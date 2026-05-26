import Foundation

/// Google Gemini provider. Mirrors `_geminiChat` in `brain.js`:
///   - generateContent REST endpoint (no SDK dependency — same wire format)
///   - system prompt goes into top-level `systemInstruction`, not as a message
///   - vision via `parts[].inlineData = { mimeType, data }`
///   - JSON mode via `generationConfig.responseMimeType = "application/json"`
///   - 429 / RESOURCE_EXHAUSTED marks the provider blocked for 60 min
struct GeminiChat: ChatProvider {
    let name = "gemini"

    private let model: String
    private let apiKey: String?
    private let session: URLSession

    init(
        apiKey: String? = ProcessInfo.processInfo.environment["GEMINI_API_KEY"],
        model: String = ProcessInfo.processInfo.environment["GEMINI_MODEL"] ?? "gemini-2.5-flash",
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey?.isEmpty == false ? apiKey : nil
        self.model = model
        self.session = session
    }

    var isAvailable: Bool {
        get async {
            guard apiKey != nil else { return false }
            return await !RateLimiter.shared.isBlocked(name)
        }
    }

    func chat(_ req: ChatRequest) async -> String {
        guard let apiKey else { return "" }
        if await RateLimiter.shared.isBlocked(name) { return "" }

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: makeBody(req))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            print("[brain] gemini network error:", error.localizedDescription)
            return ""
        }

        guard let http = response as? HTTPURLResponse else { return "" }

        if http.statusCode != 200 {
            let errText = String(data: data, encoding: .utf8) ?? ""
            if http.statusCode == 429 || matchesRateLimit(errText) {
                await RateLimiter.shared.markBlocked(name, reason: errText)
            } else {
                print("[brain] gemini \(http.statusCode):", errText.prefix(160))
            }
            return ""
        }

        return extractText(data) ?? ""
    }

    // MARK: - Request body

    private func makeBody(_ req: ChatRequest) -> [String: Any] {
        var parts: [[String: Any]] = [["text": req.user]]
        if let png = req.imageData {
            parts.append([
                "inlineData": [
                    "mimeType": "image/png",
                    "data": png.base64EncodedString()
                ]
            ])
        }

        var generationConfig: [String: Any] = [
            "maxOutputTokens": req.maxTokens,
            "temperature": req.temperature,
        ]
        if req.jsonMode {
            generationConfig["responseMimeType"] = "application/json"
        }

        var body: [String: Any] = [
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": generationConfig,
        ]
        if let system = req.system, !system.isEmpty {
            body["systemInstruction"] = ["parts": [["text": system]]]
        }
        return body
    }

    /// Walks the generateContent response shape:
    /// `{ candidates: [ { content: { parts: [ { text: "…" } ] } } ] }`
    private func extractText(_ data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = json["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]]
        else {
            return nil
        }
        let joined = parts.compactMap { $0["text"] as? String }.joined()
        let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func matchesRateLimit(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("quota")
            || lowered.contains("rate limit")
            || lowered.contains("rate-limit")
            || lowered.contains("resource_exhausted")
    }
}
