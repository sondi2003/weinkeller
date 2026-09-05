import Foundation

/// OpenAI Chat Completions mit `response_format: json_schema` (Structured Outputs).
///
/// Endpoint: `POST https://api.openai.com/v1/chat/completions`
/// Auth:     `Authorization: Bearer <key>`
struct OpenAIClient: AIProviderClient {

    let provider: AIProvider = .openAI
    private let transport: HTTPTransport
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    init(transport: HTTPTransport) {
        self.transport = transport
    }

    func recommend(_ request: PairingRequest, apiKey: String, model: String) async throws -> PairingResponse {
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": PromptBuilder.systemPrompt(maxRecommendations: request.maxRecommendations)],
                ["role": "user", "content": PromptBuilder.userPrompt(for: request)]
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "wine_pairing",
                    "strict": true,
                    "schema": RecommendationSchema.jsonSchema(includeAdditionalProperties: true)
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
        guard let content = choice.message.content, !content.isEmpty else {
            throw AIServiceError.emptyResponse
        }
        return try PairingResponse.decode(fromModelText: content)
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
