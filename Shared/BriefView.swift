import SwiftUI

/// "Summarized for you by Dia": the streaming summary paragraph followed by the
/// icon-led sections, laid out exactly like the Figma "introduction" block.
struct BriefView: View {
    @Bindable var model: ChatModel

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 16) {
                DiaCaptionRow(text: model.hasBrief || !model.isSummarizing ? "Summarized for you by Dia" : "Summarizing for you…")
                if let summary = model.brief?.summary, !summary.isEmpty {
                    DiaBodyText(summary)
                } else if model.isSummarizing || model.phase == .resolving {
                    placeholderLines
                } else if model.errorText == nil {
                    DiaBodyText("Nothing to summarize yet.")
                }
            }
            .padding(.horizontal, DiaTheme.contentInset)

            if let sections = model.brief?.sections, !sections.isEmpty {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(sections) { section in
                        SectionRow(section: section, preview: model.preview)
                    }
                }
                .padding(.horizontal, DiaTheme.contentInset)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.hasBrief)
    }

    private var placeholderLines: some View {
        VStack(alignment: .leading, spacing: 9) {
            RoundedRectangle(cornerRadius: 4).fill(DiaTheme.iconPill).frame(height: 12)
            RoundedRectangle(cornerRadius: 4).fill(DiaTheme.iconPill).frame(height: 12)
            RoundedRectangle(cornerRadius: 4).fill(DiaTheme.iconPill).frame(width: 180, height: 12)
        }
        .padding(.vertical, 4)
    }
}

private struct SectionRow: View {
    let section: BriefSnapshot.SectionSnapshot
    let preview: LinkPreview?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: (section.icon ?? .facts).symbolName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DiaTheme.secondaryLabel)
                .frame(width: 24, height: 24)
                .background(DiaTheme.iconPill, in: Circle())
                .padding(.top, -1)

            VStack(alignment: .leading, spacing: 8) {
                if let title = section.title, !title.isEmpty {
                    DiaBodyText(title, weight: .semibold)
                }
                if let body = section.body, !body.isEmpty {
                    DiaBodyText(body)
                }
                if let link = resolvedLink {
                    Link(destination: link) {
                        HStack(spacing: 5) {
                            favicon
                            Text(hostLabel(for: link))
                                .font(DiaTheme.body)
                                .tracking(DiaTheme.bodyTracking)
                                .underline()
                                .foregroundStyle(DiaTheme.label)
                        }
                    }
                }
            }
        }
    }

    /// Model-provided link, but only if it points somewhere real; otherwise, for a
    /// "buy" section on a product page, fall back to the shared page itself.
    private var resolvedLink: URL? {
        if let raw = section.linkURL,
           let link = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
           link.scheme?.hasPrefix("http") == true {
            return link
        }
        if section.icon == .buy, let preview, preview.kind == .product {
            return preview.canonicalURL ?? preview.url
        }
        return nil
    }

    private func hostLabel(for url: URL) -> String {
        let host = url.host ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private var favicon: some View {
        let sameSite = resolvedLink?.host == (preview?.canonicalURL ?? preview?.url)?.host
        let url = sameSite ? preview?.faviconURL : resolvedLink.flatMap { link in
            var c = URLComponents()
            c.scheme = link.scheme
            c.host = link.host
            c.path = "/favicon.ico"
            return c.url
        }
        return AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit()
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 11))
                    .foregroundStyle(DiaTheme.secondaryLabel)
            }
        }
        .frame(width: 16, height: 16)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
