import Foundation

/// Everything we managed to learn about a shared link, in a shape both the UI
/// (preview card) and the on-device model (context block) can use.
struct LinkPreview: Sendable, Equatable {

    enum Kind: String, Sendable {
        case post, article, product, page
    }

    struct Author: Sendable, Equatable {
        var name: String
        var handle: String?
        var avatarURL: URL?
        var isVerified: Bool = false
    }

    var kind: Kind
    var url: URL
    var canonicalURL: URL?
    var title: String?
    var description: String?
    var siteName: String?
    var faviconURL: URL?
    var imageURL: URL?
    var author: Author?
    var date: Date?
    /// Readable text, already capped so it fits the on-device model's window.
    var bodyText: String?
    var priceText: String?
    var quotedText: String?

    /// Host without "www." — used as the link label and site fallback.
    var displayHost: String {
        let host = (canonicalURL ?? url).host ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var displayDate: String? {
        guard let date else { return nil }
        return Self.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        return f
    }()

    /// Whether there's anything worth drawing a card for.
    var hasCardContent: Bool {
        title != nil || description != nil || imageURL != nil || author != nil || (bodyText?.isEmpty == false)
    }

    /// The block handed to the model as grounding context.
    var contextBlock: String {
        var lines: [String] = []
        lines.append("Type: \(kind.rawValue)")
        lines.append("URL: \((canonicalURL ?? url).absoluteString)")
        if let siteName { lines.append("Site: \(siteName)") }
        if let author {
            var a = "Author: \(author.name)"
            if let handle = author.handle { a += " (@\(handle))" }
            lines.append(a)
        }
        if let displayDate { lines.append("Date: \(displayDate)") }
        if let title { lines.append("Title: \(title)") }
        if let priceText { lines.append("Price: \(priceText)") }
        if let description, description != bodyText { lines.append("Description: \(description)") }
        if let bodyText, !bodyText.isEmpty { lines.append("Content:\n\(bodyText)") }
        if let quotedText { lines.append("Quoted post:\n\(quotedText)") }
        return lines.joined(separator: "\n")
    }

    /// Fallback when nothing could be fetched: at least the URL and any text the
    /// share sheet handed over.
    static func bare(url: URL, text: String?) -> LinkPreview {
        LinkPreview(kind: .page, url: url, bodyText: text)
    }
}
