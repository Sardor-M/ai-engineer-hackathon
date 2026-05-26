import AVFoundation
import Foundation

/// `AVSpeechSynthesizer` fallback. Replaces the browser `speechSynthesis` path
/// `renderer.js` used when ElevenLabs was unavailable. The character is much
/// less alive than ElevenLabs (no breathiness, no nuance), but the cat keeps
/// talking — which matters more than tone during a demo when the network or
/// API key fails mid-line.
///
/// Profile mapping is approximate: we pick AVSpeechSynthesisVoice variants
/// that lean toward the same feel as the matching ElevenLabs voice (deeper
/// for `low`, slower for `whisper`, etc.).
@MainActor
final class SystemTTS: NSObject, TTSEngine {
    let name = "system"

    private let synth = AVSpeechSynthesizer()
    private var onDoneCallback: (@MainActor () -> Void)?

    override init() {
        super.init()
        synth.delegate = self
    }

    nonisolated var isAvailable: Bool {
        true   // AVSpeechSynthesizer is always available on macOS 13+
    }

    var isSpeaking: Bool {
        synth.isSpeaking
    }

    func speak(
        _ text: String,
        profile: VoiceProfile,
        onDone: (@MainActor () -> Void)?
    ) async -> Bool {
        guard !text.isEmpty else {
            onDone?()
            return false
        }

        // Preempt anything already speaking.
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice(for: profile)
        let (rate, pitch, volume) = tuning(for: profile)
        utterance.rate = rate
        utterance.pitchMultiplier = pitch
        utterance.volume = volume

        self.onDoneCallback = onDone
        synth.speak(utterance)
        return true
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        if let cb = onDoneCallback {
            onDoneCallback = nil
            cb()
        }
    }

    // MARK: - Profile → voice mapping

    private func voice(for profile: VoiceProfile) -> AVSpeechSynthesisVoice? {
        // Prefer en-US Samantha for warm profiles, en-GB Daniel for low.
        // Falls back to default if a preferred voice isn't installed.
        let preferredID: String?
        switch profile {
        case .soft:    preferredID = "com.apple.voice.compact.en-US.Samantha"
        case .curious: preferredID = "com.apple.voice.compact.en-US.Samantha"
        case .bright:  preferredID = "com.apple.voice.compact.en-US.Samantha"
        case .low:     preferredID = "com.apple.voice.compact.en-GB.Daniel"
        case .whisper: preferredID = "com.apple.voice.compact.en-US.Samantha"
        }
        if let id = preferredID, let v = AVSpeechSynthesisVoice(identifier: id) {
            return v
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    /// (rate, pitch, volume) tuned by ear to land roughly where the matching
    /// ElevenLabs profile sits. `AVSpeechUtterance.defaultSpeechRate` is 0.5.
    private func tuning(for profile: VoiceProfile) -> (Float, Float, Float) {
        switch profile {
        case .soft:    return (0.46, 1.0,  0.85)
        case .curious: return (0.50, 1.1,  0.85)
        case .bright:  return (0.52, 1.15, 0.9)
        case .low:     return (0.44, 0.85, 0.85)
        case .whisper: return (0.42, 0.95, 0.6)
        }
    }
}

extension SystemTTS: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if let cb = onDoneCallback {
                onDoneCallback = nil
                cb()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if let cb = onDoneCallback {
                onDoneCallback = nil
                cb()
            }
        }
    }
}
