import SwiftUI

/// UI for `AudioProbe`. Run it on a physical device; the simulator borrows the
/// Mac's mic and won't tell you the truth about extension sandboxing.
struct ProbeView: View {
    @State private var probe = AudioProbe()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Can this window open the microphone?")
                    .font(.headline)
                Text("""
                Every step below has to pass for a live voice conversation to work \
                inside the share sheet. The one that matters is “Activate AVAudioSession” \
                — Apple's docs historically said extensions can't. Test on a real device.
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)

                levelMeter

                VStack(spacing: 0) {
                    ForEach(probe.steps) { step in
                        StepRow(step: step)
                        if step.id != probe.steps.last?.id { Divider() }
                    }
                }
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))

                if !probe.transcript.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Heard").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(probe.transcript).font(.body)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
                }

                if let summary = probe.summary {
                    Text(summary)
                        .font(.footnote)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 12))
                }

                Button {
                    if probe.isRunning {
                        probe.stop()
                    } else {
                        Task { await probe.start() }
                    }
                } label: {
                    Label(probe.isRunning ? "Stop" : "Start audio probe",
                          systemImage: probe.isRunning ? "stop.fill" : "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .onDisappear { probe.stop() }
    }

    private var levelMeter: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill))
                Capsule()
                    .fill(.tint)
                    .frame(width: max(4, geo.size.width * probe.level))
                    .animation(.linear(duration: 0.08), value: probe.level)
            }
        }
        .frame(height: 10)
    }
}

private struct StepRow: View {
    let step: AudioProbe.Step

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(step.name).font(.subheadline)
                if let detail = step.detail {
                    Text(detail)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    @ViewBuilder private var icon: some View {
        switch step.state {
        case .pending: Image(systemName: "circle").foregroundStyle(.tertiary)
        case .running: ProgressView().controlSize(.small)
        case .ok:      Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:  Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}
