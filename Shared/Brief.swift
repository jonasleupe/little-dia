import Foundation
import FoundationModels

/// The structured summary the on-device model produces for a shared link.
/// Mirrors the Figma layout: one paragraph, then a few icon-led sections.
@Generable
struct Brief: Equatable {
    @Guide(description: "One or two plain sentences saying what this is and who it's from. No preamble, no markdown.")
    var summary: String

    @Guide(description: "One to three short sections that add the most useful context: where to buy it, what people think, key facts, who is involved, dates or places. Never restate the summary.", .count(1...3))
    var sections: [Section]

    @Generable
    struct Section: Equatable {
        @Guide(description: "Two to four word title, e.g. 'Get Matic', 'People praising Matic', 'Key details'.")
        var title: String

        @Guide(description: "One to three sentences of plain text. No markdown, no bullet characters.")
        var body: String

        @Guide(description: "The icon that best fits this section.")
        var icon: Icon

        @Guide(description: "Only when the section is about buying, visiting or reading more: the shared page's own URL or a URL that appears in the content. Never invent a URL. Otherwise leave empty.")
        var linkURL: String?
    }

    @Generable
    enum Icon: Equatable {
        case buy
        case reviews
        case facts
        case people
        case date
        case place
        case warning
        case link
        case idea

        var symbolName: String {
            switch self {
            case .buy: "basket.fill"
            case .reviews: "pencil.line"
            case .facts: "info.circle"
            case .people: "person.2"
            case .date: "calendar"
            case .place: "mappin"
            case .warning: "exclamationmark.triangle"
            case .link: "link"
            case .idea: "lightbulb"
            }
        }
    }
}

extension Brief.Section {
    var link: URL? {
        guard let linkURL, let url = URL(string: linkURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.hasPrefix("http") == true else { return nil }
        return url
    }
}
