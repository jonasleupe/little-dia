import Foundation
import Observation
import FoundationModels

/// Drives one share-sheet session: resolve the link, stream a structured brief
/// from Apple's on-device model, then answer follow-up questions in the same
/// model session so the brief stays in context. Nothing about the content is
/// sent to a cloud model.
@MainActor
@Observable
final class ChatModel {

    enum Availability: Equatable {
        case checking
        case available
        case unavailable(String)
    }

    enum Phase: Equatable {
        case resolving
        case ready
    }

    struct Message: Identifiable {
        enum Role { case user, assistant }
        let id = UUID()
        let role: Role
        var text: String
        var isStreaming: Bool = false
        /// Seconds the on-device model took to finish this reply ("Thought for 14s").
        var thinkingSeconds: Int?
    }

    private(set) var availability: Availability = .checking
    private(set) var phase: Phase = .resolving
    private(set) var preview: LinkPreview?
    private(set) var brief: BriefSnapshot?
    private(set) var isSummarizing = false
    /// Sections written by OpenRouter when the on-device model isn't available.
    private(set) var webSections: [BriefSnapshot.SectionSnapshot] = []
    private(set) var isResearching = false
    var webErrorText: String?
    private(set) var messages: [Message] = []
    private(set) var isResponding = false
    var errorText: String?
    var input: String = ""
    var isBookmarked = false

    let content: SharedContent
    /// Debug aid: stream canned answers instead of calling the model, so the
    /// design can be reviewed on machines without Apple Intelligence.
    let usesSampleAnswers: Bool
    /// Set when the user saved an OpenRouter key. The brief still comes from the
    /// on-device model; only follow-up questions go to Luna (with web search).
    /// OpenRouter also fills in when Apple Intelligence isn't available at all.
    private let openRouter: OpenRouterClient?
    private var session: LanguageModelSession?
    private var loadTask: Task<Void, Never>?

    var usesWeb: Bool { openRouter != nil }

    init(content: SharedContent, usesSampleAnswers: Bool = false) {
        self.content = content
        self.usesSampleAnswers = usesSampleAnswers
        self.openRouter = usesSampleAnswers ? nil : OpenRouterKeyStore.load().map { OpenRouterClient(apiKey: $0) }
        refreshAvailability()
        loadTask = Task { [weak self] in await self?.load() }
    }

