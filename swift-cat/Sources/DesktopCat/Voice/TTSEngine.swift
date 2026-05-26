import Foundation

/// A pluggable speech-synthesis engine. ElevenLabs is primary (cloud,
/// in-character); SystemTTS is the AVSpeechSynthesizer fallback we reach for
/// when the network or API key isn't available.
///
/// Engines never throw — `speak` returns `false` on failure so the `Voice`
/// dispatcher can try the next engine without unwrapping a Result chain.
protocol TTSEngine: AnyObject, Sendable {
    var name: String { get }

    /// True iff the engine has what it needs to run right now (API key set,
    /// audio session OK). Cheap to read.
    var isAvailable: Bool { get }

    /// True while audio is actively playing. The coordinator uses this to
    /// avoid stomping a speech-in-progress with a new utterance.
    @MainActor var isSpeaking: Bool { get }

    /// Speak `text` in the given profile. Returns `true` if playback started
    /// successfully. `onDone` is invoked on the main actor when playback ends
    /// (used by Phase 4's talking-animation to stop).
    @MainActor
    func speak(
        _ text: String,
        profile: VoiceProfile,
        onDone: (@MainActor () -> Void)?
    ) async -> Bool

    /// Halt any in-progress speech. Idempotent.
    @MainActor
    func stop()
}
