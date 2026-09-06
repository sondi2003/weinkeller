import Foundation
import SwiftData

// MARK: - Weintyp

/// Die vier Grundtypen, nach denen der Keller sortiert und gefiltert wird.
/// `rawValue` ist stabil (englisch), damit sich Anzeige-Texte später ändern lassen,
/// ohne bestehende SwiftData-Datensätze zu brechen.
enum WineType: String, Codable, CaseIterable, Identifiable, Sendable {
    case red = "red"
    case white = "white"
    case sparkling = "sparkling"
    case rose = "rose"

    var id: String { rawValue }

    /// Deutscher Anzeigename für die UI und für den Prompt an die KI.
    var displayName: String {
        switch self {
        case .red:       return "Rotwein"
        case .white:     return "Weißwein"
        case .sparkling: return "Schaumwein"
        case .rose:      return "Rosé"
        }
    }

    /// SF Symbol für Listen und Picker.
    var symbolName: String {
        switch self {
        case .red:       return "wineglass.fill"
        case .white:     return "wineglass"
        case .sparkling: return "bubbles.and.sparkles"
        case .rose:      return "drop.fill"
        }
    }
}

// MARK: - SwiftData-Modell

/// Eine Position im Weinkeller: ein bestimmter Wein mit Jahrgang und aktuellem Bestand.
@Model
final class Wine {
    /// Name des Weins bzw. der Cuvée, z. B. "La Pinède".
    var name: String

    /// Produzent, Weingut oder Domaine, z. B. "Domaine La Tour Vieille".
    var producer: String = ""

    /// Jahrgang, z. B. 2019.
    var vintage: Int

    /// Rebsorte(n), z. B. "Grenache noir, Mourvèdre, Carignan".
    /// Hieß früher `grapeOrRegion`; SwiftData migriert bestehende Daten automatisch.
    @Attribute(originalName: "grapeOrRegion")
    var grape: String

    /// Region oder Appellation, z. B. "Collioure".
    var region: String = ""

    /// Herkunftsland, z. B. "Frankreich". Macht die Kartensuche eindeutig
    /// („Mosel“ allein landet sonst in Frankreich statt in Deutschland).
    var country: String = ""

    /// Rot, Weiß, Schaum oder Rosé.
    var type: WineType

    /// Anzahl der Flaschen, die aktuell im Keller liegen.
    var quantity: Int

    /// Archivierte Weine bleiben als Historie erhalten, tauchen aber weder
    /// in der Kellerliste noch in KI-Empfehlungen auf.
    var isArchived: Bool

    /// Freitext, z. B. Terroir, Vinifikation, "Geschenk von Anna", "bis 2030 trinken".
    var notes: String

    /// Speiseempfehlungen, die auf dem Etikett stehen – auf Deutsch, z. B.
    /// ["Gegrilltes Fleisch", "Hartkäse"]. Leer, wenn das Etikett nichts dazu sagt.
    var foodPairings: [String] = []

    /// Zugeschnittenes Foto des Vorderseiten-Etiketts als JPEG. Liegt dank
    /// `externalStorage` als Datei neben der Datenbank, nicht in ihr.
    @Attribute(.externalStorage)
    var labelImageData: Data? = nil

    // MARK: Herkunft auf der Karte

    /// Koordinaten der Region, einmalig per Geocoding ermittelt.
    var latitude: Double? = nil
    var longitude: Double? = nil

    /// Welche Region zuletzt nachgeschlagen wurde – erkennt spätere Änderungen.
    var geocodedQuery: String? = nil

    /// Aufgelöster Ortsname mit Land, z. B. „Collioure, Frankreich“.
    var geocodedPlaceName: String? = nil

    /// „place“ = Region gefunden (Stecknadel), „country“ = nur das Land gesichert.
    var geocodePrecision: String? = nil

    var createdAt: Date

    init(
        name: String,
        producer: String = "",
        vintage: Int,
        grape: String,
        region: String = "",
        country: String = "",
        type: WineType,
        quantity: Int = 1,
        notes: String = "",
        foodPairings: [String] = [],
        labelImageData: Data? = nil,
        isArchived: Bool = false,
        createdAt: Date = .now
    ) {
        self.name = name
        self.producer = producer
        self.vintage = vintage
        self.grape = grape
        self.region = region
        self.country = country
        self.type = type
        self.quantity = max(0, quantity)
        self.notes = notes
        self.foodPairings = foodPairings
        self.labelImageData = labelImageData
        self.isArchived = isArchived
        self.createdAt = createdAt
    }

    // MARK: Bestands-Management

    /// `true`, sobald keine Flasche mehr übrig ist.
    var isOutOfStock: Bool { quantity <= 0 }

    /// Eine Flasche abbuchen (Minus-Button). Fällt nie unter 0.
    func consumeBottle() {
        guard quantity > 0 else { return }
        quantity -= 1
    }

    /// Eine Flasche hinzubuchen (Plus-Button).
    func addBottle() {
        quantity += 1
    }

    /// Kurzform für Listen: "2019 · Grenache, Mourvèdre · Collioure".
    var subtitle: String {
        ([String(vintage), grape, region.isEmpty ? country : region])
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// Anzeigename inklusive Produzent, falls vorhanden.
    var fullName: String {
        producer.isEmpty ? name : "\(producer) – \(name)"
    }

    /// `true`, wenn zur aktuellen Region schon ein Nachschlagen stattgefunden hat.
    /// Ein fehlender `geocodePrecision` bedeutet: noch nie oder mit älterer Logik gesucht.
    var needsGeocoding: Bool {
        geocodePrecision == nil || geocodedQuery != RegionGeocoder.query(region: region, country: country)
    }

    /// Übernimmt ein Geocoding-Ergebnis (oder merkt sich den erfolglosen Versuch).
    func applyGeocode(_ result: GeocodedRegion?, for query: String) {
        geocodedQuery = query
        latitude = result?.latitude
        longitude = result?.longitude
        geocodedPlaceName = result?.placeName
        // „none“ merkt sich den erfolglosen Versuch, damit nicht bei jedem Öffnen neu gesucht wird.
        geocodePrecision = result?.precision.rawValue ?? "none"
    }

    /// `true`, wenn die Region selbst gefunden wurde und eine Stecknadel gerechtfertigt ist.
    var hasPreciseOrigin: Bool {
        geocodePrecision == GeocodedRegion.Precision.place.rawValue
    }

    /// Schlanke, `Codable`-Kopie für die Übergabe an den KI-Service.
    /// SwiftData-Objekte selbst sind nicht `Sendable` und gehören nicht ins Netzwerk-Layer.
    var inventoryItem: WineInventoryItem {
        WineInventoryItem(
            name: name,
            producer: producer,
            vintage: vintage,
            grape: grape,
            region: ([region, country].filter { !$0.isEmpty }).joined(separator: ", "),
            type: type.displayName,
            notes: String(notes.prefix(300)),
            labelPairings: foodPairings,
            quantity: quantity
        )
    }
}

// MARK: - DTO für den KI-Service

/// Das, was die KI über eine Flasche wissen muss. Wird als JSON in den Prompt eingebettet.
struct WineInventoryItem: Codable, Hashable, Sendable {
    let name: String
    let producer: String
    let vintage: Int
    let grape: String
    let region: String
    /// Anzeigename des Typs ("Rotwein" usw.), damit der Prompt ohne Mapping lesbar bleibt.
    let type: String
    /// Terroir, Vinifikation, eigene Notizen – hilft der KI beim Pairing.
    let notes: String
    /// Speiseempfehlungen laut Etikett.
    let labelPairings: [String]
    let quantity: Int
}
