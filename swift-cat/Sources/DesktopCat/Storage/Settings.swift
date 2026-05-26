import Foundation

/// Five voice characters borrowed from the Electron version. Each one drives
/// both audio (ElevenLabs voiceId — wired in Phase 3) and visuals (color +
/// breath animation — wired in Phase 4).
enum VoiceProfile: String, Codable, CaseIterable, Sendable {
    case soft, curious, bright, low, whisper
}

/// User-tunable settings, persisted to `Application Support/DesktopCat/settings.json`.
/// Defaults match the Electron app so users carry over expectations.
struct Settings: Codable, Equatable, Sendable {
    var voiceEnabled: Bool
    var voiceProfile: VoiceProfile
    var autoVoiceByContext: Bool
    var mouseQuestionsEnabled: Bool

    static let defaults = Settings(
        voiceEnabled: true,
        voiceProfile: .soft,
        autoVoiceByContext: true,
        mouseQuestionsEnabled: true
    )
}

@MainActor
final class SettingsStore {
    private(set) var current: Settings = .defaults
    private let url: URL

    init(url: URL = AppSupport.file("settings.json")) {
        self.url = url
        load()
    }

    func load() {
        guard
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(Settings.self, from: data)
        else { return }
        current = decoded
    }

    /// Mutate in place; only writes to disk if something actually changed.
    @discardableResult
    func update(_ change: (inout Settings) -> Void) -> Settings {
        var next = current
        change(&next)
        if next != current {
            current = next
            persist(next)
        }
        return next
    }

    private func persist(_ s: Settings) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try enc.encode(s).write(to: url, options: .atomic)
        } catch {
            print("[cat] settings save failed:", error.localizedDescription)
        }
    }
}
