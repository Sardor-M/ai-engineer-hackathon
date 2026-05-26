import Foundation

/// Provider-agnostic TTS dispatcher. Tries engines in order — first
/// `isAvailable` engine that returns `true` from `speak` wins. Mirrors the
/// pattern in `Brain` so coordinator code can speak without knowing whether
/// audio came from ElevenLabs or the system synth.
@MainActor
final class Voice {
    let engines: [TTSEngine]

    init(engines: [TTSEngine]) {
        self.engines = engines
    }

    /// Convenience: ElevenLabs primary, AVSpeechSynthesizer fallback.
    /// Reads `ELEVENLABS_API_KEY` from the environment.
    static func defaultStack() -> Voice {
        Voice(engines: [ElevenLabsTTS(), SystemTTS()])
    }

    /// True if any engine is currently producing audio.
    var isSpeaking: Bool {
        engines.contains(where: { $0.isSpeaking })
    }

    /// Stop every engine.
    func stop() {
        for engine in engines { engine.stop() }
    }

    /// Speak `text` in the picked voice. Returns the engine that played, or
    /// `nil` if every engine failed (in which case we logged but didn't crash).
    @discardableResult
    func speak(
        _ text: String,
        mode: VoiceMode,
        settings: Settings,
        onDone: (@MainActor () -> Void)? = nil
    ) async -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard settings.voiceEnabled else { return nil }

        let profile = VoicePicker.pick(
            mode: mode,
            defaultProfile: settings.voiceProfile,
            autoByContext: settings.autoVoiceByContext
        )

        for engine in engines where engine.isAvailable {
            let ok = await engine.speak(trimmed, profile: profile, onDone: onDone)
            if ok {
                return engine.name
            }
        }
        print("[voice] no engine could speak")
        return nil
    }
}
