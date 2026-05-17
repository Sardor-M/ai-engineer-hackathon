import Foundation

/// Parsed output of `Brain.analyzeEmail`. Empty strings mean "model didn't
/// give us that field" — never crash on partial JSON.
struct EmailResult: Sendable, Equatable {
    var summary: String
    var draftReply: String
    var clarifyingQuestion: String

    static let empty = EmailResult(summary: "", draftReply: "", clarifyingQuestion: "")
}

/// Parsed output of `Brain.getCatResponse` (the autonomous observation loop).
struct CatResponse: Sendable, Equatable {
    var response: String
    var tag: String

    static let empty = CatResponse(response: "", tag: "")
}

/// Provider-agnostic dispatcher. Tries providers in order; the first one that
/// returns a non-empty string wins. Mirrors the public surface of `brain.js`
/// (describeScreen, getCatResponse, summarizePdfImage, analyzeEmail,
/// askMouseQuestion, proactiveAssist, replyToUser) so coordinator code can be
/// written the same way it would be in JavaScript — minus the IPC.
///
/// Every method returns "" or an empty struct on total failure. The cat goes
/// silent rather than surfacing a stack trace.
final class Brain: Sendable {
    let providers: [ChatProvider]

    init(providers: [ChatProvider]) {
        self.providers = providers
    }

    /// Convenience: OpenAI primary, Gemini fallback. Reads API keys from env.
    static func defaultStack() -> Brain {
        Brain(providers: [OpenAIChat(), GeminiChat()])
    }

    // MARK: - Public APIs (mirror brain.js exports)

    /// One-line description of the screen image. Used by the autonomous
    /// observation loop. Returns "no observation" when no provider can answer
    /// (matches `brain.js:186-200`).
    func describeScreen(_ image: Data) async -> String {
        guard !image.isEmpty else { return "no observation" }
        let req = ChatRequest(
            system: """
            Describe what's on this screen in one short sentence. \
            Focus on the activity, not specific text content. \
            Don't mention specific names, emails, or sensitive information.
            """,
            user: "Describe this screen.",
            imageData: image,
            maxTokens: 80
        )
        let text = await dispatch(req)
        return text.isEmpty ? "no observation" : text
    }

    /// In-character response to a screen description. The autonomous loop
    /// drives this every ~30s. Returns CatResponse.empty if all providers
    /// fail OR the model returns silence — both are legitimate.
    func getCatResponse(description: String, memory: Memory) async -> CatResponse {
        let recent = memory.recentSaid(10)
        let payload: [String: Any] = [
            "screen_description": description,
            "session_count": memory.sessionCount,
            "recent_observations": memory.observations.suffix(10).map { obs in
                [
                    "at": ISO8601DateFormatter().string(from: obs.at),
                    "description": obs.description ?? "",
                    "tag": obs.tag ?? "",
                    "said": obs.said ?? "",
                ]
            },
            "recent_lines_already_said": recent,
            "output_format": [
                "response": "what the cat says, can be empty string",
                "tag": "short-tag-describing-what-happened",
            ],
            "instruction": "Return ONLY valid JSON with keys: response, tag.",
        ]
        let userText = jsonString(payload)

        let req = ChatRequest(
            system: Prompts.systemFromFile(),
            user: userText,
            jsonMode: true,
            maxTokens: 200
        )
        let raw = await dispatch(req)
        if raw.isEmpty { return .empty }
        if let parsed = decodeCatResponse(raw) { return parsed }
        // brain.js falls back to using the raw text as the response when the
        // model forgets to emit JSON. Keep parity.
        return CatResponse(response: raw, tag: "")
    }

    /// 2-4 sentence summary of a PDF page. Returns "" on failure; renderer
    /// shows a friendly fallback rather than an error.
    func summarizePdfImage(_ image: Data) async -> String {
        guard !image.isEmpty else { return "" }
        return await dispatch(ChatRequest(
            system: Prompts.pdf,
            user: "Summarize this page.",
            imageData: image,
            maxTokens: 250
        ))
    }

