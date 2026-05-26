import Foundation

/// OpenAI chat-completions provider. Mirrors `_openaiChat` in `brain.js`:
///   - text and vision both go through the same endpoint
///   - vision sends an inline base64 PNG via `image_url.url = "data:image/png;base64,…"`
///   - JSON mode sets `response_format = { type: "json_object" }`
///   - 429 / quota errors mark the provider blocked for 60 min
struct OpenAIChat: ChatProvider {
    let name = "openai"

    /// Defaults match `brain.js:4-5`. Overridable via env so a beta tester can
    /// point at a different model without rebuilding.
    private let textModel: String
    private let visionModel: String
    private let apiKey: String?
    private let session: URLSession

    init(
        apiKey: String? = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
        textModel: String = ProcessInfo.processInfo.environment["OPENAI_TEXT_MODEL"] ?? "gpt-4o-mini",
        visionModel: String = ProcessInfo.processInfo.environment["OPENAI_VISION_MODEL"] ?? "gpt-4o-mini",
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey?.isEmpty == false ? apiKey : nil
        self.textModel = textModel
        self.visionModel = visionModel
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

        let body = makeBody(req)
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            print("[brain] openai network error:", error.localizedDescription)
            return ""
        }

        guard let http = response as? HTTPURLResponse else { return "" }

        if http.statusCode != 200 {
            let errText = String(data: data, encoding: .utf8) ?? ""
            if http.statusCode == 429 || matchesRateLimit(errText) {
                await RateLimiter.shared.markBlocked(name, reason: errText)
            } else {
                print("[brain] openai \(http.statusCode):", errText.prefix(160))
            }
            return ""
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            return ""
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Request body

    private func makeBody(_ req: ChatRequest) -> [String: Any] {
        var messages: [[String: Any]] = []

        if let system = req.system, !system.isEmpty {
            messages.append(["role": "system", "content": system])
        }

        if let png = req.imageData {
            let b64 = png.base64EncodedString()
            messages.append([
                "role": "user",
                "content": [
                    ["type": "text", "text": req.user],
                    [
                        "type": "image_url",
                        "image_url": ["url": "data:image/png;base64,\(b64)"]
                    ]
                ] as [Any]
            ])
        } else {
            messages.append(["role": "user", "content": req.user])
        }

        var body: [String: Any] = [
            "model": req.imageData != nil ? visionModel : textModel,
            "messages": messages,
            "max_tokens": req.maxTokens,
            "temperature": req.temperature,
        ]
        if req.jsonMode {
            body["response_format"] = ["type": "json_object"]
        }
        return body
    }

    private func matchesRateLimit(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("quota") || lowered.contains("rate limit") || lowered.contains("rate-limit") || lowered.contains("ratelimit")
    }
}
