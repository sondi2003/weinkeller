import Foundation
import SwiftData

/// Beispieldaten für Xcode-Previews. Läuft komplett im Speicher.
@MainActor
enum PreviewData {

    static let sampleWines: [Wine] = [
        Wine(name: "Fendant Les Murettes", vintage: 2022, grapeOrRegion: "Chasselas, Wallis", type: .white, quantity: 4),
        Wine(name: "Barolo Cannubi", vintage: 2017, grapeOrRegion: "Nebbiolo, Piemont", type: .red, quantity: 2, notes: "Ab 2027 trinken, vorher dekantieren."),
        Wine(name: "Château Margaux", vintage: 2015, grapeOrRegion: "Cabernet Sauvignon, Bordeaux", type: .red, quantity: 1, notes: "Geschenk von Anna"),
        Wine(name: "Riesling Kabinett", vintage: 2021, grapeOrRegion: "Riesling, Mosel", type: .white, quantity: 0),
        Wine(name: "Franciacorta Brut", vintage: 2019, grapeOrRegion: "Chardonnay, Lombardei", type: .sparkling, quantity: 3),
        Wine(name: "Whispering Angel", vintage: 2023, grapeOrRegion: "Grenache, Provence", type: .rose, quantity: 6),
        Wine(name: "Amarone Classico", vintage: 2012, grapeOrRegion: "Corvina, Venetien", type: .red, quantity: 1, isArchived: true)
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
                wineName: "Barolo Cannubi",
                vintage: 2017,
                reasoning: "Die kräftigen Tannine und die Säure des Nebbiolo schneiden durch das Fett der Bolognese, während Kirsch- und Teernoten die Tomaten und das geschmorte Fleisch aufgreifen.",
                servingTip: "Eine Stunde dekantieren, bei 17 °C im großen Burgunderglas servieren."
            ),
            PairingRecommendation(
                rank: 2,
                wineName: "Château Margaux",
                vintage: 2015,
                reasoning: "Feiner, eleganter Bordeaux mit Cassis und Zedernholz – passt, ist aber fast zu schade für ein Alltagsgericht.",
                servingTip: "Bei 18 °C servieren, mindestens 45 Minuten atmen lassen."
            )
        ],
        generalNote: "Ein Rotwein mit guter Säurestruktur ist die klassische Wahl zur Bolognese."
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
