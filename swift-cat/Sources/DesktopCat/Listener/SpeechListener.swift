import AVFoundation
import Foundation
import Speech

/// On-device speech-to-text via `SFSpeechRecognizer` + `AVAudioEngine`.
///
/// Why on-device first: `SFSpeechRecognizer.supportsOnDeviceRecognition` is
/// true for the user's locale on every modern Mac, transcription is free,
/// and there's no network round-trip — partials arrive in ~150 ms. We fall
/// through to `WhisperListener` when the locale's on-device pack isn't
/// installed (rare but possible).
///
/// Threading:
/// - `AVAudioEngine`'s input tap callback runs on a background audio thread.
///   We forward buffers to `SFSpeechAudioBufferRecognitionRequest` (thread-safe
///   per Apple docs) and bounce all coordinator-visible callbacks through
///   the main actor.
@MainActor
final class SpeechListener: NSObject, ListenerEngine {
    let name = "speech"

    private let locale: Locale
    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var callbacks: ListenerCallbacks?
    private var lastTranscript: String = ""
    private(set) var isListening: Bool = false

    init(locale: Locale = .current) {
        self.locale = locale
        self.recognizer = SFSpeechRecognizer(locale: locale)
        super.init()
    }

    nonisolated var isAvailable: Bool {
        get async {
            // Only signal availability when the locale supports on-device
            // recognition. If it doesn't, SFSpeechRecognizer would silently
            // fall back to Apple's cloud service — we prefer to let
            // WhisperListener handle the network path explicitly.
            await MainActor.run {
                guard let r = self.recognizer else { return false }
                return r.isAvailable && r.supportsOnDeviceRecognition
            }
        }
    }

    func start(callbacks: ListenerCallbacks) async throws {
        guard !isListening else { return }
        guard let recognizer, recognizer.isAvailable else {
            throw ListenerError.recognizerUnavailable
        }

        // First-use authorization. macOS shows the system prompt on the very
        // first call; subsequent calls return cached status synchronously.
        let speechStatus = await Self.requestSpeechAuthorization()
        guard speechStatus == .authorized else {
            // Use a distinct error so the dispatcher doesn't fall through to
            // WhisperListener — uploading mic audio after an explicit denial
            // would be a privacy violation.
            throw ListenerError.speechPermissionDenied
        }

        let micGranted = await Self.requestMicAccess()
        guard micGranted else {
            throw ListenerError.micDenied
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // Prefer on-device when the locale supports it. Falls back to
        // server-based recognition automatically when it doesn't.
        if recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }
        self.request = req
        self.callbacks = callbacks
        self.lastTranscript = ""

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        // 1024-frame buffers — same default the Apple sample uses. Smaller
        // makes partials chattier without improving accuracy.
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            // Background audio thread. SFSpeechAudioBufferRecognitionRequest
            // is documented as safe to append from any thread.
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.request = nil
            self.callbacks = nil
            throw ListenerError.audioEngineFailed(error.localizedDescription)
        }

        self.task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            // Recognizer callback may run on a non-main queue; bounce.
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    self.lastTranscript = text
                    self.callbacks?.onPartial(text)
                    if result.isFinal {
                        self.finish()
                    }
                }
                if let error {
                    self.callbacks?.onError("speech recognizer: \(error.localizedDescription)")
                    self.finish()
                }
            }
        }

        isListening = true
    }

    func stop() {
        guard isListening else { return }
        request?.endAudio()
        // recognitionTask continues until it emits a final result; we'll
        // finish in the callback above when isFinal arrives. If the task
        // never finalizes (e.g. broken pipe), `finish` will still be called
        // from the error branch.
    }

    // MARK: - Helpers

    private func finish() {
        guard isListening else { return }
        isListening = false

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        task?.cancel()
        task = nil
        request = nil

        let final = lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let cb = callbacks
        callbacks = nil
        cb?.onFinal(final)
    }

    // MARK: - Authorization

    private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private static func requestMicAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }
}
