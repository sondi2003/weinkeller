import Foundation
import Observation

/// Persistente Einstellungen für den KI-Layer.
///
/// - Modellnamen und bevorzugter Anbieter: `UserDefaults` (unkritisch).
/// - API-Keys: Keychain (siehe `KeychainStore`).
///
/// Aktiv ist automatisch der Anbieter, für den ein API-Key hinterlegt ist.
/// Sind mehrere Keys hinterlegt, entscheidet `preferredProvider` (wählbar in den Einstellungen).
///
/// Als `@Observable` kann die Klasse direkt in SwiftUI-Views eingebunden werden;
/// die Views aktualisieren sich, wenn sich Keys oder Modelle ändern.
@Observable
@MainActor
final class AISettings {

    private enum Keys {
        static let preferredProvider = "ai.preferredProvider"
        static func model(for provider: AIProvider) -> String { "ai.model.\(provider.rawValue)" }
    }

    private let defaults: UserDefaults

    /// Nur relevant, wenn mehr als ein Anbieter einen Key hat.
    var preferredProvider: AIProvider {
        didSet { defaults.set(preferredProvider.rawValue, forKey: Keys.preferredProvider) }
    }

    /// Spiegel der Keychain, damit SwiftUI Änderungen mitbekommt.
    /// Die Keychain selbst ist nicht observierbar.
    private(set) var apiKeys: [AIProvider: String] = [:]

    /// Modellnamen pro Anbieter; leer = `provider.defaultModel`.
    private(set) var models: [AIProvider: String] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let stored = defaults.string(forKey: Keys.preferredProvider)
            .flatMap(AIProvider.init(rawValue:))
        self.preferredProvider = stored ?? .anthropic

        for provider in AIProvider.allCases {
            apiKeys[provider] = KeychainStore.string(for: provider.rawValue) ?? ""
            models[provider] = defaults.string(forKey: Keys.model(for: provider)) ?? ""
        }
    }

    // MARK: API-Keys

    func apiKey(for provider: AIProvider) -> String {
        apiKeys[provider] ?? ""
    }

    func hasAPIKey(for provider: AIProvider) -> Bool {
        !apiKey(for: provider).isEmpty
    }

    /// Speichert den Key in der Keychain. Ein leerer String löscht ihn.
    func setAPIKey(_ key: String, for provider: AIProvider) throws {
        try KeychainStore.set(key, for: provider.rawValue)
        apiKeys[provider] = key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Modelle

    /// Das effektiv verwendete Modell (Nutzer-Eingabe oder Standard).
    func model(for provider: AIProvider) -> String {
        let custom = (models[provider] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? provider.defaultModel : custom
    }

    /// Der rohe, vom Nutzer eingegebene Modellname (für das Textfeld in den Einstellungen).
    func customModel(for provider: AIProvider) -> String {
        models[provider] ?? ""
    }

    func setCustomModel(_ model: String, for provider: AIProvider) {
        models[provider] = model
        defaults.set(model, forKey: Keys.model(for: provider))
    }

    // MARK: Aktiver Anbieter

    /// Alle Anbieter mit hinterlegtem Key, in der Reihenfolge von `AIProvider.allCases`.
    var configuredProviders: [AIProvider] {
        AIProvider.allCases.filter { hasAPIKey(for: $0) }
    }

    /// Der Anbieter, der für Anfragen verwendet wird – oder `nil`, wenn kein Key hinterlegt ist.
    ///
    /// Genau ein Key → dieser Anbieter. Mehrere Keys → `preferredProvider`, sofern er
    /// einen Key hat, sonst der erste konfigurierte.
    var activeProvider: AIProvider? {
        let configured = configuredProviders
        if configured.contains(preferredProvider) { return preferredProvider }
        return configured.first
    }

    /// Modell des aktiven Anbieters.
    var activeModel: String? {
        activeProvider.map { model(for: $0) }
    }

    /// `true`, wenn der Nutzer zwischen mehreren konfigurierten Anbietern wählen kann.
    var hasMultipleProviders: Bool {
        configuredProviders.count > 1
    }
}
