import CoreData
import Foundation

/// Beispieldaten für Xcode-Previews. Läuft komplett im Speicher, ohne CloudKit.
@MainActor
enum PreviewData {

    /// Gefüllter Speicher für Previews.
    static let controller: PersistenceController = {
        let controller = PersistenceController(inMemory: true, useCloudKit: false)
        let context = controller.viewContext
        let cellar = Cellar.findOrCreateDefault(in: context)

        Wine.create(in: context, cellar: cellar, name: "Les Murettes", producer: "Fendant",
                    vintage: 2022, grape: "Chasselas", region: "Wallis", country: "Schweiz",
                    type: .white, quantity: 4)
        Wine.create(in: context, cellar: cellar, name: "Cannubi", producer: "Barolo",
                    vintage: 2017, grape: "Nebbiolo", region: "Piemont", country: "Italien",
                    type: .red, quantity: 2, notes: "Ab 2027 trinken, vorher dekantieren.")
        Wine.create(in: context, cellar: cellar, name: "La Pinède", producer: "Domaine La Tour Vieille",
                    vintage: 2019, grape: "Grenache noir, Mourvèdre, Carignan", region: "Collioure",
                    country: "Frankreich", type: .red, quantity: 1,
                    notes: "Schieferterrassen am Mittelmeer, lange Mazeration.",
                    foodPairings: ["Gegrilltes Fleisch", "Lamm", "Hartkäse"])
        Wine.create(in: context, cellar: cellar, name: "Riesling Kabinett", vintage: 2021,
                    grape: "Riesling", region: "Mosel", country: "Deutschland",
                    type: .white, quantity: 0)
        Wine.create(in: context, cellar: cellar, name: "Franciacorta Brut", vintage: 2019,
                    grape: "Chardonnay", region: "Lombardei", country: "Italien",
                    type: .sparkling, quantity: 3)
        Wine.create(in: context, cellar: cellar, name: "Whispering Angel", producer: "Château d'Esclans",
                    vintage: 2023, grape: "Grenache", region: "Provence", country: "Frankreich",
                    type: .rose, quantity: 6)
        context.saveChanges()
        return controller
    }()

    /// Leerer Speicher für den Empty State.
    static let emptyController = PersistenceController(inMemory: true, useCloudKit: false)

    static var context: NSManagedObjectContext { controller.viewContext }
    static var emptyContext: NSManagedObjectContext { emptyController.viewContext }

    /// Beispielweine in stabiler Reihenfolge.
    static var sampleWines: [Wine] {
        let request = Wine.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

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
                reasoning: "Die kräftigen Tannine und die Säure des Nebbiolo schneiden durch das Fett der Bolognese.",
                servingTip: "Eine Stunde dekantieren, bei 17 °C servieren."
            ),
            PairingRecommendation(
                rank: 2,
                wineName: "La Pinède",
                vintage: 2019,
                fit: .good,
                reasoning: "Warme Grenache-Frucht mit der Würze von Mourvèdre, etwas weniger Struktur.",
                servingTip: "Bei 16 °C servieren, 30 Minuten atmen lassen."
            )
        ],
        generalNote: "Ein Rotwein mit guter Säurestruktur ist die klassische Wahl zur Bolognese.",
        noGoodMatch: false,
        shoppingTip: "Klassisch: ein Chianti Classico oder ein Barbera d'Alba."
    )
}
