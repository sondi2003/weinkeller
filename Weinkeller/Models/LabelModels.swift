import Foundation

// MARK: - Ergebnis der Etikett-Erkennung

/// Aus dem Etikett extrahierte Felder. Leere Strings bzw. 0 bedeuten „nicht erkannt“.
struct WineLabelExtraction: Codable, Sendable, Equatable {
    var name: String = ""
    var producer: String = ""
    var vintage: Int = 0
    var grape: String = ""
    var region: String = ""
    /// Rohwert: "red", "white", "sparkling", "rose" oder "unknown".
    var type: String = "unknown"
    var alcoholPercent: Double = 0
    var notes: String = ""

    /// Typ als App-Enum, falls erkannt.
    var wineType: WineType? {
        WineType(rawValue: type.lowercased())
    }

    /// `true`, wenn wenigstens ein Kernfeld gefüllt ist.
    var hasContent: Bool {
        !name.isEmpty || !producer.isEmpty || vintage > 0 || !grape.isEmpty || !region.isEmpty
    }
}

/// Womit die Zuordnung der Felder gemacht wurde – für die Anzeige in der UI.
enum LabelExtractionSource: Sendable, Equatable {
    case onDevice
    case cloud(AIProvider)
    case heuristic

    var displayName: String {
        switch self {
        case .onDevice:            return "Apple Intelligence (auf dem Gerät)"
        case .cloud(let provider): return provider.shortName
        case .heuristic:           return "einfache Erkennung ohne KI"
        }
    }
}

/// Erkanntes Etikett samt Rohtext und Quelle – wird ans Formular übergeben.
struct LabelScanResult: Sendable, Identifiable, Equatable {
    let id = UUID()
    let extraction: WineLabelExtraction
    let recognizedText: String
    let source: LabelExtractionSource
}

// MARK: - JSON-Schema für die Cloud-Zuordnung

/// Schema, auf das OpenAI/Gemini/Anthropic bei der Etikett-Zuordnung festgelegt werden.
/// Alle Felder sind Pflicht (strict-kompatibel); „unbekannt“ = leerer String bzw. 0.
enum LabelSchema {

    static func jsonSchema(includeAdditionalProperties: Bool) -> [String: Any] {
        var schema: [String: Any] = [
            "type": "object",
            "properties": [
                "name": ["type": "string", "description": "Name des Weins oder der Cuvée ohne Produzent, z. B. \"La Pinède\". Leer, wenn unbekannt."],
                "producer": ["type": "string", "description": "Produzent, Weingut, Domaine oder Château. Leer, wenn unbekannt."],
                "vintage": ["type": "integer", "description": "Jahrgang als vierstellige Zahl, 0 wenn nicht auf dem Etikett."],
                "grape": ["type": "string", "description": "Rebsorten, kommagetrennt, in Originalschreibweise. Leer, wenn unbekannt."],
                "region": ["type": "string", "description": "Region oder Appellation, z. B. \"Collioure\". Leer, wenn unbekannt."],
                "type": ["type": "string", "enum": ["red", "white", "sparkling", "rose", "unknown"], "description": "Weintyp."],
                "alcoholPercent": ["type": "number", "description": "Alkoholgehalt in Volumenprozent, 0 wenn unbekannt."],
                "notes": ["type": "string", "description": "Kurze deutsche Notiz zu Terroir, Vinifikation und Ausbau (max. 2 Sätze). Leer, wenn nichts dazu auf dem Etikett steht."]
            ],
            "required": ["name", "producer", "vintage", "grape", "region", "type", "alcoholPercent", "notes"]
        ]
        if includeAdditionalProperties {
            schema["additionalProperties"] = false
        }
        return schema
    }
}
