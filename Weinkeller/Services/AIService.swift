import Foundation

// MARK: - Provider-Schnittstelle

/// Ein Client pro Anbieter. Jeder Client kennt seinen Endpoint, sein Payload-Format
/// und wie er die Antwort in ein `PairingResponse` verwandelt.
protocol AIProviderClient: Sendable {
    var provider: AIProvider { get }

    func recommend(
        _ request: PairingRequest,
        apiKey: String,
        model: String
    ) async throws -> PairingResponse
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

    /// Holt eine Top-N-Empfehlung vom gewünschten Anbieter.
    ///
    /// - Parameters:
    ///   - request: Gericht + Inventar.
    ///   - provider: Welcher Anbieter angesprochen wird.
    ///   - apiKey: Der Key des Nutzers für genau diesen Anbieter.
    ///   - model: Modellname, z. B. `provider.defaultModel`.
    func recommend(
        _ request: PairingRequest,
        provider: AIProvider,
        apiKey: String,
        model: String
    ) async throws -> PairingResponse {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIServiceError.missingAPIKey(provider) }
        guard let client = clients[provider] else {
            preconditionFailure("Kein Client für \(provider) registriert.")
        }
        guard !request.inventory.isEmpty else {
            // Kein Netzwerkaufruf nötig – die KI könnte ohnehin nichts empfehlen.
            return PairingResponse(
                recommendations: [],
                generalNote: "Der Weinkeller ist leer. Lege zuerst Flaschen an, damit ich etwas empfehlen kann."
            )
        }
        return try await client.recommend(request, apiKey: key, model: model)
    }

    /// Bequemer Einstieg direkt aus den Einstellungen heraus: verwendet automatisch
    /// den Anbieter, für den ein API-Key hinterlegt ist.
    @MainActor
    func recommend(_ request: PairingRequest, using settings: AISettings) async throws -> PairingResponse {
        guard let provider = settings.activeProvider else {
            throw AIServiceError.noProviderConfigured
        }
        let apiKey = settings.apiKey(for: provider)
        let model = settings.model(for: provider)
        return try await recommend(request, provider: provider, apiKey: apiKey, model: model)
    }
}