    var canSend: Bool {
        (availability == .available || usesWeb)
            && phase == .ready
            && !isResponding
            && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True once the brief has a summary worth showing.
    var hasBrief: Bool { !(brief?.summary?.isEmpty ?? true) }

    // MARK: - Loading

    private func load() async {
        phase = .resolving
        if let url = content.url {
            preview = await LinkResolver.resolve(url: url, sharedText: content.text)
        }
        phase = .ready
        startSession()
        await summarize()
    }

    /// Re-runs the fetch (for when the page or mirror was briefly unreachable).
    func retryLoad() {
        loadTask?.cancel()
        brief = nil
        webSections = []
        webErrorText = nil
        messages.removeAll()
        errorText = nil
        loadTask = Task { [weak self] in await self?.load() }
    }

    // MARK: - Availability

    func refreshAvailability() {
        if usesSampleAnswers { availability = .available; return }
        switch SystemLanguageModel.default.availability {
        case .available:
            availability = .available
        case .unavailable(let reason):
            availability = .unavailable(Self.describe(reason))
        @unknown default:
            availability = .unavailable("The on-device model is unavailable on this device.")
        }
    }

    static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "This device isn't eligible for Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in Settings, then reopen this."
        case .modelNotReady:
            return "The on-device model is still downloading. Try again in a bit."
        @unknown default:
            return "The on-device model is unavailable right now."
        }
    }

    // MARK: - Session

    private var contextBlock: String {
        if let preview { return preview.contextBlock }
        var parts: [String] = []
        if let url = content.url { parts.append("URL: \(url.absoluteString)") }
        if let text = content.text, !text.isEmpty { parts.append("Shared text:\n\(text)") }
        return parts.isEmpty ? "(the share sheet provided nothing readable)" : parts.joined(separator: "\n\n")
    }

    private func startSession() {
        guard availability == .available, !usesSampleAnswers else { return }
        session = LanguageModelSession(instructions: Self.instructions(context: contextBlock))
    }

    private static func instructions(context: String) -> String {
        """
        You are Dia, a concise assistant living inside a share-sheet window on iOS. \
        The user just tapped "Share" on something in another app (a post, an article, \
        a product page) and wants to understand it without leaving the sheet.

        Ground everything in the shared content below. Write plain text: no markdown, \
        no headings, no bullet characters. Keep replies short and scannable, usually \
        one to three sentences. If the content doesn't answer a question, say so in a \
        few words and add what you can from general knowledge. Never invent URLs, \
        prices or dates that aren't in the content.

        SHARED CONTENT:
        \(context)
        """
    }

    // MARK: - Brief

    private func summarize() async {
        if usesSampleAnswers { await SampleAnswers.streamBrief(into: self); return }
        guard let session, availability == .available else {
            if usesWeb { await summarizeOnWeb() }
            return
        }
        isSummarizing = true
        errorText = nil
        brief = nil

        let kind = preview?.kind ?? .page
        let guidance: String
        switch kind {
        case .product:
            guidance = "This is a product page. Sections should cover where to buy it (link to the shared page) and what stands out or what reviewers say."
        case .post:
            guidance = "This is a social post. The summary should say who posted it and what it's about. Sections should add context: what the thing mentioned is, why it matters, where to find or buy it if relevant."
        case .article:
            guidance = "This is an article. Sections should give the key points and why they matter."
        case .page:
            guidance = "Sections should give the most useful facts about this page."
        }

        do {
            let stream = session.streamResponse(
                to: "Write the brief for the shared content. \(guidance)",
                generating: Brief.self,
                options: GenerationOptions(temperature: 0.3)
            )
            for try await partial in stream {
                brief = BriefSnapshot(partial.content)
            }
        } catch {
            errorText = Self.friendly(error)
        }
        isSummarizing = false
    }

    // MARK: - Web (OpenRouter)

    /// No on-device model: let OpenRouter write the summary and the sections.
    private func summarizeOnWeb() async {
        guard let openRouter else { return }
        isSummarizing = true
        isResearching = true
        webErrorText = nil
        do {
            let sections = try await openRouter.research(
                context: contextBlock,
                existingSummary: nil,
                kind: preview?.kind ?? .page
            )
            // First section doubles as the summary paragraph when the model can't run locally.
            var snapshot = BriefSnapshot()
            snapshot.summary = preview?.description ?? preview?.title ?? preview?.bodyText.map { String($0.prefix(220)) }
            snapshot.sections = Self.snapshots(from: sections)
            brief = snapshot
        } catch {
            webErrorText = error.localizedDescription
        }
        isSummarizing = false
        isResearching = false
    }

    private static func snapshots(from sections: [OpenRouterClient.ResearchSection]) -> [BriefSnapshot.SectionSnapshot] {
        sections.enumerated().map { index, section in
            BriefSnapshot.SectionSnapshot(
                id: 100 + index,
                title: section.title,
                body: section.body,
                icon: Brief.Icon(name: section.icon) ?? .facts,
                linkURL: section.url
            )
        }
    }

    /// The transcript as OpenRouter messages: context + brief as the system prompt,
    /// then the conversation so far (including the just-appended user turn).
    private func webMessages() -> [OpenRouterClient.ChatMessage] {
        var system = Self.instructions(context: contextBlock)
        var known: [String] = []
        if let summary = brief?.summary, !summary.isEmpty { known.append(summary) }
        for section in (brief?.sections ?? []) + webSections {
            if let title = section.title, let body = section.body { known.append("\(title): \(body)") }
        }
        if !known.isEmpty {
            system += "\n\nWHAT THE USER HAS ALREADY BEEN TOLD:\n" + known.joined(separator: "\n")
        }
        system += "\n\nYou can search the web. Use it for anything current (availability, prices, news) and mention the source site in a few words."
        var out: [OpenRouterClient.ChatMessage] = [.init(role: .system, content: system)]
        for message in messages where !(message.role == .assistant && message.text.isEmpty) {
            out.append(.init(role: message.role == .user ? .user : .assistant, content: message.text))
        }
        return out
    }

    // MARK: - Sending

    func send(_ overridePrompt: String? = nil) {
        let prompt = (overridePrompt ?? input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isResponding else { return }
        if usesSampleAnswers {
            if overridePrompt == nil { input = "" }
            SampleAnswers.reply(to: prompt, in: self)
            return
        }
        if let openRouter {
            if overridePrompt == nil { input = "" }
            errorText = nil
            messages.append(.init(role: .user, text: prompt))
            let assistantIndex = messages.count
            messages.append(.init(role: .assistant, text: "", isStreaming: true))
            isResponding = true
            let started = Date()
            let history = webMessages()
            Task { [weak self] in
                guard let self else { return }
                do {
                    for try await delta in openRouter.streamAnswer(messages: history) {
                        self.messages[assistantIndex].text += delta
                    }
                } catch {
                    if self.messages[assistantIndex].text.isEmpty { self.messages[assistantIndex].text = "" }
                    self.errorText = error.localizedDescription
                }
                self.messages[assistantIndex].isStreaming = false
                self.messages[assistantIndex].thinkingSeconds = max(1, Int(Date().timeIntervalSince(started).rounded()))
                self.isResponding = false
            }
            return
        }

        guard let session else { return }

        if overridePrompt == nil { input = "" }
        errorText = nil
        messages.append(.init(role: .user, text: prompt))

        let assistantIndex = messages.count
        messages.append(.init(role: .assistant, text: "", isStreaming: true))
        isResponding = true
        let started = Date()

        Task { [weak self] in
            guard let self else { return }
            do {
                let stream = session.streamResponse(to: prompt)
                for try await partial in stream {
                    self.messages[assistantIndex].text = partial.content
                }
            } catch {
                self.messages[assistantIndex].text = ""
                self.errorText = Self.friendly(error)
            }
            self.messages[assistantIndex].isStreaming = false
            self.messages[assistantIndex].thinkingSeconds = max(1, Int(Date().timeIntervalSince(started).rounded()))
            self.isResponding = false
        }
    }

    /// Recreates the model session (after the context window fills up), keeping
    /// the brief as context so the conversation still knows what was shared.
    func startOver() {
        guard availability == .available, !usesSampleAnswers else { messages.removeAll(); errorText = nil; return }
        var context = contextBlock
        if let summary = brief?.summary, !summary.isEmpty {
            context += "\n\nEARLIER BRIEF:\n\(summary)"
        }
        session = LanguageModelSession(instructions: Self.instructions(context: context))
        messages.removeAll()
        errorText = nil
        isResponding = false
    }

    static func friendly(_ error: Error) -> String {
        if let generation = error as? LanguageModelSession.GenerationError {
            switch generation {
            case .exceededContextWindowSize:
                return "This conversation outgrew the on-device model's memory. Start over to keep going."
            case .guardrailViolation:
                return "The on-device safety guardrail blocked that request."
            case .unsupportedLanguageOrLocale:
                return "The on-device model doesn't support this language yet."
            case .assetsUnavailable:
                return "The on-device model's assets aren't installed yet. On Simulator, enable Apple Intelligence on your Mac (System Settings → Apple Intelligence & Siri) and reboot the simulator."
            case .rateLimited:
                return "The on-device model is rate-limited right now. Try again in a moment."
            default:
                return "The on-device model couldn't complete the request (\(generation))."
            }
        }
        let nsError = error as NSError
        if nsError.domain.contains("FoundationModels") || nsError.localizedDescription.contains("GenerationError") {
            return "The on-device model couldn't generate a response. On Simulator, Apple Intelligence must be enabled on the host Mac (System Settings → Apple Intelligence & Siri). (\(nsError.domain) \(nsError.code))"
        }
        return error.localizedDescription
    }
}

