import Foundation

/// Coarse classification of what the user is doing right now. Phase 2 uses
/// this to switch the cat sprite; Phase 3 uses it to pick a prompt + voice.
enum CatMode: String, Sendable {
    case idle
    case pdf
    case email
}
