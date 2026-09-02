import SwiftUI
import FoundationModels

/// The host app is deliberately thin: it exists so iOS installs the extension,
/// reports whether the on-device model is usable, and lets you rehearse the
/// share flow without actually opening X every time.
struct HostView: View {
    @State private var urlString = "https://x.com/jack/status/20"
    @State private var pastedText = ""
    @State private var simulated: SharedContent?
    @State private var useSampleAnswers = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Apple Intelligence") {
                    AvailabilityRow()
                }

                Section {
                    Text("""
                    Open X, Safari or any app, tap Share, and choose **Little Dia**. \
                    A sheet opens with a preview of what you shared, a summary from \
                    Apple's on-device model, and a place to ask follow-up questions. \
                    Only the page itself is fetched; nothing is sent to a cloud model.
                    """)
                    .font(.footnote)
                } header: {
                    Text("How it works")
                }

                Section("Rehearse the flow") {
                    TextField("URL", text: $urlString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Shared text (optional)", text: $pastedText, axis: .vertical)
                        .lineLimit(2...5)
                    Toggle("Use sample answers (design review)", isOn: $useSampleAnswers)
                    Button("Open Little Dia") {
                        simulated = SharedContent(
                            url: URL(string: urlString.trimmingCharacters(in: .whitespaces)),
                            text: pastedText.isEmpty ? nil : pastedText,
                            rawItems: []
                        )
                    }
                    .disabled(URL(string: urlString.trimmingCharacters(in: .whitespaces)) == nil && pastedText.isEmpty)
                }

                Section {
                    ForEach(Self.samples, id: \.url) { sample in
                        Button {
                            urlString = sample.url
                            pastedText = ""
                            simulated = SharedContent(url: URL(string: sample.url), text: nil, rawItems: [])
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sample.label)
                                Text(sample.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .tint(.primary)
                    }
                } header: {
                    Text("Samples")
                }

                Section {
                    NavigationLink {
                        ProbeView().navigationTitle("Mic probe")
                    } label: {
                        Label("Microphone probe", systemImage: "mic")
                    }
                } header: {
                    Text("Diagnostics")
                } footer: {
                    Text("Checks whether an audio session can be opened here. Dictation inside the share sheet depends on the same steps passing on a real device.")
                }
            }
            .navigationTitle("Little Dia")
            .sheet(item: Binding(
                get: { simulated.map(IdentifiedContent.init) },
                set: { simulated = $0?.content }
            )) { identified in
                RehearsalSheet(content: identified.content, usesSampleAnswers: useSampleAnswers) { simulated = nil }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .presentationBackground(DiaTheme.sheetBackground)
            }
        }
    }

    private static let samples: [(label: String, url: String)] = [
        ("X post", "https://x.com/jack/status/20"),
        ("Product page", "https://maticrobots.com/product"),
        ("Article", "https://en.wikipedia.org/wiki/Robotic_vacuum_cleaner"),
    ]
}

private struct RehearsalSheet: View {
    @State private var model: ChatModel
    let onClose: () -> Void

    init(content: SharedContent, usesSampleAnswers: Bool, onClose: @escaping () -> Void) {
        _model = State(initialValue: ChatModel(content: content, usesSampleAnswers: usesSampleAnswers))
        self.onClose = onClose
    }

    var body: some View {
        DiaSheetView(model: model, onClose: onClose)
    }
}

private struct IdentifiedContent: Identifiable {
    let id = UUID()
    let content: SharedContent
}

private struct AvailabilityRow: View {
    @State private var status = "Checking…"
    @State private var ok = false

    var body: some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? .green : .orange)
            Text(status)
                .font(.footnote)
        }
        .task {
            switch SystemLanguageModel.default.availability {
            case .available:
                ok = true
                status = "On-device model ready."
            case .unavailable(let reason):
                status = ChatModel.describe(reason)
            }
        }
    }
}
