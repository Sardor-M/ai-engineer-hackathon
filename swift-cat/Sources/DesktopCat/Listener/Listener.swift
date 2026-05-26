import Foundation

/// Provider-agnostic listener dispatcher. Tries engines in order — the first
/// one whose `start` returns without throwing wins, and its transcript is the
/// one we ship through callbacks. Mirrors the `Voice` / `Brain` pattern so
/// coordinator code stays the same shape across all three subsystems.
@MainActor
final class Listener {
    let engines: [ListenerEngine]

    private var activeEngine: ListenerEngine?

    init(engines: [ListenerEngine]) {
        self.engines = engines
    }

    /// Convenience: on-device `SpeechListener` primary, `WhisperListener`
    /// fallback. Reads `WHISPER_API_KEY` / `OPENAI_API_KEY` from env.
    static func defaultStack() -> Listener {
        Listener(engines: [SpeechListener(), WhisperListener()])
    }

    /// True while any engine is capturing audio.
    var isListening: Bool {
        activeEngine?.isListening ?? false
    }

    /// Begin a listening session. Returns the name of the engine that started,
    /// or `nil` if every engine refused. The caller doesn't need to know which
    /// engine fired — partials and final routed through `callbacks` identically.
    @discardableResult
    func start(callbacks: ListenerCallbacks) async -> String? {
        if isListening {
            print("[listener] already listening — ignoring duplicate start")
            return activeEngine?.name
        }
        activeEngine = nil

        for engine in engines {
            let available = await engine.isAvailable
            guard available else { continue }
            do {
                try await engine.start(callbacks: callbacks)
                activeEngine = engine
                print("[listener] \(engine.name) → listening")
                return engine.name
            } catch let e as ListenerError {
                print("[listener] \(engine.name) refused: \(e)")
                continue
            } catch {
                print("[listener] \(engine.name) error: \(error.localizedDescription)")
                continue
            }
        }

        print("[listener] no engine could start")
        // The coordinator may still want to know the final result fired (with
        // empty text) so its UI clears state.
        callbacks.onFinal("")
        return nil
    }

    /// Stop the current session. No-op if nothing's running. Final callback
    /// fires inside the engine — coordinator gets the transcript from there.
    func stop() {
        activeEngine?.stop()
        activeEngine = nil
    }

    /// Toggle helper for hotkey wiring. Returns whether listening is now on.
    @discardableResult
    func toggle(callbacks: ListenerCallbacks) async -> Bool {
        if isListening {
            stop()
            return false
        }
        let name = await start(callbacks: callbacks)
        return name != nil
    }
}
