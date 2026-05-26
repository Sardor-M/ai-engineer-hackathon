import Foundation

/// All sprite states the cat can be in. Phase 1 only renders .puddle and
/// .awake; the rest are scaffolding referenced by later phases so the rest
/// of the code can be written against the full set from day one.
enum CatSpriteState: String, CaseIterable {
    case puddle
    case awake
    case sleep
    case walk1
    case walk2
    case annoyed
    case play
}
