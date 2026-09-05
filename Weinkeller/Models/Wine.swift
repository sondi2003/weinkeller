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
    /// Name des Weins bzw. des Weinguts, z. B. "Château Margaux".
    var name: String

    /// Jahrgang, z. B. 2018.
    var vintage: Int

    /// Rebsorte und/oder Region, z. B. "Cabernet Sauvignon, Bordeaux".
    var grapeOrRegion: String

    /// Rot, Weiß, Schaum oder Rosé.
    var type: WineType

    /// Anzahl der Flaschen, die aktuell im Keller liegen.
    var quantity: Int

    /// Archivierte Weine bleiben als Historie erhalten, tauchen aber weder
    /// in der Kellerliste noch in KI-Empfehlungen auf.
    var isArchived: Bool

    /// Freitext, z. B. "Geschenk von Anna" oder "bis 2030 trinken".
    var notes: String

    var createdAt: Date

    init(
        name: String,
        vintage: Int,
        grapeOrRegion: String,
        type: WineType,
        quantity: Int = 1,
        notes: String = "",
        isArchived: Bool = false,
        createdAt: Date = .now
    ) {
        self.name = name
        self.vintage = vintage
        self.grapeOrRegion = grapeOrRegion
        self.type = type
        self.quantity = max(0, quantity)
        self.notes = notes
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

    /// Kurzform für Listen: "2018 · Cabernet Sauvignon, Bordeaux".
    var subtitle: String {
        "\(vintage) · \(grapeOrRegion)"
    }

    /// Schlanke, `Codable`-Kopie für die Übergabe an den KI-Service.
    /// SwiftData-Objekte selbst sind nicht `Sendable` und gehören nicht ins Netzwerk-Layer.
    var inventoryItem: WineInventoryItem {
        WineInventoryItem(
            name: name,
            vintage: vintage,
            grapeOrRegion: grapeOrRegion,
            type: type.displayName,
            quantity: quantity
        )
    }
}

// MARK: - DTO für den KI-Service

/// Das, was die KI über eine Flasche wissen muss. Wird als JSON in den Prompt eingebettet.
struct WineInventoryItem: Codable, Hashable, Sendable {
    let name: String
    let vintage: Int
    let grapeOrRegion: String
    /// Anzeigename des Typs ("Rotwein" usw.), damit der Prompt ohne Mapping lesbar bleibt.
    let type: String
    let quantity: Int
}
