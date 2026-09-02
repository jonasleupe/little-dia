import SwiftUI
import FoundationModels

@main
struct ShareExperimentApp: App {
    var body: some Scene {
        WindowGroup {
            HostView()
                .task {
                    let args = ProcessInfo.processInfo.arguments
                    guard args.contains("-selftest") || args.contains("-probetest") else { return }
                    setvbuf(stdout, nil, _IONBF, 0)   // unbuffered so console capture is reliable
                    if args.contains("-selftest") { await Self.runSelfTest() }
                    if args.contains("-probetest") { await Self.runProbeTest() }
                }
        }
    }

    /// Launch with `-selftest` to exercise the resolver + the on-device model from the console.
    /// Pass `-url <url>` to test a specific link; defaults to a tweet, a product page and an article.
    static func runSelfTest() async {
        let args = ProcessInfo.processInfo.arguments
        var urls = [
            "https://x.com/jack/status/20",
            "https://maticrobots.com/product",
            "https://en.wikipedia.org/wiki/Robotic_vacuum_cleaner",
        ]
        if let i = args.firstIndex(of: "-url"), i + 1 < args.count {
            urls = [args[i + 1]]
        }

        for urlString in urls {
            guard let url = URL(string: urlString) else { continue }
            print("SELFTEST ===== \(urlString)")
            let preview = await LinkResolver.resolve(url: url, sharedText: nil)
            print("SELFTEST kind: \(preview.kind.rawValue)")
            print("SELFTEST title: \(preview.title ?? "<none>")")
            print("SELFTEST site: \(preview.siteName ?? "<none>")  favicon: \(preview.faviconURL?.absoluteString ?? "<none>")")
            print("SELFTEST author: \(preview.author.map { "\($0.name) @\($0.handle ?? "-") verified=\($0.isVerified) avatar=\($0.avatarURL?.absoluteString ?? "-")" } ?? "<none>")")
            print("SELFTEST date: \(preview.displayDate ?? "<none>")  price: \(preview.priceText ?? "<none>")")
            print("SELFTEST image: \(preview.imageURL?.absoluteString ?? "<none>")")
            print("SELFTEST description: \(preview.description ?? "<none>")")
            print("SELFTEST body(\(preview.bodyText?.count ?? 0)): \(preview.bodyText?.prefix(300) ?? "<none>")")
        }

        // Full flow for the first URL: brief + one follow-up.
        guard let url = URL(string: urls[0]) else { return }
        let model = ChatModel(content: SharedContent(url: url, text: nil, rawItems: []))
        print("SELFTEST availability: \(model.availability)")
        while model.phase == .resolving || model.isSummarizing {
            try? await Task.sleep(for: .milliseconds(200))
        }
        print("SELFTEST summary: \(model.brief?.summary ?? "<none>")")
        for section in model.brief?.sections ?? [] {
            print("SELFTEST section [\(section.icon.map { "\($0)" } ?? "-")] \(section.title ?? "-") — \(section.body ?? "-") \(section.linkURL.map { "→ \($0)" } ?? "")")
        }
        print("SELFTEST error: \(model.errorText ?? "<none>")")

        guard model.availability == .available else { print("SELFTEST done"); return }
        model.send("In one sentence, what is this?")
        while model.isResponding { try? await Task.sleep(for: .milliseconds(200)) }
        print("SELFTEST reply (\(model.messages.last?.thinkingSeconds ?? 0)s): \(model.messages.last?.text ?? "<none>")")
        print("SELFTEST error: \(model.errorText ?? "<none>")")
        print("SELFTEST done")
    }

    /// Launch with `-probetest` to run the mic probe from the console.
    static func runProbeTest() async {
        print("PROBE starting…")
        let probe = AudioProbe()
        await probe.start()
        for _ in 0..<24 {
            try? await Task.sleep(for: .milliseconds(300))
            if probe.steps.allSatisfy({ $0.state == .ok || $0.state == .failed }) { break }
        }
        for step in probe.steps {
            print("PROBE \(step.state) — \(step.name)\(step.detail.map { " · \($0)" } ?? "")")
        }
        print("PROBE level: \(String(format: "%.3f", probe.level))  transcript: \(probe.transcript.isEmpty ? "<none>" : probe.transcript)")
        print("PROBE summary: \(probe.summary ?? "<all steps passed>")")
        probe.stop()
        print("PROBE done")
    }
}
