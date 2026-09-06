import SwiftUI
import SwiftData

@main
struct WeinkellerApp: App {

    /// Einstellungen (Provider, Modelle, Keys) – einmal pro App-Lebenszyklus.
    @State private var settings = AISettings()

    /// Der KI-Service ist zustandslos und kann geteilt werden.
    private let aiService = AIService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(\.aiService, aiService)
        }
        // Derselbe Container, den auch die Siri-Intents verwenden.
        .modelContainer(SharedModelContainer.shared)
    }
}

// MARK: - AIService per Environment verfügbar machen

private struct AIServiceKey: EnvironmentKey {
    static let defaultValue = AIService()
}

extension EnvironmentValues {
    var aiService: AIService {
        get { self[AIServiceKey.self] }
        set { self[AIServiceKey.self] = newValue }
    }
}
