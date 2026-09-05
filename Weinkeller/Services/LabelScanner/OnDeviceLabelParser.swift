import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Zuordnung des Etikett-Texts mit Apple Intelligence – vollständig auf dem Gerät.
/// Verfügbar ab iOS 26 auf Geräten mit Apple Intelligence (iPhone 15 Pro und neuer),
/// sofern Apple Intelligence in den Systemeinstellungen aktiviert ist.
@available(iOS 26.0, *)
enum OnDeviceLabelParser {

    /// `true`, wenn das Sprachmodell auf diesem Gerät gerade einsatzbereit ist.
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static func parse(recognizedText: String) async throws -> WineLabelExtraction {
        let session = LanguageModelSession(instructions: PromptBuilder.labelSystemPrompt)
        let response = try await session.respond(
            to: PromptBuilder.labelUserPrompt(recognizedText: recognizedText),
            generating: GeneratedWineLabel.self
        )
        let label = response.content
        return WineLabelExtraction(
            name: label.name,
            producer: label.producer,
            vintage: label.vintage,
            grape: label.grape,
            region: label.region,
            type: label.type,
            alcoholPercent: label.alcoholPercent,
            notes: label.notes
        )
    }
}

/// Zielstruktur für das Foundation-Models-Framework. Spiegel von `WineLabelExtraction`.
@available(iOS 26.0, *)
@Generable
struct GeneratedWineLabel {
    @Guide(description: "Name des Weins oder der Cuvée ohne Produzent, leer wenn unbekannt")
    var name: String

    @Guide(description: "Produzent, Weingut, Domaine oder Château, leer wenn unbekannt")
    var producer: String

    @Guide(description: "Jahrgang als vierstellige Zahl, 0 wenn unbekannt")
    var vintage: Int

    @Guide(description: "Rebsorten kommagetrennt in Originalschreibweise, leer wenn unbekannt")
    var grape: String

    @Guide(description: "Region oder Appellation, leer wenn unbekannt")
    var region: String

    @Guide(description: "Weintyp: genau einer von red, white, sparkling, rose, unknown")
    var type: String

    @Guide(description: "Alkoholgehalt in Volumenprozent, 0 wenn unbekannt")
    var alcoholPercent: Double

    @Guide(description: "Ein bis zwei deutsche Sätze zu Terroir, Vinifikation und Ausbau, leer wenn nichts dazu steht")
    var notes: String
}
#endif
