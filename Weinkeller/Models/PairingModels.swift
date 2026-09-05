import Foundation

// MARK: - Anfrage

/// Alles, was der Wein-Berater für eine Empfehlung braucht.
struct PairingRequest: Sendable {
    /// Stichwörter zum Essen, z. B. "Raclette" oder "Spaghetti Bolognese".
    let dish: String

    /// Nur nicht-archivierte Weine mit Bestand > 0 gehören hier hinein.
    let inventory: [WineInventoryItem]

    /// Wie viele Vorschläge maximal (Standard: Top 3).
    let maxRecommendations: Int

    init(dish: String, inventory: [WineInventoryItem], maxRecommendations: Int = 3) {
        self.dish = dish.trimmingCharacters(in: .whitespacesAndNewlines)
        self.inventory = inventory
        self.maxRecommendations = maxRecommendations
    }
}

// MARK: - Antwort (strukturiert, von allen drei Anbietern identisch geliefert)

/// Die strukturierte Antwort der KI. Alle drei Provider werden über ein
/// JSON-Schema (siehe `RecommendationSchema`) auf genau dieses Format festgenagelt.
struct PairingResponse: Codable, Sendable, Equatable {
    /// Sortiert nach `rank`, bestes Pairing zuerst.
    var recommendations: [PairingRecommendation]

    /// Allgemeiner Hinweis, z. B. "Zu Raclette passt eigentlich ein Fendant –
    /// davon ist keiner im Keller, daher die zweitbeste Wahl."
    var generalNote: String

    /// Convenience: Empfehlungen garantiert nach Rang sortiert.
    var sortedRecommendations: [PairingRecommendation] {
        recommendations.sorted { $0.rank < $1.rank }
    }
}

struct PairingRecommendation: Codable, Sendable, Equatable, Identifiable {
    /// 1 = beste Wahl.
    var rank: Int

    /// Muss exakt dem `name` eines Weins aus dem Inventar entsprechen.
    var wineName: String

    /// Jahrgang des empfohlenen Weins (zur eindeutigen Zuordnung bei Namensdubletten).
    var vintage: Int

    /// Warum dieser Wein zu dem Gericht passt (2–4 Sätze).
    var reasoning: String

    /// Serviertipp: Temperatur, Dekantieren, Glas …
    var servingTip: String

    var id: String { "\(rank)-\(wineName)-\(vintage)" }
}

// MARK: - JSON-Schema für Structured Output

/// Das JSON-Schema, mit dem alle drei Anbieter auf `PairingResponse` festgelegt werden.
///
/// OpenAI (strict) und Anthropic verlangen `additionalProperties: false` auf jedem Objekt,
/// Gemini lehnt diesen Schlüssel dagegen ab. Deshalb ist das Schema parametrisiert.
enum RecommendationSchema {

    static func jsonSchema(includeAdditionalProperties: Bool) -> [String: Any] {
        var recommendation: [String: Any] = [
            "type": "object",
            "properties": [
                "rank": [
                    "type": "integer",
                    "description": "1 = beste Empfehlung, 2 = zweitbeste, usw."
                ],
                "wineName": [
                    "type": "string",
                    "description": "Exakter Name des Weins aus dem Inventar."
                ],
                "vintage": [
                    "type": "integer",
                    "description": "Jahrgang des Weins aus dem Inventar."
                ],
                "reasoning": [
                    "type": "string",
                    "description": "Begründung auf Deutsch, warum der Wein zum Gericht passt."
                ],
                "servingTip": [
                    "type": "string",
                    "description": "Kurzer Serviertipp auf Deutsch (Temperatur, Dekantieren, Glas)."
                ]
            ],
            "required": ["rank", "wineName", "vintage", "reasoning", "servingTip"]
        ]

        var root: [String: Any] = [
            "type": "object",
            "properties": [
                "recommendations": [
                    "type": "array",
                    "description": "Bis zu drei Empfehlungen, nach Rang sortiert.",
                    "items": recommendation
                ],
                "generalNote": [
                    "type": "string",
                    "description": "Allgemeiner Hinweis auf Deutsch zur Auswahl oder zu fehlenden Alternativen."
                ]
            ],
            "required": ["recommendations", "generalNote"]
        ]

        if includeAdditionalProperties {
            recommendation["additionalProperties"] = false
            root["additionalProperties"] = false
            // `items` wurde bereits kopiert – neu setzen, damit die Änderung ankommt.
            if var props = root["properties"] as? [String: Any],
               var recs = props["recommendations"] as? [String: Any] {
                recs["items"] = recommendation
                props["recommendations"] = recs
                root["properties"] = props
            }
        }

        return root
    }
}
