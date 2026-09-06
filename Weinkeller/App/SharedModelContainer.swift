import Foundation
import SwiftData

/// Ein gemeinsamer SwiftData-Container für App und Siri-Intents.
///
/// App Intents laufen im Prozess der App, aber nicht zwingend über die SwiftUI-Szene.
/// Beide Wege müssen denselben Container verwenden, sonst sieht Siri einen leeren Keller.
enum SharedModelContainer {

    static let shared: ModelContainer = {
        let schema = Schema([Wine.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("ModelContainer konnte nicht erstellt werden: \(error)")
        }
    }()

    /// Alle Weine, die aktuell trinkbereit im Keller liegen.
    @MainActor
    static func availableWines() throws -> [Wine] {
        let descriptor = FetchDescriptor<Wine>(sortBy: [SortDescriptor(\.name)])
        return try shared.mainContext.fetch(descriptor)
            .filter { !$0.isArchived && $0.quantity > 0 }
    }
}
