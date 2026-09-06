import Foundation

/// OpenAI Chat Completions mit `response_format: json_schema` (Structured Outputs).
///
/// Endpoint: `POST https://api.openai.com/v1/chat/completions`
/// Auth:     `Authorization: Bearer <key>`
struct OpenAIClient: AIProviderClient {

    let provider: AIProvider = .openAI
    let supportsAdditionalProperties = true
    private let transport: HTTPTransport
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    init(transport: HTTPTransport) {
        self.transport = transport
    }

    func structuredText(
        system: String,
        user: String,
        schemaName: String,
        schema: [String: Any],
        speed: AISpeed,
        apiKey: String,
        model: String
    ) async throws -> String {
        // Tempo steuert bei OpenAI die Modellwahl, die der Aufrufer trifft – kein Body-Unterschied.
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": schemaName,
                    "strict": true,
                    "schema": schema
                ]
            ]
        ]

        let data = try await transport.postJSON(
            url: endpoint,
            provider: provider,
            headers: ["Authorization": "Bearer \(apiKey)"],
            body: body
        )

        let decoded: ChatCompletionResponse
        do {
            decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        } catch {
            throw AIServiceError.decodingFailed("OpenAI-Antwort: \(error.localizedDescription)")
        }

        guard let choice = decoded.choices.first else { throw AIServiceError.emptyResponse }
        if let refusal = choice.message.refusal, !refusal.isEmpty {
            throw AIServiceError.refused(refusal)
        }
        if choice.finishReason == "length" {
            throw AIServiceError.truncated
        }
        guard let content = choice.message.content, !content.isEmpty else {
            throw AIServiceError.emptyResponse
        }
        return content
    }

    // MARK: Antwort-Modell (nur die Felder, die wir brauchen)

    private struct ChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
                let refusal: String?
            }
            let message: Message
            let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case message
                case finishReason = "finish_reason"
            }
        }
        let choices: [Choice]
    }
}
