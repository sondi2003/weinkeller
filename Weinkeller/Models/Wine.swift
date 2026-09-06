import CoreData
import CoreLocation
import Foundation

// MARK: - Weintyp

/// Die vier Grundtypen, nach denen der Keller sortiert und gefiltert wird.
/// `rawValue` ist stabil (englisch), damit sich Anzeige-Texte später ändern lassen,
/// ohne bestehende Datensätze zu brechen.
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

// MARK: - Core-Data-Modell

/// Eine Position im Weinkeller: ein bestimmter Wein mit Jahrgang und aktuellem Bestand.
// Laufzeitname bewusst abweichend: „Wine“ ist zugleich der Entitätsname der früheren
// SwiftData-Ablage. Ohne eigenen Namen greift die Übernahme auf die falsche Klasse zu
// und das Öffnen des alten Speichers schlägt fehl.
@objc(WineEntity)
final class Wine: NSManagedObject, Identifiable {

    @nonobjc class func fetchRequest() -> NSFetchRequest<Wine> {
        NSFetchRequest<Wine>(entityName: "Wine")
    }

    // MARK: Gespeicherte Werte

    @NSManaged var uuid: UUID?
    /// Stabile Identität für Listen; `objectID` gilt auch für noch nicht gespeicherte Objekte.
    var id: NSManagedObjectID { objectID }
    /// Name des Weins bzw. der Cuvée, z. B. "La Pinède".
    @NSManaged var name: String
    /// Produzent, Weingut oder Domaine, z. B. "Domaine La Tour Vieille".
    @NSManaged var producer: String
    @NSManaged var vintage: Int64
    /// Rebsorte(n), z. B. "Grenache noir, Mourvèdre, Carignan".
    @NSManaged var grape: String
    /// Region oder Appellation, z. B. "Collioure".
    @NSManaged var region: String
    /// Herkunftsland, macht die Kartensuche eindeutig.
    @NSManaged var country: String
    @NSManaged var quantity: Int64
    @NSManaged var isArchived: Bool
    /// Freitext, z. B. Terroir, Vinifikation, "bis 2030 trinken".
    @NSManaged var notes: String
    /// Zugeschnittenes Foto des Vorderseiten-Etiketts als JPEG.
    @NSManaged var labelImageData: Data?
    @NSManaged var createdAt: Date?
    @NSManaged var cellar: Cellar?

    /// Rohwerte, die über berechnete Eigenschaften bequemer nutzbar sind.
    @NSManaged private var typeRaw: String
    @NSManaged private var foodPairingsRaw: String
    @NSManaged private var latitude: Double
    @NSManaged private var longitude: Double
    @NSManaged var geocodedQuery: String
    @NSManaged var geocodedPlaceName: String
    /// „place“ = Region gefunden, „country“ = nur das Land, „none“ = erfolglos gesucht,
    /// leer = noch nie gesucht.
    @NSManaged var geocodePrecision: String

    // MARK: Anlegen

    /// Legt eine Flasche an und hängt sie an den Keller.
    @discardableResult
    static func create(
        in context: NSManagedObjectContext,
        cellar: Cellar,
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
    ) -> Wine {
        let wine = Wine(context: context)
        wine.uuid = UUID()
        wine.cellar = cellar
        wine.name = name
        wine.producer = producer
        wine.vintage = Int64(vintage)
        wine.grape = grape
        wine.region = region
        wine.country = country
        wine.type = type
        wine.quantity = Int64(max(0, quantity))
        wine.notes = notes
        wine.foodPairings = foodPairings
        wine.labelImageData = labelImageData
        wine.isArchived = isArchived
        wine.createdAt = createdAt
        wine.geocodedQuery = ""
        wine.geocodedPlaceName = ""
        wine.geocodePrecision = ""
        return wine
    }

    // MARK: Bequeme Zugriffe

    var type: WineType {
        get { WineType(rawValue: typeRaw) ?? .red }
        set { typeRaw = newValue.rawValue }
    }

    /// Speiseempfehlungen laut Etikett, intern als eine Zeile pro Eintrag gespeichert.
    var foodPairings: [String] {
        get {
            foodPairingsRaw
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        set { foodPairingsRaw = newValue.joined(separator: "\n") }
    }

    /// Jahrgang als `Int`, weil Core Data mit `Int64` arbeitet.
    var vintageValue: Int {
        get { Int(vintage) }
        set { vintage = Int64(newValue) }
    }

    var quantityValue: Int {
        get { Int(quantity) }
        set { quantity = Int64(max(0, newValue)) }
    }

    // MARK: Bestands-Management

    /// `true`, sobald keine Flasche mehr übrig ist.
    var isOutOfStock: Bool { quantity <= 0 }

    /// Eine Flasche abbuchen (Minus-Button). Fällt nie unter 0.
    func consumeBottle() {
        guard quantity > 0 else { return }
        quantity -= 1
        managedObjectContext?.saveChanges()
    }

    /// Eine Flasche hinzubuchen (Plus-Button).
    func addBottle() {
        quantity += 1
        managedObjectContext?.saveChanges()
    }

    // MARK: Darstellung

    /// Kurzform für Listen: "2019 · Grenache · Collioure".
    var subtitle: String {
        [String(vintage), grape, region.isEmpty ? country : region]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// Anzeigename inklusive Produzent, falls vorhanden.
    var fullName: String {
        producer.isEmpty ? name : "\(producer) – \(name)"
    }

    // MARK: Herkunft

    /// Koordinate der Herkunft, sofern eine ermittelt wurde.
    var coordinate: CLLocationCoordinate2D? {
        guard geocodePrecision == GeocodedRegion.Precision.place.rawValue
                || geocodePrecision == GeocodedRegion.Precision.country.rawValue else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// `true`, wenn die Region selbst gefunden wurde und eine Stecknadel gerechtfertigt ist.
    var hasPreciseOrigin: Bool {
        geocodePrecision == GeocodedRegion.Precision.place.rawValue
    }

    /// `true`, wenn zur aktuellen Region noch kein Nachschlagen stattgefunden hat.
    var needsGeocoding: Bool {
        geocodePrecision.isEmpty
            || geocodedQuery != (RegionGeocoder.query(region: region, country: country) ?? "")
    }

    /// Übernimmt ein Geocoding-Ergebnis (oder merkt sich den erfolglosen Versuch).
    func applyGeocode(_ result: GeocodedRegion?, for query: String) {
        geocodedQuery = query
        latitude = result?.latitude ?? 0
        longitude = result?.longitude ?? 0
        geocodedPlaceName = result?.placeName ?? ""
        // „none“ merkt sich den erfolglosen Versuch, damit nicht bei jedem Öffnen neu gesucht wird.
        geocodePrecision = result?.precision.rawValue ?? "none"
        managedObjectContext?.saveChanges()
    }

    // MARK: Übergabe an den KI-Service

    /// Schlanke, `Codable`-Kopie für den KI-Service. Managed Objects gehören nicht ins Netzwerk-Layer.
    var inventoryItem: WineInventoryItem {
        WineInventoryItem(
            name: name,
            producer: producer,
            vintage: Int(vintage),
            grape: grape,
            region: [region, country].filter { !$0.isEmpty }.joined(separator: ", "),
            type: type.displayName,
            notes: String(notes.prefix(300)),
            labelPairings: foodPairings,
            quantity: Int(quantity)
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