// MARK: - Brief snapshot (decoupled from FoundationModels' partial types)

struct BriefSnapshot: Equatable {
    var summary: String?
    var sections: [SectionSnapshot] = []

    struct SectionSnapshot: Identifiable, Equatable {
        let id: Int
        var title: String?
        var body: String?
        var icon: Brief.Icon?
        var linkURL: String?
    }

    init(summary: String? = nil, sections: [SectionSnapshot] = []) {
        self.summary = summary
        self.sections = sections
    }

    init(_ partial: Brief.PartiallyGenerated) {
        summary = partial.summary
        sections = (partial.sections ?? []).enumerated().map { index, section in
            SectionSnapshot(id: index, title: section.title, body: section.body, icon: section.icon, linkURL: section.linkURL)
        }
    }
}

// MARK: - Sample answers (design review without Apple Intelligence)

@MainActor
enum SampleAnswers {
    static let brief = BriefSnapshot(
        summary: "Brooke LeBlanc posts about receiving a special delivery of a Matic cleaning robot, expressing enthusiasm for robots handling household chores.",
        sections: [
            .init(id: 0, title: "Get Matic",
                  body: "You can buy a Matic robot vacuum and mop directly from the company’s official site at",
                  icon: .buy, linkURL: "https://maticrobots.com/product"),
            .init(id: 1, title: "People praising Matic",
                  body: "Reviews from WIRED, Verge, and Forbes praise its quiet operation, adaptive mapping, and reduced maintenance needs, though its height limits access under low furniture and edge cleaning can be inconsistent.",
                  icon: .reviews, linkURL: nil),
        ]
    )

