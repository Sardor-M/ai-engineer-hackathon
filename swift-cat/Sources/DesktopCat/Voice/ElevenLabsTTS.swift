import AVFoundation
import Foundation

/// ElevenLabs text-to-speech via REST. Mirrors `cat:speak` in `main.js`:
///   - POST text-to-speech/{voiceId}
///   - model_id `eleven_flash_v2_5`, stability 0.55, similarity_boost 0.75
///   - returns audio/mpeg which we play through `AVAudioPlayer`
///
/// Single-player design: a new utterance preempts whatever's playing. That
/// matches the Electron behavior (`stopAudio()` before the next `new Audio()`).
@MainActor
final class ElevenLabsTTS: NSObject, TTSEngine {
    let name = "elevenlabs"

    private let apiKey: String?
    private let session: URLSession
    private let modelId = "eleven_flash_v2_5"
    private let stability: Double = 0.55
    private let similarityBoost: Double = 0.75

    private var player: AVAudioPlayer?
    private var onDoneCallback: (@MainActor () -> Void)?

    init(
        apiKey: String? = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"],
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey?.isEmpty == false ? apiKey : nil
        self.session = session
    }

    nonisolated var isAvailable: Bool {
        apiKey != nil
    }

    var isSpeaking: Bool {
        player?.isPlaying ?? false
    }

    func speak(
        _ text: String,
        profile: VoiceProfile,
        onDone: (@MainActor () -> Void)?
    ) async -> Bool {
        guard let apiKey, !text.isEmpty else {
            await fireOnDone(onDone)
            return false
        }

        let voiceId = VoiceLibrary.voiceId(for: profile)
        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "text": text,
            "model_id": modelId,
            "voice_settings": [
                "stability": stability,
                "similarity_boost": similarityBoost,
            ],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            print("[voice] elevenlabs network error:", error.localizedDescription)
            await fireOnDone(onDone)
            return false
        }

        guard
            let http = response as? HTTPURLResponse,
            http.statusCode == 200,
            !data.isEmpty
        else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let detail = String(data: data, encoding: .utf8)?.prefix(160) ?? ""
            print("[voice] elevenlabs \(status):", detail)
            await fireOnDone(onDone)
            return false
        }

        return play(audioData: data, onDone: onDone)
    }

    func stop() {
        player?.stop()
        player = nil
        if let cb = onDoneCallback {
            onDoneCallback = nil
            cb()
        }
    }

    // MARK: - Playback

    private func play(audioData: Data, onDone: (@MainActor () -> Void)?) -> Bool {
        // Preempt any in-flight playback first.
        player?.stop()

        do {
            let p = try AVAudioPlayer(data: audioData)
            p.delegate = self
            p.volume = 0.75
            p.prepareToPlay()
            guard p.play() else {
                print("[voice] AVAudioPlayer.play() returned false")
                onDone?()
                return false
            }
            self.player = p
            self.onDoneCallback = onDone
            return true
        } catch {
            print("[voice] AVAudioPlayer init failed:", error.localizedDescription)
            onDone?()
            return false
        }
    }

    private func fireOnDone(_ cb: (@MainActor () -> Void)?) async {
        guard let cb else { return }
        await MainActor.run { cb() }
    }
}

extension ElevenLabsTTS: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if self.player === player {
                self.player = nil
            }
            if let cb = onDoneCallback {
                onDoneCallback = nil
                cb()
            }
        }
    }
}
