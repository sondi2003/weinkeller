import SwiftUI
import SwiftData

@main
struct WeinkellerApp: App {

    /// Ein gemeinsamer Container für die ganze App.
    private let modelContainer: ModelContainer = {
        let schema = Schema([Wine.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("ModelContainer konnte nicht erstellt werden: \(error)")
        }
    }()

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
        .modelContainer(modelContainer)
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
