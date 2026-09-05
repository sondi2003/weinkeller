import Foundation

// MARK: - Provider-Schnittstelle

/// Ein Client pro Anbieter. Jeder Client kennt seinen Endpoint und sein Payload-Format
/// und liefert Text, der einem JSON-Schema folgt (Structured Output).
protocol AIProviderClient: Sendable {
    var provider: AIProvider { get }

    /// Ob das Schema `additionalProperties: false` enthalten darf (Gemini lehnt es ab).
    var supportsAdditionalProperties: Bool { get }

    /// Schickt System- und User-Prompt und liefert den Antworttext, der `schema` folgt.
    func structuredText(
        system: String,
        user: String,
        schemaName: String,
        schema: [String: Any],
        apiKey: String,
        model: String
    ) async throws -> String
}

extension AIProviderClient {

    /// Wein-Empfehlung zu einem Gericht.
    func recommend(_ request: PairingRequest, apiKey: String, model: String) async throws -> PairingResponse {
        let text = try await structuredText(
            system: PromptBuilder.systemPrompt(maxRecommendations: request.maxRecommendations),
            user: PromptBuilder.userPrompt(for: request),
            schemaName: "wine_pairing",
            schema: RecommendationSchema.jsonSchema(includeAdditionalProperties: supportsAdditionalProperties),
            apiKey: apiKey,
            model: model
        )
        return try PairingResponse.decode(fromModelText: text)
    }

    /// Etikett-Text zu Feldern zuordnen.
    func extractLabel(recognizedText: String, apiKey: String, model: String) async throws -> WineLabelExtraction {
        let text = try await structuredText(
            system: PromptBuilder.labelSystemPrompt,
            user: PromptBuilder.labelUserPrompt(recognizedText: recognizedText),
            schemaName: "wine_label",
            schema: LabelSchema.jsonSchema(includeAdditionalProperties: supportsAdditionalProperties),
            apiKey: apiKey,
            model: model
        )
        return try JSONDecoding.decode(WineLabelExtraction.self, fromModelText: text)
    }
}

// MARK: - Fassade

/// Zentrale Anlaufstelle für die UI / ViewModels.
///
/// Der Service ist bewusst zustandslos: Anbieter, Key und Modell werden pro Aufruf übergeben
/// (typischerweise aus `AISettings`). Dadurch lässt er sich in Tests mit Fake-Clients füttern
/// und ist nicht an den Main Actor gebunden.
final class AIService: Sendable {

    private let clients: [AIProvider: any AIProviderClient]

    /// Standard-Konfiguration mit den drei echten Clients.
    convenience init(session: URLSession = .shared) {
        let transport = HTTPTransport(session: session)
        self.init(clients: [
            OpenAIClient(transport: transport),
            GeminiClient(transport: transport),
            AnthropicClient(transport: transport)
        ])
    }

    /// Für Tests oder um einzelne Anbieter auszutauschen.
    init(clients: [any AIProviderClient]) {
        self.clients = Dictionary(uniqueKeysWithValues: clients.map { ($0.provider, $0) })
    }

    private func client(for provider: AIProvider) -> any AIProviderClient {
        guard let client = clients[provider] else {
            preconditionFailure("Kein Client für \(provider) registriert.")
        }
        return client
    }

    // MARK: Wein-Empfehlung

    /// Holt eine Top-N-Empfehlung vom gewünschten Anbieter.
    func recommend(
        _ request: PairingRequest,
        provider: AIProvider,
        apiKey: String,
        model: String
    ) async throws -> PairingResponse {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIServiceError.missingAPIKey(provider) }
        guard !request.inventory.isEmpty else {
            // Kein Netzwerkaufruf nötig – die KI könnte ohnehin nichts empfehlen.
            return PairingResponse(
                recommendations: [],
                generalNote: "Der Weinkeller ist leer. Lege zuerst Flaschen an, damit ich etwas empfehlen kann."
            )
        }
        return try await client(for: provider).recommend(request, apiKey: key, model: model)
    }

    /// Bequemer Einstieg direkt aus den Einstellungen heraus: verwendet automatisch
    /// den Anbieter, für den ein API-Key hinterlegt ist.
    @MainActor
    func recommend(_ request: PairingRequest, using settings: AISettings) async throws -> PairingResponse {
        guard let provider = settings.activeProvider else {
            throw AIServiceError.noProviderConfigured
        }
        return try await recommend(
            request,
            provider: provider,
            apiKey: settings.apiKey(for: provider),
            model: settings.model(for: provider)
        )
    }

    // MARK: Etikett-Erkennung

    /// Ordnet OCR-Text den Weinfeldern zu – über den angegebenen Cloud-Anbieter.
    func extractLabel(
        recognizedText: String,
        provider: AIProvider,
        apiKey: String,
        model: String
    ) async throws -> WineLabelExtraction {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIServiceError.missingAPIKey(provider) }
        return try await client(for: provider).extractLabel(recognizedText: recognizedText, apiKey: key, model: model)
    }
}

// MARK: - Gemeinsames Decoding strukturierter Antworten

enum JSONDecoding {

    /// Dekodiert den JSON-Text, den ein Anbieter im Structured-Output-Modus liefert.
    /// Entfernt vorsorglich Markdown-Codefences (```json … ```), falls ein Modell sie doch mitschickt.
    static func decode<T: Decodable>(_ type: T.Type, fromModelText text: String) throws -> T {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = cleaned.data(using: .utf8), !data.isEmpty else {
            throw AIServiceError.emptyResponse
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AIServiceError.decodingFailed(error.localizedDescription)
        }
    }
}

extension PairingResponse {
    static func decode(fromModelText text: String) throws -> PairingResponse {
        var response = try JSONDecoding.decode(PairingResponse.self, fromModelText: text)
        response.recommendations = response.sortedRecommendations
        return response
    }
}
