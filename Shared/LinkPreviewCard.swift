import SwiftUI

/// The "Host Card": what was shared, rendered like the source app would show it.
/// X posts get the avatar / name / date / text / media layout; everything else
/// gets an Open Graph card.
struct LinkPreviewCard: View {
    let preview: LinkPreview?
    let isLoading: Bool

    var body: some View {
        Group {
            if let preview, preview.hasCardContent {
                card(for: preview)
            } else if isLoading {
                skeleton
            } else if let preview {
                bareCard(preview)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Layouts

    @ViewBuilder
    private func card(for preview: LinkPreview) -> some View {
        Group {
            if preview.kind == .post, let author = preview.author {
                postCard(preview, author: author)
            } else {
                pageCard(preview)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DiaTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: DiaTheme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DiaTheme.cardRadius)
                .strokeBorder(DiaTheme.hairline, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.07), radius: 4, x: 0, y: 4)
    }

    private func postCard(_ preview: LinkPreview, author: LinkPreview.Author) -> some View {
        HStack(alignment: .top, spacing: 10) {
            avatar(author.avatarURL)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(author.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(DiaTheme.label)
                        .lineLimit(1)
                    if author.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: 0x1D9BF0))
                    }
                    if let date = preview.displayDate {
                        Text("· \(date)")
                            .font(.system(size: 14))
                            .foregroundStyle(DiaTheme.secondaryLabel)
                            .lineLimit(1)
                    }
                }

                if let text = preview.bodyText, !text.isEmpty {
                    Text(text)
                        .font(.system(size: 15))
                        .foregroundStyle(DiaTheme.label)
                        .lineSpacing(3)
                        .lineLimit(8)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let quoted = preview.quotedText {
                    Text(quoted)
                        .font(.system(size: 14))
                        .foregroundStyle(DiaTheme.secondaryLabel)
                        .lineLimit(3)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(DiaTheme.hairline) }
                }

                if let imageURL = preview.imageURL {
                    remoteImage(imageURL, height: 150, radius: 12)
                        .padding(.top, 2)
                }
            }
        }
        .padding(10)
        .padding(.trailing, 4)
    }

    private func pageCard(_ preview: LinkPreview) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let imageURL = preview.imageURL {
                remoteImage(imageURL, height: 150, radius: 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                if let title = preview.title {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DiaTheme.label)
                        .lineLimit(2)
                }
                if let description = preview.description, description != preview.title {
                    Text(description)
                        .font(.system(size: 14))
                        .foregroundStyle(DiaTheme.secondaryLabel)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    favicon(preview.faviconURL)
                    Text(preview.siteName ?? preview.displayHost)
                        .font(.system(size: 13))
                        .foregroundStyle(DiaTheme.secondaryLabel)
                        .lineLimit(1)
                    if let price = preview.priceText {
                        Text("·").foregroundStyle(DiaTheme.secondaryLabel)
                        Text(price)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DiaTheme.label)
                    }
                }
                .padding(.top, 2)
            }
            .padding(12)
        }
    }

    private func bareCard(_ preview: LinkPreview) -> some View {
        HStack(spacing: 8) {
            favicon(preview.faviconURL)
            Text(preview.url.absoluteString)
                .font(.system(size: 14))
                .foregroundStyle(DiaTheme.secondaryLabel)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DiaTheme.iconPill, in: RoundedRectangle(cornerRadius: DiaTheme.bubbleRadius))
    }

    private var skeleton: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(DiaTheme.iconPill).frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4).fill(DiaTheme.iconPill).frame(width: 140, height: 12)
                RoundedRectangle(cornerRadius: 4).fill(DiaTheme.iconPill).frame(height: 12)
                RoundedRectangle(cornerRadius: 4).fill(DiaTheme.iconPill).frame(width: 220, height: 12)
                RoundedRectangle(cornerRadius: 12).fill(DiaTheme.iconPill).frame(height: 120).padding(.top, 4)
            }
        }
        .padding(10)
        .background(DiaTheme.surface, in: RoundedRectangle(cornerRadius: DiaTheme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DiaTheme.cardRadius).strokeBorder(DiaTheme.hairline, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.07), radius: 4, x: 0, y: 4)
        .redacted(reason: .placeholder)
    }

    // MARK: - Pieces

    private func avatar(_ url: URL?) -> some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Circle().fill(DiaTheme.iconPill)
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(Circle())
    }

    private func favicon(_ url: URL?) -> some View {
        AsyncImage(url: url) { phase in
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

    private func remoteImage(_ url: URL, height: CGFloat, radius: CGFloat) -> some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Rectangle().fill(DiaTheme.iconPill)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}
