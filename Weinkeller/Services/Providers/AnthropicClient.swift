import Foundation

/// Anthropic Messages API mit Structured Output (`output_config.format`).
///
/// Endpoint: `POST https://api.anthropic.com/v1/messages`
/// Auth:     `x-api-key: <key>` + `anthropic-version: 2023-06-01`
///
/// Hinweise zum Standardmodell `claude-opus-5`:
/// - Adaptives Thinking ist standardmäßig aktiv; der `thinking`-Parameter wird deshalb weggelassen.
/// - Server-seitige Fallbacks (`fallbacks: "default"`) sind aktiviert: sollte ein Safety-Filter
///   die Anfrage ablehnen, beantwortet Anthropic sie im selben Call mit einem Ersatzmodell.
///   Bei einem Wein-Berater praktisch irrelevant, kostet aber nichts. Wer das nicht möchte,
///   entfernt `fallbacks` und den `anthropic-beta`-Header.
struct AnthropicClient: AIProviderClient {

    let provider: AIProvider = .anthropic
    private let transport: HTTPTransport
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    init(transport: HTTPTransport) {
        self.transport = transport
    }

    func recommend(_ request: PairingRequest, apiKey: String, model: String) async throws -> PairingResponse {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 8192,
            "system": PromptBuilder.systemPrompt(maxRecommendations: request.maxRecommendations),
            "messages": [
                ["role": "user", "content": PromptBuilder.userPrompt(for: request)]
            ],
            "output_config": [
                "format": [
                    "type": "json_schema",
                    "schema": RecommendationSchema.jsonSchema(includeAdditionalProperties: true)
                ]
            ],
            "fallbacks": "default"
        ]

        let data = try await transport.postJSON(
            url: endpoint,
            provider: provider,
            headers: [
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01",
                "anthropic-beta": "server-side-fallback-2026-07-01"
            ],
            body: body
        )

        let decoded: MessagesResponse
        do {
            decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
        } catch {
            throw AIServiceError.decodingFailed("Anthropic-Antwort: \(error.localizedDescription)")
        }

        // Immer zuerst `stop_reason` prüfen – bei "refusal" ist `content` nicht schema-konform.
        if decoded.stopReason == "refusal" {
            throw AIServiceError.refused(decoded.stopDetails?.explanation ?? decoded.stopDetails?.category)
        }

        let text = decoded.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()
        guard !text.isEmpty else { throw AIServiceError.emptyResponse }
        return try PairingResponse.decode(fromModelText: text)
    }

    // MARK: Antwort-Modell

    private struct MessagesResponse: Decodable {
        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }
        struct StopDetails: Decodable {
            let category: String?
            let explanation: String?
        }
        let content: [ContentBlock]
        let stopReason: String?
        let stopDetails: StopDetails?

        enum CodingKeys: String, CodingKey {
            case content
            case stopReason = "stop_reason"
            case stopDetails = "stop_details"
        }
    }
}
