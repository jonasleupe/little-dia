import SwiftUI

/// The floating "Ask anything..." bar: Dia mark, multiline field, mic (hidden
/// once there's text) and the arrow-up send button.
struct ComposerBar: View {
    @Bindable var model: ChatModel
    @Bindable var dictation: DictationController

    @FocusState private var focused: Bool

    private var hasText: Bool { !model.input.isEmpty }
    private var isEnabled: Bool { model.availability == .available }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            bar

            if let error = dictation.errorText {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(DiaTheme.captionLabel)
                    .padding(.horizontal, 12)
                    .transition(.opacity)
            }
        }
        .onChange(of: dictation.transcript) { _, transcript in
            if dictation.isListening || !transcript.isEmpty { model.input = transcript }
        }
        .onChange(of: model.isResponding) { _, responding in
            if responding { dictation.stop() }
        }
    }

    private var bar: some View {
        HStack(alignment: .bottom, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Image("DiaMark")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 14)

                TextField(
                    "",
                    text: $model.input,
                    prompt: Text(dictation.isListening ? "Listening…" : "Ask anything...")
                        .foregroundStyle(DiaTheme.placeholder),
                    axis: .vertical
                )
                .font(DiaTheme.input)
                .tracking(-0.119)
                .lineLimit(1...4)
                .focused($focused)
                .disabled(!isEnabled)
                .submitLabel(.send)
                .onSubmit { if model.canSend { model.send() } }
                .foregroundStyle(DiaTheme.label)
            }
            .padding(.leading, DiaTheme.contentInset)
            .padding(.vertical, 14)
            .frame(minHeight: 52)

            HStack(spacing: 4) {
                if !hasText || dictation.isListening {
                    Button {
                        Task { await dictation.toggle() }
                    } label: {
                        Image(systemName: dictation.isListening ? "stop.fill" : "microphone")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(dictation.isListening ? Color.red : DiaTheme.placeholder)
                            .frame(width: DiaTheme.toolbarButton, height: DiaTheme.toolbarButton)
                            .contentShape(Circle())
                            .symbolEffect(.pulse, isActive: dictation.isListening)
                    }
                    .disabled(!isEnabled)
                    .accessibilityLabel(dictation.isListening ? "Stop dictation" : "Dictate")
                    .transition(.scale.combined(with: .opacity))
                }

                Button {
                    model.send()
                    focused = true
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(model.canSend ? DiaTheme.label : DiaTheme.sendIdleGlyph)
                        .frame(width: DiaTheme.toolbarButton, height: DiaTheme.toolbarButton)
                        .background(DiaTheme.sendBackground, in: Circle())
                }
                .disabled(!model.canSend)
                .accessibilityLabel("Send")
            }
            .padding(8)
            .animation(.snappy(duration: 0.18), value: hasText)
            .animation(.snappy(duration: 0.18), value: model.canSend)
        }
        .background(DiaTheme.surface, in: RoundedRectangle(cornerRadius: DiaTheme.composerRadius))
        .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 4)
    }
}
