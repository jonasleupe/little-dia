import SwiftUI

/// The white inner sheet: a dashed content container that scrolls the preview
/// card, the brief and the conversation, with the composer floating above it.
struct InnerSheetView: View {
    @Bindable var model: ChatModel
    @State private var dictation = DictationController()
    @State private var composerHeight: CGFloat = 60

    private let inset: CGFloat = 8
    private let composerBottom: CGFloat = 12

    var body: some View {
        ZStack(alignment: .bottom) {
            // The dashed container stops halfway down the composer, which floats
            // over its bottom edge (Figma: Content ends 62pt up, input sits 36pt up).
            dashedContent
                .padding(.horizontal, inset)
                .padding(.top, inset)
                .padding(.bottom, composerBottom + composerHeight / 2)

            ComposerBar(model: model, dictation: dictation)
                .padding(.horizontal, DiaTheme.contentInset)
                .padding(.bottom, composerBottom)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { composerHeight = $0 }
        }
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: DiaTheme.sheetRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: DiaTheme.sheetRadius
            )
            .fill(DiaTheme.surface)
            .ignoresSafeArea(edges: .bottom)
        }
        .onDisappear { dictation.stop() }
    }

    private var dashedContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    LinkPreviewCard(preview: model.preview, isLoading: model.phase == .resolving)
                        .padding(.horizontal, inset)

                    if case .unavailable(let reason) = model.availability {
                        unavailable(reason)
                    } else {
                        BriefView(model: model)
                    }

                    ConversationView(model: model)

                    if let errorText = model.errorText {
                        errorRow(errorText)
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.top, inset)
                .padding(.bottom, 12)
            }
            .safeAreaPadding(.bottom, composerHeight / 2 + 20)
            .scrollDismissesKeyboard(.interactively)
            .clipShape(RoundedRectangle(cornerRadius: DiaTheme.contentRadius))
            .onChange(of: model.messages.last?.text) {
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: model.messages.count) {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: DiaTheme.contentRadius)
                .strokeBorder(DiaTheme.dashedBorder, style: StrokeStyle(lineWidth: 0.92, dash: [4, 4]))
        }
    }

    private func unavailable(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            DiaCaptionRow(text: "Dia can't summarize on this device")
            DiaBodyText(reason)
        }
        .padding(.horizontal, DiaTheme.contentInset)
    }

    private func errorRow(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                Text(text)
                    .font(DiaTheme.caption)
                    .foregroundStyle(DiaTheme.captionLabel)
            }
            if text.contains("Start over") {
                Button("Start over") { model.startOver() }
                    .font(DiaTheme.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, DiaTheme.contentInset)
    }
}
