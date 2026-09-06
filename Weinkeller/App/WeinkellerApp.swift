import SwiftUI

@main
struct WeinkellerApp: App {

    /// Nötig, damit Freigabe-Einladungen ankommen (siehe SceneDelegate).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Core Data mit CloudKit. Wird von App und Siri-Intent gemeinsam genutzt.
    private let persistence = PersistenceController.shared

    /// Einstellungen (Provider, Modelle, Keys) – einmal pro App-Lebenszyklus.
    @State private var settings = AISettings()

    /// Der KI-Service ist zustandslos und kann geteilt werden.
    private let aiService = AIService()

    /// Hell, dunkel oder dem System folgen. Gilt für die ganze App.
    @AppStorage(AppearanceSetting.storageKey) private var appearance: AppearanceSetting = .system

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(\.aiService, aiService)
                .environment(\.managedObjectContext, persistence.viewContext)
                .preferredColorScheme(appearance.colorScheme)
                .task {
                    // Einmalige Übernahme aus der früheren SwiftData-Ablage.
                    LegacyImporter.importIfNeeded(into: persistence.viewContext)
                }
        }
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
