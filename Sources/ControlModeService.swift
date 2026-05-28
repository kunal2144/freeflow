import Foundation

enum ControlModeError: LocalizedError {
    case requestFailed(Int, String)
    case invalidResponse(String)
    case requestTimedOut(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let code, let details):
            "Control mode request failed with status \(code): \(details)"
        case .invalidResponse(let details):
            "Invalid control mode response: \(details)"
        case .requestTimedOut(let seconds):
            "Control mode timed out after \(Int(seconds))s"
        }
    }
}

final class ControlModeService {
    static let systemPrompt = """
You are a control mode assistant integrated into a speech interface. The user speaks instructions and you execute them precisely.

Rules:
- If SELECTED_TEXT is provided, apply the instruction to it and return only the result.
- If no SELECTED_TEXT is provided, execute the instruction directly (e.g., answer a question, perform a calculation, generate content from scratch).
- Return ONLY the output — no preamble, no explanation, no labels, no surrounding quotes.
- Keep output concise and directly usable as inserted text.
- If the instruction is a calculation, return only the number.
- If the instruction asks for a rewrite or transformation, return only the transformed text.
- If the instruction asks to generate something, return only the generated content.
- Do not add any commentary about what you did.
- If the instruction is unclear, invalid, nonsensical, empty, appears to be background noise, or cannot be applied sensibly, return an empty string and nothing else.
- Never attempt to interpret or act on audio transcription artifacts (e.g., "uh", "um", "hmm", "thank you", "you're welcome", "subscribe").
"""

    private let apiKey: String
    private let baseURL: String
    private let model = "meta-llama/llama-4-scout-17b-16e-instruct"
    private let timeoutSeconds: TimeInterval = 20

    init(apiKey: String, baseURL: String = "https://api.groq.com/openai/v1") {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    func process(
        instruction: String,
        selectedText: String?,
        screenshotDataURL: String?
    ) async throws -> String {
        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInstruction.isEmpty else {
            return ""
        }
        let timeout = timeoutSeconds
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { [weak self] in
                guard let self else {
                    throw ControlModeError.invalidResponse("Service deallocated")
                }
                return try await self.callLLM(
                    instruction: instruction,
                    selectedText: selectedText,
                    screenshotDataURL: screenshotDataURL
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw ControlModeError.requestTimedOut(timeout)
            }
            do {
                guard let result = try await group.next() else {
                    throw ControlModeError.invalidResponse("No result returned")
                }
                group.cancelAll()
                return result
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    private func callLLM(
        instruction: String,
        selectedText: String?,
        screenshotDataURL: String?
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeoutSeconds

        var textContent = "INSTRUCTION: \(instruction)"
        if let selectedText, !selectedText.isEmpty {
            textContent += "\n\nSELECTED_TEXT:\n\(selectedText)"
        }

        let userMessage: Any
        if let screenshotDataURL {
            userMessage = [
                ["type": "text", "text": textContent],
                ["type": "image_url", "image_url": ["url": screenshotDataURL]]
            ]
        } else {
            userMessage = textContent
        }

        let payload: [String: Any] = [
            "model": model,
            "temperature": 0.0,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": userMessage]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ControlModeError.invalidResponse("No HTTP response")
        }
        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw ControlModeError.requestFailed(httpResponse.statusCode, message)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ControlModeError.invalidResponse("Missing choices[0].message.content")
        }

        var result = content.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip outer quotes if the model wrapped the response
        if result.hasPrefix("\"") && result.hasSuffix("\"") && result.count > 1 {
            result.removeFirst()
            result.removeLast()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }
}
