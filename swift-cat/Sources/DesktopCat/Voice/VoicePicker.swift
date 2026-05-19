import Foundation

/// Which "mode" the cat is in when she speaks — picks the matching voice
/// character. Mirrors VOICE_BY_MODE in brain.js.
enum VoiceMode: String, Sendable {
    case auto       // idle observation / proactive — use the user's default
    case pdf        // reading mode  → "low"   (deeper, studious)
    case email      // letter mode   → "soft"
    case curious    // mouse question → "curious"
    case play       // play state    → "bright"
}

/// The five ElevenLabs voice IDs, lifted byte-for-byte from VOICE_LIBRARY in
/// brain.js so the cat sounds identical to the Electron version.
enum VoiceLibrary {
    static let ids: [VoiceProfile: String] = [
        .soft:    "21m00Tcm4TlvDq8ikWAM",
        .curious: "AZnzlk1XvdvUeBnXmlld",
        .bright:  "MF3mGyEYCl7XYWbV9V6O",
        .low:     "EXAVITQu4vr4xnSDxMaL",
        .whisper: "XB0fDUnXU5powFXDhCwa",
    ]

    static func voiceId(for profile: VoiceProfile) -> String {
        ids[profile] ?? ids[.soft]!
    }
}

/// Picks the right voice profile for the moment. Pure function — port of
/// pickVoiceProfile() from brain.js. Rules in priority order:
///
///   1. If auto-by-context is off, always use the user's chosen default.
///   2. Night hours (22:00–05:59) always pick `whisper`, regardless of mode.
///   3. Otherwise map mode → profile via VOICE_BY_MODE; if no match, default.
enum VoicePicker {
    private static let byMode: [VoiceMode: VoiceProfile] = [
        .pdf:     .low,
        .email:   .soft,
        .curious: .curious,
        .play:    .bright,
        .auto:    .soft,
    ]

    static func pick(
        mode: VoiceMode,
        defaultProfile: VoiceProfile,
        autoByContext: Bool,
        hour: Int = Calendar.current.component(.hour, from: Date())
    ) -> VoiceProfile {
        if !autoByContext { return defaultProfile }
        if hour >= 22 || hour < 6 { return .whisper }
        return byMode[mode] ?? defaultProfile
    }
}
