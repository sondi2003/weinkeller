import Foundation

/// Anthropic Messages API mit Structured Output (`output_config.format`).
///
/// Endpoint: `POST https://api.anthropic.com/v1/messages`
/// Auth:     `x-api-key: <key>` + `anthropic-version: 2023-06-01`
///
/// Hinweise zum Standardmodell `claude-opus-5`:
/// - Adaptives Thinking ist standardmässig aktiv; der `thinking`-Parameter wird deshalb weggelassen.
/// - Server-seitige Fallbacks (`fallbacks: "default"`) sind aktiviert: sollte ein Safety-Filter
///   die Anfrage ablehnen, beantwortet Anthropic sie im selben Call mit einem Ersatzmodell.
///   Bei einem Wein-Berater praktisch irrelevant, kostet aber nichts. Wer das nicht möchte,
///   entfernt `fallbacks` und den `anthropic-beta`-Header.
struct AnthropicClient: AIProviderClient {

    let provider: AIProvider = .anthropic
    let supportsAdditionalProperties = true
    private let transport: HTTPTransport
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

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
        // Adaptives Thinking zählt zum max_tokens-Budget. Ein zu knappes Budget führt dazu, dass das
        // Modell das Schema nur noch mit Minimal-Inhalten füllt („placeholder“, "x", 0). Deshalb
        // grosszügiges Limit und moderater Denkaufwand – für ein Wein-Pairing reicht das völlig.
        var outputConfig: [String: Any] = [
            "format": [
                "type": "json_schema",
                "schema": schema
            ]
        ]
        // Haiku kennt keinen Denkaufwand; das Feld würde die Anfrage scheitern lassen.
        if !model.lowercased().contains("haiku") {
            // Für Siri weniger Denkaufwand, damit die Antwort schnell kommt.
            outputConfig["effort"] = speed == .fast ? "low" : "medium"
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": system,
            "messages": [
                ["role": "user", "content": user]
            ],
            "output_config": outputConfig,
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
        if decoded.stopReason == "max_tokens" {
            throw AIServiceError.truncated
        }

        let text = decoded.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()
        guard !text.isEmpty else { throw AIServiceError.emptyResponse }
        return text
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
