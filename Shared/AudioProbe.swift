import Foundation
import Observation
import AVFoundation
import Speech

/// Answers one question: **can a Share extension open a live microphone stream?**
///
/// Each step reports success or the exact failure, so running this once on a
/// physical device tells you whether the voice-conversation idea is viable in the
/// sheet or has to hand off to the host app.
///
/// (Production would use iOS 26's `SpeechAnalyzer` / `SpeechTranscriber`; this
/// uses `SFSpeechRecognizer` because the probe only needs to prove the audio path,
/// and that API is stable.)
@MainActor
@Observable
final class AudioProbe {

    enum StepState { case pending, running, ok, failed }

    struct Step: Identifiable {
        let id = UUID()
        let name: String
        var state: StepState = .pending
        var detail: String?
    }

    private enum S: Int { case mic, session, engine, buffers, speechAuth, transcription }

    private(set) var steps: [Step] = [
        Step(name: "Microphone permission"),
        Step(name: "Activate AVAudioSession (.playAndRecord)"),
        Step(name: "Start AVAudioEngine + input tap"),
        Step(name: "Receiving audio buffers"),
        Step(name: "Speech-recognition permission"),
        Step(name: "Live on-device transcription"),
    ]

    private(set) var isRunning = false
    private(set) var level: Double = 0        // 0…1, smoothed
    private(set) var transcript: String = ""
    private(set) var summary: String?

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var task: SFSpeechRecognitionTask?
    private let sink = BufferSink()

    // MARK: - Control

    func start() async {
        guard !isRunning else { return }
        reset()
        isRunning = true

        // The critical unknowns first: mic permission, then opening an audio
        // session and engine inside this process. `start()` returns as soon as
        // that path is proven (or fails).
        guard await stepMicPermission() else { return finish(false) }
        guard stepActivateSession() else { return finish(false) }
        guard stepStartEngine() else { return finish(false) }

        // Speech auth / transcription resolve in the background and never abort
        // the audio result.
        Task { [weak self] in
            await self?.stepSpeechPermission()
            self?.startTranscription()
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        sink.detach()
        task?.cancel()
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRunning = false
        level = 0
    }

    // MARK: - Steps

    private func stepMicPermission() async -> Bool {
        set(.mic, .running)
        let granted = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
        set(.mic, granted ? .ok : .failed, granted ? nil : "Denied — or this process has no mic entitlement.")
        return granted
    }

    private func stepActivateSession() -> Bool {
        set(.session, .running)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            set(.session, .ok, "category=\(session.category.rawValue), \(Int(session.sampleRate))Hz, inputs=\(session.availableInputs?.count ?? 0)")
            return true
        } catch {
            let ns = error as NSError
            set(.session, .failed, "\(ns.domain) \(ns.code): \(ns.localizedDescription)")
            return false
        }
    }

    private func stepStartEngine() -> Bool {
        set(.engine, .running)
        set(.buffers, .running)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            set(.engine, .failed, "Input node has an invalid format (\(format)). No usable mic in this process.")
            return false
        }

        sink.onLevel = { [weak self] rms in
            Task { @MainActor in self?.ingest(level: rms) }
        }
        // The tap block runs on the realtime audio thread. It MUST be @Sendable so
        // Swift doesn't bind it to this @MainActor context — an isolation check
        // firing on the audio thread is a hard crash.
        let sink = self.sink
        let tapBlock: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { buffer, _ in
            sink.receive(buffer)
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: tapBlock)

        do {
            engine.prepare()
            try engine.start()
            set(.engine, .ok, "\(Int(format.sampleRate))Hz ×\(format.channelCount)")
            return true
        } catch {
            set(.engine, .failed, "engine.start(): \((error as NSError).localizedDescription)")
            input.removeTap(onBus: 0)
            return false
        }
    }

    private func stepSpeechPermission() async {
        set(.speechAuth, .running)
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { _ in }
            // Poll rather than await the callback — it can stall for a long time
            // on Simulator.
            for _ in 0..<40 where SFSpeechRecognizer.authorizationStatus() == .notDetermined {
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        let status = SFSpeechRecognizer.authorizationStatus()
        set(.speechAuth, status == .authorized ? .ok : .failed,
            status == .authorized ? nil : "Status: \(status).")
    }

    private func startTranscription() {
        set(.transcription, .running)
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            set(.transcription, .failed, "Skipped — speech recognition not authorized.")
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            set(.transcription, .failed, "SFSpeechRecognizer unavailable for en-US.")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        sink.attach(request)

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    self.set(.transcription, .ok)
                }
                if let error {
                    self.set(.transcription, .failed, (error as NSError).localizedDescription)
                }
            }
        }
    }

    private func ingest(level rms: Double) {
        self.level = self.level * 0.8 + min(1, rms * 6) * 0.2
        if steps[S.buffers.rawValue].state == .running {
            set(.buffers, .ok, "first buffers received")
        }
    }

    // MARK: - Bookkeeping

    private func set(_ step: S, _ state: StepState, _ detail: String? = nil) {
        steps[step.rawValue].state = state
        if let detail { steps[step.rawValue].detail = detail }
    }

    private func reset() {
        for i in steps.indices { steps[i].state = .pending; steps[i].detail = nil }
        transcript = ""
        summary = nil
        level = 0
    }

    private func finish(_ ok: Bool) {
        isRunning = ok ? isRunning : false
        if !ok {
            let firstFailure = steps.first { $0.state == .failed }
            summary = "Blocked at “\(firstFailure?.name ?? "?")”. A share extension can't open the mic here — hand off to the host app for voice."
        }
    }

    nonisolated fileprivate static func rms(of buffer: AVAudioPCMBuffer) -> Double {
        guard let data = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        let channel = data[0]
        for i in 0..<frames { sum += channel[i] * channel[i] }
        return Double((sum / Float(frames)).squareRoot())
    }
}

/// Bridges the realtime audio-tap thread to the actor. Lives at file scope (not
/// nested in the `@MainActor` type) so its methods carry no actor isolation.
/// `append` on `SFSpeechAudioBufferRecognitionRequest` is safe off-main; the
/// level callback only ever forwards a plain `Double`.
private final class BufferSink: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    var onLevel: (@Sendable (Double) -> Void)?

    func attach(_ request: SFSpeechAudioBufferRecognitionRequest) {
        lock.lock(); self.request = request; lock.unlock()
    }
    func detach() {
        lock.lock(); request?.endAudio(); request = nil; lock.unlock()
    }
    func receive(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); let request = self.request; lock.unlock()
        request?.append(buffer)
        onLevel?(AudioProbe.rms(of: buffer))
    }
}
