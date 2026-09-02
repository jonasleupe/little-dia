import SwiftUI

/// Follow-up questions and answers, continuing the brief's list: the user's
/// question as a right-aligned bubble, Dia's reply as caption + paragraph.
struct ConversationView: View {
    @Bindable var model: ChatModel

    var body: some View {
        if !model.messages.isEmpty {
            VStack(alignment: .leading, spacing: 32) {
                ForEach(model.messages) { message in
                    switch message.role {
                    case .user:
                        userBubble(message.text)
                    case .assistant:
                        reply(message)
                    }
                }
            }
        }
    }

    private func userBubble(_ text: String) -> some View {
        HStack {
            Spacer(minLength: 48)
            Text(text)
                .font(DiaTheme.body)
                .tracking(DiaTheme.bodyTracking)
                .lineSpacing(DiaTheme.bodyLineSpacing)
                .foregroundStyle(DiaTheme.label)
                .padding(16)
                .background(DiaTheme.userBubble, in: RoundedRectangle(cornerRadius: DiaTheme.bubbleRadius))
        }
        .padding(.horizontal, DiaTheme.contentInset)
    }

    private func reply(_ message: ChatModel.Message) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            DiaCaptionRow(text: message.isStreaming
                          ? "Thinking…"
                          : "Thought for \(message.thinkingSeconds ?? 1)s")

            if message.text.isEmpty && message.isStreaming {
                ProgressView()
                    .controlSize(.small)
                    .tint(DiaTheme.secondaryLabel)
            } else if !message.text.isEmpty {
                DiaBodyText(message.text)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, DiaTheme.contentInset)
    }
}