    /// Summary / draft reply / clarifying question for a selected Mail message.
    /// Always returns an EmailResult — fields may be empty on failure.
    func analyzeEmail(_ mail: MailSelection) async -> EmailResult {
        let userMsg = "Subject: \(mail.subject)\nFrom: \(mail.sender)\n\n\(mail.body)"
        let raw = await dispatch(ChatRequest(
            system: Prompts.email,
            user: userMsg,
            jsonMode: true,
            maxTokens: 400
        ))
        if raw.isEmpty { return .empty }

        if let parsed = decodeEmailResult(raw) { return parsed }
        // Match brain.js fallback: raw text becomes summary, others empty.
        return EmailResult(summary: raw, draftReply: "", clarifyingQuestion: "")
    }

    /// One short cat-question about a cursor-region image. Returns "" if the
    /// model decides the region is blank or wallpaper.
    func askMouseQuestion(_ region: Data) async -> String {
        guard !region.isEmpty else { return "" }
        let text = await dispatch(ChatRequest(
            system: Prompts.mouseQuestion,
            user: "Look at this region near the cursor and ask a short question.",
            imageData: region,
            maxTokens: 60
        ))
        return strippedQuotes(text)
    }

    /// Click-to-proactive: capture → cat says one thing, with dedup against
    /// recent_lines_already_said. Returns "" on total failure.
    func proactiveAssist(_ image: Data, memory: Memory) async -> String {
        guard !image.isEmpty else { return "" }
        let recent = memory.recentSaid(10)
        let payload: [String: Any] = [
            "instruction": "Look at the screen image attached. Say one short thing in your voice. Pick an angle you have NOT used recently.",
            "recent_lines_already_said": recent,
            "current_hour_24": Calendar.current.component(.hour, from: Date()),
        ]
        let text = await dispatch(ChatRequest(
            system: Prompts.proactive,
            user: jsonString(payload),
            imageData: image,
            maxTokens: 120
        ))
        return strippedQuotes(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cat reply to a user utterance (from mic or test harness). Returns a
    /// friendly placeholder when no provider can answer so the UI never goes
    /// silent on a direct address (matches `brain.js:322-331`).
    func replyToUser(_ userText: String) async -> String {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let req = ChatRequest(
            system: Prompts.userReply,
            user: String(trimmed.prefix(2000)),
            maxTokens: 120
        )
        let text = await dispatch(req)
        if text.isEmpty { return "mm. ask again in a bit." }
        return strippedQuotes(text)
    }

    // MARK: - Dispatcher

    /// Tries each provider in order; first non-empty response wins.
    private func dispatch(_ req: ChatRequest) async -> String {
        for provider in providers {
            guard await provider.isAvailable else { continue }
            let text = await provider.chat(req)
            if !text.isEmpty { return text }
        }
        return ""
    }

    // MARK: - JSON helpers

    private func jsonString(_ obj: [String: Any]) -> String {
        guard
            let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
            let str = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return str
    }

    private func decodeCatResponse(_ raw: String) -> CatResponse? {
        guard
            let data = raw.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        let response = (json["response"] as? String) ?? ""
        let tag = (json["tag"] as? String) ?? ""
        return CatResponse(response: response, tag: tag)
    }

    private func decodeEmailResult(_ raw: String) -> EmailResult? {
        guard
            let data = raw.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return EmailResult(
            summary: (json["summary"] as? String) ?? "",
            draftReply: (json["draftReply"] as? String) ?? "",
            clarifyingQuestion: (json["clarifyingQuestion"] as? String) ?? ""
        )
    }

    private func strippedQuotes(_ s: String) -> String {
        var out = s
        if out.hasPrefix("\"") || out.hasPrefix("'") { out.removeFirst() }
        if out.hasSuffix("\"") || out.hasSuffix("'") { out.removeLast() }
        return out
    }
}
