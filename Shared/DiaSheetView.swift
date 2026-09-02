import SwiftUI

/// The full "Little Dia" sheet: outer gray chrome with the faint rainbow bleed,
/// the toolbar (close · title · bookmark) and the white inner sheet. Used by the
/// share extension and by the host app's rehearsal sheet.
struct DiaSheetView: View {
    @Bindable var model: ChatModel
    let onClose: () -> Void

    var body: some View {
        ZStack {
            DiaTheme.sheetBackground
                .ignoresSafeArea()

            bleed
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Grabber: 58×4 at 5pt from the top, as in the Figma "Grabber" frame.
                Capsule()
                    .fill(DiaTheme.grabber)
                    .frame(width: 58, height: 4)
                    .padding(.top, 5)

                toolbar
                    .padding(.horizontal, DiaTheme.contentInset)
                    .padding(.top, 7)   // 5 + 4 + 7 = 16pt content inset from the sheet edge
                    .padding(.bottom, 10)

                InnerSheetView(model: model)
                    .padding(.horizontal, 8)
            }
        }
    }

    /// Rectangle 104 in Figma: a tall rainbow gradient, blurred and nearly transparent.
    private var bleed: some View {
        GeometryReader { geo in
            DiaTheme.bleedGradient
                .frame(width: geo.size.width * 1.4, height: geo.size.height * 1.3)
                .blur(radius: 24)
                .opacity(0.08)
                .position(x: geo.size.width / 2, y: geo.size.height * 0.75)
        }
        .allowsHitTesting(false)
    }

    private var toolbar: some View {
        ZStack {
            Text("Little Dia")
                .font(DiaTheme.headline)
                .tracking(-0.43)
                .foregroundStyle(DiaTheme.title)

            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DiaTheme.secondaryLabel)
                        .frame(width: DiaTheme.toolbarButton, height: DiaTheme.toolbarButton)
                        .contentShape(Circle())
                }
                .accessibilityLabel("Close")

                Spacer()

                Button {
                    withAnimation(.snappy(duration: 0.2)) { model.isBookmarked.toggle() }
                } label: {
                    Image(systemName: model.isBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DiaTheme.surface)
                        .frame(width: DiaTheme.toolbarButton, height: DiaTheme.toolbarButton)
                        .background(DiaTheme.bookmark, in: Circle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(model.isBookmarked ? "Remove bookmark" : "Bookmark")
            }
        }
        .frame(height: 44)
    }
}