    static func streamBrief(into model: ChatModel) async {
        model.setSummarizing(true)
        var snapshot = BriefSnapshot()
        let words = brief.summary?.split(separator: " ") ?? []
        for i in words.indices {
            try? await Task.sleep(for: .milliseconds(40))
            snapshot.summary = words[...i].joined(separator: " ")
            model.setBrief(snapshot)
        }
        for section in brief.sections {
            try? await Task.sleep(for: .milliseconds(350))
            snapshot.sections.append(section)
            model.setBrief(snapshot)
        }
        model.setSummarizing(false)
    }

    static func reply(to prompt: String, in model: ChatModel) {
        let answer = "No official availability in Europe yet. Matic currently only ships to US addresses."
        model.beginReply(to: prompt)
        Task {
            try? await Task.sleep(for: .seconds(3))   // long enough to see the thinking state
            let words = answer.split(separator: " ")
            for i in words.indices {
                try? await Task.sleep(for: .milliseconds(45))
                model.updateReply(words[...i].joined(separator: " "))
            }
            model.finishReply(seconds: 14)
        }
    }
}

extension ChatModel {
    func setSummarizing(_ value: Bool) { isSummarizing = value }
    func setBrief(_ value: BriefSnapshot) { brief = value }

    func beginReply(to prompt: String) {
        errorText = nil
        messages.append(.init(role: .user, text: prompt))
        messages.append(.init(role: .assistant, text: "", isStreaming: true))
        isResponding = true
    }
    func updateReply(_ text: String) {
        guard let last = messages.indices.last else { return }
        messages[last].text = text
    }
    func finishReply(seconds: Int) {
        guard let last = messages.indices.last else { return }
        messages[last].isStreaming = false
        messages[last].thinkingSeconds = seconds
        isResponding = false
    }
}
