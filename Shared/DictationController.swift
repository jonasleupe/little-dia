import Foundation
import Observation
import AVFoundation
import Speech

/// Tap-to-dictate into the composer. Uses the same audio path `AudioProbe`
/// proved out (mic permission → AVAudioSession → AVAudioEngine tap →
/// SFSpeechRecognizer), with on-device recognition whenever the locale supports
/// it. Every failure lands in `errorText` as one readable line.
@MainActor
@Observable
final class DictationController {

    private(set) var isListening = false
    private(set) var transcript = ""
    var errorText: String?

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private let sink = RecognitionSink()

    func toggle() async {
        if isListening { stop() } else { await start() }
    }

    func start() async {
        guard !isListening else { return }
        errorText = nil
        transcript = ""

        let micGranted = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
        guard micGranted else {
            errorText = "Microphone access is off for Little Dia. You can enable it in Settings."
            return
        }

        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { _ in }
            for _ in 0..<40 where SFSpeechRecognizer.authorizationStatus() == .notDetermined {
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            errorText = "Speech recognition isn't allowed for Little Dia."
            return
        }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorText = "Couldn't open the microphone from the share sheet on this device."
            return
        }

        let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else {
            errorText = "Speech recognition isn't available right now."
            return
        }
        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        sink.attach(request)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            errorText = "No usable microphone in this window."
            sink.detach()
            return
        }

        let sink = self.sink
        let tapBlock: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { buffer, _ in
            sink.receive(buffer)
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: tapBlock)

        do {
            engine.prepare()
            try engine.start()
        } catch {
            errorText = "Couldn't start listening (\((error as NSError).localizedDescription))."
            input.removeTap(onBus: 0)
            sink.detach()
            return
        }

        isListening = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failure = error.map { ($0 as NSError).localizedDescription }
            Task { @MainActor in
                guard let self else { return }
                if let text { self.transcript = text }
                if isFinal { self.stop() }
                if let failure, self.isListening {
                    // "No speech detected" style errors arrive after a silent stop; only surface real ones.
                    if self.transcript.isEmpty { self.errorText = "Didn't catch that. \(failure)" }
                    self.stop()
                }
            }
        }
    }

    func stop() {
        guard isListening || engine.isRunning else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        sink.detach()
        task?.finish()
        task = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Bridges the realtime audio-tap thread to the actor. File scope so its methods
/// carry no actor isolation; `append` on the request is safe off-main.
private final class RecognitionSink: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func attach(_ request: SFSpeechAudioBufferRecognitionRequest) {
        lock.lock(); self.request = request; lock.unlock()
    }
    func detach() {
        lock.lock(); request?.endAudio(); request = nil; lock.unlock()
    }
    func receive(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); let request = self.request; lock.unlock()
        request?.append(buffer)
    }
}
