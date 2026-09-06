import Foundation
import SwiftData

/// Beispieldaten für Xcode-Previews. Läuft komplett im Speicher.
@MainActor
enum PreviewData {

    static let sampleWines: [Wine] = [
        Wine(name: "Les Murettes", producer: "Fendant", vintage: 2022, grape: "Chasselas", region: "Wallis", type: .white, quantity: 4),
        Wine(name: "Cannubi", producer: "Barolo", vintage: 2017, grape: "Nebbiolo", region: "Piemont", type: .red, quantity: 2, notes: "Ab 2027 trinken, vorher dekantieren."),
        Wine(name: "La Pinède", producer: "Domaine La Tour Vieille", vintage: 2019, grape: "Grenache noir, Mourvèdre, Carignan", region: "Collioure", country: "Frankreich", type: .red, quantity: 1, notes: "Schieferterrassen am Mittelmeer, lange Mazeration, Ausbau im Tank.", foodPairings: ["Gegrilltes Fleisch", "Lamm", "Hartkäse"]),
        Wine(name: "Riesling Kabinett", vintage: 2021, grape: "Riesling", region: "Mosel", type: .white, quantity: 0),
        Wine(name: "Franciacorta Brut", vintage: 2019, grape: "Chardonnay", region: "Lombardei", type: .sparkling, quantity: 3),
        Wine(name: "Whispering Angel", producer: "Château d'Esclans", vintage: 2023, grape: "Grenache", region: "Provence", type: .rose, quantity: 6),
        Wine(name: "Amarone Classico", vintage: 2012, grape: "Corvina", region: "Venetien", type: .red, quantity: 1, isArchived: true)
    ]

    /// Container mit Beispielweinen.
    static let container: ModelContainer = {
        let container = makeContainer()
        for wine in sampleWines {
            container.mainContext.insert(wine)
        }
        return container
    }()

    /// Leerer Container für den Empty State.
    static let emptyContainer: ModelContainer = makeContainer()

    /// Eigene UserDefaults-Suite, damit Previews die echten Einstellungen nicht anfassen.
    static let defaults: UserDefaults = {
        let suite = UserDefaults(suiteName: "preview.weinkeller")!
        suite.removePersistentDomain(forName: "preview.weinkeller")
        return suite
    }()

    static let sampleResponse = PairingResponse(
        recommendations: [
            PairingRecommendation(
                rank: 1,
                wineName: "Cannubi",
                vintage: 2017,
                fit: .excellent,
                reasoning: "Die kräftigen Tannine und die Säure des Nebbiolo schneiden durch das Fett der Bolognese, während Kirsch- und Teernoten die Tomaten und das geschmorte Fleisch aufgreifen.",
                servingTip: "Eine Stunde dekantieren, bei 17 °C im großen Burgunderglas servieren."
            ),
            PairingRecommendation(
                rank: 2,
                wineName: "La Pinède",
                vintage: 2019,
                fit: .good,
                reasoning: "Warme Grenache-Frucht mit der Würze von Mourvèdre – passt gut zu Tomate und Hackfleisch, mit etwas weniger Struktur als der Barolo.",
                servingTip: "Bei 16 °C servieren, 30 Minuten atmen lassen."
            )
        ],
        generalNote: "Ein Rotwein mit guter Säurestruktur ist die klassische Wahl zur Bolognese.",
        noGoodMatch: false,
        shoppingTip: "Klassisch: ein Sangiovese aus der Toskana (Chianti Classico) oder ein Barbera d'Alba."
    )

    private static func makeContainer() -> ModelContainer {
        let schema = Schema([Wine.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Preview-Container konnte nicht erstellt werden: \(error)")
        }
    }
}
