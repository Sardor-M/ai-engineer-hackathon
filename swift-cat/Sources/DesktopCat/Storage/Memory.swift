import Foundation

/// Single observation in the cat's memory. Mirrors the JSON shape used by the
/// Electron version so we can read/write the same file during coexistence.
struct Observation: Codable, Sendable {
    let at: Date
    var description: String?
    var tag: String?
    var said: String?
}

struct Memory: Codable, Sendable {
    var sessionCount: Int
    var observations: [Observation]

    static let empty = Memory(sessionCount: 0, observations: [])

    /// Last `n` non-empty `said` lines. Used by Phase 3 to feed the model
    /// `recent_lines_already_said` so the cat doesn't repeat herself.
    func recentSaid(_ n: Int = 10) -> [String] {
        observations
            .suffix(15)
            .compactMap { $0.said }
            .filter { !$0.isEmpty }
            .suffix(n)
            .map { $0 }
    }
}

@MainActor
final class MemoryStore {
    private(set) var current: Memory = .empty
    private let url: URL
    private let maxObservations = 100

    init(url: URL = AppSupport.file("memory.json")) {
        self.url = url
        load()
    }

    func load() {
        guard
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(Memory.self, from: data)
        else { return }
        current = decoded
    }

    func append(_ obs: Observation) {
        current.observations.append(obs)
        if current.observations.count > maxObservations {
            current.observations.removeFirst(current.observations.count - maxObservations)
        }
        current.sessionCount += 1
        persist()
    }

    private func persist() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try enc.encode(current).write(to: url, options: .atomic)
        } catch {
            print("[cat] memory save failed:", error.localizedDescription)
        }
    }
}
