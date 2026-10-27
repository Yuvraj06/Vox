import Foundation

/// Calls the Gemini API with the user's own key. Returns actions in the same shape as the on-device Brain,
/// so the same preview, executor and undo work for both.
struct GeminiClient {
    enum Failure: Error, LocalizedError {
        case http(Int, String)
        case badReply

        var errorDescription: String? {
            switch self {
            case .http(400, let message): "Gemini didn't accept the request: \(message)"
            case .http(401, _), .http(403, _): "Gemini didn't accept the API key."
            case .http(404, _): "Gemini doesn't know that model name."
            case .http(429, _): "Gemini's free limit is used up for now."
            case .http(let code, let message): "Gemini error \(code): \(message)"
            case .badReply: "Gemini sent back something I couldn't read."
            }
        }
    }

    let apiKey: String
    let model: String

    /// Some models don't take a thinking level. Remembered after the first refusal.
    private static var skipThinkingLevel = false

    /// Works out actions for a command. `outline` is every title in the notes, with short ids like n3.
    /// `here` says which screen is open, from `BrainContext.hereLine()`.
    func plan(command: String, outline: String, here: String? = nil) async throws -> [BrainAction] {
        let prompt = (here.map { $0 + "\n" } ?? "") + "Command: \(command)\n\nNotes:\n\(outline)"
        do {
            return try await send(prompt, thinkingLevel: !Self.skipThinkingLevel)
        } catch Failure.http(400, let message) where message.lowercased().contains("thinking") && !Self.skipThinkingLevel {
            Self.skipThinkingLevel = true
            return try await send(prompt, thinkingLevel: false)
        }
    }

    private func send(_ prompt: String, thinkingLevel: Bool) async throws -> [BrainAction] {
        let escapedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(escapedModel):generateContent")!
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        var config: [String: Any] = [
            "responseMimeType": "application/json",
            "responseSchema": Self.schema,
            "temperature": 0,
        ]
        // Less thinking means a faster answer, which matters for the 3 second window.
        if thinkingLevel { config["thinkingConfig"] = ["thinkingLevel": "low"] }
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": BrainInstructions.gemini]]],
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": config,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.http(status, Self.errorMessage(in: data)) }
        return try Self.actions(in: data)
    }

    // MARK: Reply

    /// Reads candidates[0].content.parts[].text, skipping thought parts, and decodes the plan from it.
    private static func actions(in data: Data) throws -> [BrainAction] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidate = (root["candidates"] as? [[String: Any]])?.first,
              let parts = (candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]]
        else { throw Failure.badReply }
        let text = parts
            .filter { ($0["thought"] as? Bool) != true }
            .compactMap { $0["text"] as? String }
            .joined()
        guard let json = text.data(using: .utf8),
              let plan = try? JSONDecoder().decode(BrainPlan.self, from: json)
        else { throw Failure.badReply }
        return plan.actions
    }

    private static func errorMessage(in data: Data) -> String {
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let message = (root?["error"] as? [String: Any])?["message"] as? String
        return message ?? String(decoding: data.prefix(200), as: UTF8.self)
    }

    // MARK: Schema

    /// The same flat action shape as `BrainAction`, so Gemini can only answer with valid actions.
    private static var schema: [String: Any] {
        func text() -> [String: Any] { ["type": "STRING", "nullable": true] }
        func choice(_ values: [String]) -> [String: Any] { ["type": "STRING", "format": "enum", "enum": values, "nullable": true] }
        let action: [String: Any] = [
            "type": "OBJECT",
            "properties": [
                "type": ["type": "STRING", "format": "enum", "enum": ActionType.allCases.map(\.rawValue)],
                "target": text(),
                "parent": text(),
                "title": text(),
                "kind": choice(KindChoice.allCases.map(\.rawValue)),
                "view": choice(ViewChoice.allCases.map(\.rawValue)),
                "status": choice(StatusChoice.allCases.map(\.rawValue)),
                "key": text(),
                "value": text(),
                "timePhrase": text(),
                "estimateMinutes": ["type": "INTEGER", "nullable": true],
                "reminderKind": choice(ReminderChoice.allCases.map(\.rawValue)),
                "question": text(),
            ],
            "required": ["type"],
        ]
        return [
            "type": "OBJECT",
            "properties": ["actions": ["type": "ARRAY", "items": action]],
            "required": ["actions"],
        ]
    }
}
