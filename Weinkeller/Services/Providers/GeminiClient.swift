import Foundation

/// Google Gemini `generateContent` mit `responseMimeType: application/json` + `responseSchema`.
///
/// Endpoint: `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`
/// Auth:     `x-goog-api-key: <key>`
struct GeminiClient: AIProviderClient {

    let provider: AIProvider = .gemini
    /// Gemini akzeptiert kein `additionalProperties` im Schema.
    let supportsAdditionalProperties = false
    private let transport: HTTPTransport
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    init(transport: HTTPTransport) {
        self.transport = transport
    }

    func structuredText(
        system: String,
        user: String,
        schemaName: String,
        schema: [String: Any],
        apiKey: String,
        model: String
    ) async throws -> String {
        guard let url = URL(string: "\(baseURL)/\(model):generateContent") else {
            throw AIServiceError.invalidURL
        }

        let body: [String: Any] = [
            "system_instruction": [
                "parts": [["text": system]]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": user]]
                ]
            ],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": schema,
                "temperature": 0.4
            ]
        ]

        let data = try await transport.postJSON(
            url: url,
            provider: provider,
            headers: ["x-goog-api-key": apiKey],
            body: body
        )

        let decoded: GenerateContentResponse
        do {
            decoded = try JSONDecoder().decode(GenerateContentResponse.self, from: data)
        } catch {
            throw AIServiceError.decodingFailed("Gemini-Antwort: \(error.localizedDescription)")
        }

        if let blockReason = decoded.promptFeedback?.blockReason {
            throw AIServiceError.refused(blockReason)
        }
        guard let candidate = decoded.candidates?.first else { throw AIServiceError.emptyResponse }
        if candidate.finishReason == "SAFETY" || candidate.finishReason == "PROHIBITED_CONTENT" {
            throw AIServiceError.refused(candidate.finishReason)
        }
        if candidate.finishReason == "MAX_TOKENS" {
            throw AIServiceError.truncated
        }

        let text = (candidate.content?.parts ?? [])
            .compactMap(\.text)
            .joined()
        guard !text.isEmpty else { throw AIServiceError.emptyResponse }
        return text
    }

    // MARK: Antwort-Modell

    private struct GenerateContentResponse: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable {
                    let text: String?
                }
                let parts: [Part]?
            }
            let content: Content?
            let finishReason: String?
        }
        struct PromptFeedback: Decodable {
            let blockReason: String?
        }
        let candidates: [Candidate]?
        let promptFeedback: PromptFeedback?
    }
}
