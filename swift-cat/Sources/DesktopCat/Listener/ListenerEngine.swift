import Foundation

/// Callbacks a `ListenerEngine` invokes while it's running. The engine owns
/// the audio session; callers don't see raw buffers. Every callback fires on
/// the main actor so the coordinator can mutate UI / Voice state without an
/// extra hop.
struct ListenerCallbacks: Sendable {
    /// Streaming partial transcript. May fire many times before `onFinal`.
    /// Empty strings are valid — engines emit `""` when the recognizer has
    /// nothing yet. Coordinator should debounce display updates.
    let onPartial: @MainActor @Sendable (String) -> Void

    /// Final transcript for this listening session. Fires exactly once,
    /// after the engine stops. Empty string means "we heard nothing usable".
    let onFinal: @MainActor @Sendable (String) -> Void

    /// Non-fatal warning while listening. The engine keeps running unless it
    /// also returns from `start` with a thrown error.
    let onError: @MainActor @Sendable (String) -> Void
}

/// A pluggable speech-to-text engine. `SpeechListener` (SFSpeechRecognizer +
/// AVAudioEngine) is primary because it runs on-device and free; `WhisperListener`
/// is the network fallback for locales without on-device support.
///
/// Lifecycle:
///   1. Caller checks `isAvailable`.
///   2. Caller calls `start(callbacks:)` — engine begins capturing audio.
///   3. Engine streams `onPartial` updates.
///   4. Caller calls `stop()` (or engine times out) — engine fires `onFinal`
///      once with the consolidated transcript.
///
/// Engines never crash. Failures become an `onError` callback + an empty
/// `onFinal` so the cat goes silent rather than surfacing a stack trace.
protocol ListenerEngine: AnyObject, Sendable {
    var name: String { get }

    /// True iff the engine has what it needs to run right now (mic permission,
    /// recognizer locale installed, API key set). Cheap to read; never blocks.
    var isAvailable: Bool { get async }

    /// True while audio is being captured. Read on the main actor.
    @MainActor var isListening: Bool { get }

    /// Begin capture. Throws if the audio session cannot be configured (e.g.,
    /// mic denied at the OS level after a stale `isAvailable` check).
    @MainActor
    func start(callbacks: ListenerCallbacks) async throws

    /// Stop capture. Idempotent. Engine fires `onFinal` exactly once.
    @MainActor
    func stop()
}

/// Errors that bubble up from `start`. Coordinator logs the message and tries
/// the next engine; nothing else cares about the exact case.
enum ListenerError: Error, CustomStringConvertible, Sendable {
    case micDenied
    case recognizerUnavailable
    case audioEngineFailed(String)
    case apiKeyMissing
    case network(String)

    var description: String {
        switch self {
        case .micDenied: return "microphone permission denied"
        case .recognizerUnavailable: return "speech recognizer unavailable for this locale"
        case .audioEngineFailed(let s): return "audio engine failed: \(s)"
        case .apiKeyMissing: return "WHISPER_API_KEY / OPENAI_API_KEY not set"
        case .network(let s): return "network: \(s)"
        }
    }
}
