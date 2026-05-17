import Foundation

/// A single request to a chat provider. The provider is responsible for
/// translating this into its own wire format (OpenAI chat-completions vs
/// Gemini generateContent etc.) and returning a single string of text.
struct ChatRequest: Sendable {
    var system: String?
    var user: String
    var imageData: Data?        // PNG bytes; provider encodes to base64 itself
    var jsonMode: Bool
    var maxTokens: Int
    var temperature: Double

    init(
        system: String? = nil,
        user: String,
        imageData: Data? = nil,
        jsonMode: Bool = false,
        maxTokens: Int = 400,
        temperature: Double = 0.85
    ) {
        self.system = system
        self.user = user
        self.imageData = imageData
        self.jsonMode = jsonMode
        self.maxTokens = maxTokens
        self.temperature = temperature
    }
}

/// Provider-agnostic chat. Implementations:
///   - never throw
///   - return "" on any failure (missing key, network error, malformed
///     response, rate-limit)
///   - mark themselves rate-limited via the shared `RateLimiter` on 429
///
/// The "" convention mirrors `brain.js` exactly so the dispatcher and
/// every call site can chain `if text.isEmpty { fallback }` cleanly.
protocol ChatProvider: Sendable {
    var name: String { get }

    /// True iff we have an API key AND we're not currently rate-limited.
    /// Reading this is cheap; the dispatcher checks it before calling chat().
    var isAvailable: Bool { get async }

    func chat(_ req: ChatRequest) async -> String
}
