import Foundation

/// Das Profil eines Weins bei WineAPI – nur die Felder, die die App zeigt.
///
/// Wird als JSON am Wein gespeichert (`wineAPIProfileJSON`), damit das Nachschlagen
/// einmalig ist und die Karte offline funktioniert. Codable in beide Richtungen: aus
/// der API-Antwort heraus und in unseren eigenen Speicher hinein.
struct WineAPIProfile: Codable, Equatable, Sendable {

    struct Named: Codable, Equatable, Sendable {
        var name: String
        var country: String?
    }

    struct PriceRange: Codable, Equatable, Sendable {
        var min: Double
        var max: Double
        var currency: String
    }

    struct Score: Codable, Equatable, Sendable {
        var score: Double?
        var scoreText: String?
        var reviewer: String
        var reviewDate: Date?
    }

    struct Pairing: Codable, Equatable, Sendable {
        var food: String
        var confidence: Double?
        var notes: String?

        /// Die Sicherheit kommt je nach Endpunkt als Zahl oder als Text („high“).
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            food = try container.decode(String.self, forKey: .food)
            notes = try container.decodeIfPresent(String.self, forKey: .notes)
            if let number = try? container.decodeIfPresent(Double.self, forKey: .confidence) {
                confidence = number
            } else if let text = try? container.decodeIfPresent(String.self, forKey: .confidence) {
                switch text.lowercased() {
                case "high": confidence = 0.9
                case "medium": confidence = 0.6
                case "low": confidence = 0.3
                default: confidence = Double(text)
                }
            } else {
                confidence = nil
            }
        }

        init(food: String, confidence: Double?, notes: String?) {
            self.food = food
            self.confidence = confidence
            self.notes = notes
        }
    }

    var id: String?
    var name: String
    var vintage: Int?
    var type: String?
    var body: String?
    var acidity: String?
    var classification: String?
    var averageRating: Double?
    var ratingsCount: Int?
    var winery: Named?
    var region: Named?
    var appellation: String?
    var grapes: [Named]?
    var alcoholContent: Double?
    var description: String?
    var priceRange: PriceRange?
    var scores: [Score]?
    var pairings: [Pairing]?

    // Von uns ergänzt, nicht aus der API.
    /// Wie sicher die Zuordnung zu unserem Wein war (0…1).
    var matchConfidence: Double?
    /// `true`, wenn WineAPI den Wein beim Abruf noch ergänzte – dann lohnt „Aktualisieren“.
    var isPending: Bool?
    /// Deutsche Fassung der Beschreibung, falls übersetzt.
    var descriptionGerman: String?
    /// Deutsche Fassung der Speiseempfehlungen, gleiche Reihenfolge wie `pairings`.
    var pairingsGerman: [String]?

    /// Die Sterne, wie sie die App zeigt: Durchschnitt auf 5.
    var hasRating: Bool { (averageRating ?? 0) > 0 }

    /// Beschreibung, bevorzugt auf Deutsch.
    var displayDescription: String? {
        let german = descriptionGerman?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !german.isEmpty { return german }
        let original = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return original.isEmpty ? nil : original
    }

    /// Speiseempfehlungen, bevorzugt auf Deutsch.
    var displayPairings: [String] {
        guard let pairings else { return [] }
        if let german = pairingsGerman, german.count == pairings.count {
            return german
        }
        return pairings.map(\.food)
    }

    /// Kritikerwertungen mit Zahl oder Text – leere Einträge fallen weg.
    var usableScores: [Score] {
        (scores ?? []).filter { $0.score != nil || !($0.scoreText ?? "").isEmpty }
    }

    var priceText: String? {
        guard let range = priceRange, range.max > 0 else { return nil }
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 0
        let low = formatter.string(from: NSNumber(value: range.min)) ?? "\(Int(range.min))"
        let high = formatter.string(from: NSNumber(value: range.max)) ?? "\(Int(range.max))"
        return range.min == range.max ? "\(low) \(range.currency)" : "\(low)–\(high) \(range.currency)"
    }

    // MARK: Speichern

    func encodedJSON() -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    static func decoded(from json: String) -> WineAPIProfile? {
        guard let data = json.data(using: .utf8), !data.isEmpty else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WineAPIProfile.self, from: data)
    }
}
