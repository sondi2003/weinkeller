import CoreData
import Foundation
import NaturalLanguage
import OSLog

/// Übersetzt Notizen, die vor der automatischen Übersetzung angelegt wurden.
///
/// Die Übersetzung beim Scannen kam später als der Keller. Wer seinen Bestand vorher
/// erfasst oder aus der früheren Ablage übernommen hat, trägt französische und
/// italienische Rückseitentexte im Klartext mit sich herum – und will sie nicht alle
/// erneut scannen.
///
/// **Ausschliesslich auf dem Gerät.** Ein Durchlauf über den ganzen Keller würde über die
/// Cloud je nach Bestand dutzende kostenpflichtige Anfragen auslösen; das darf ein
/// einzelner Knopfdruck nicht können. Notizen, für die das Sprachpaket fehlt, bleiben
/// unangetastet und werden gezählt.
@MainActor
enum NotesMigration {

    private static let logger = Logger(subsystem: "com.weinkeller.app", category: "Persistence")

    /// Eine Notiz, die übersetzt werden könnte.
    struct Candidate: Identifiable {
        let wine: Wine
        let language: NLLanguage
        var id: NSManagedObjectID { wine.objectID }
    }

    /// Was der Durchlauf bewirkt hat.
    struct Summary {
        var translated = 0
        /// Sprachpaket nicht installiert oder Übersetzung fehlgeschlagen.
        var notPossible = 0

        var isEmpty: Bool { translated == 0 && notPossible == 0 }
    }

    /// Alle Weine mit fremdsprachiger Notiz – Archiv und leere Einträge eingeschlossen.
    static func candidates(in context: NSManagedObjectContext) -> [Candidate] {
        let request = Wine.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        request.predicate = NSPredicate(format: "notes != %@", "")
        guard let wines = try? context.fetch(request) else { return [] }
        return wines.compactMap { wine in
            guard let language = LabelNotesTranslator.foreignLanguage(in: wine.notes) else { return nil }
            return Candidate(wine: wine, language: language)
        }
    }

    /// Übersetzt die übergebenen Notizen und speichert einmal am Schluss.
    static func translate(_ candidates: [Candidate], in context: NSManagedObjectContext) async -> Summary {
        var summary = Summary()
        for candidate in candidates {
            let original = candidate.wine.notes
            guard let translated = await LabelNotesTranslator.appleTranslation(
                of: original,
                from: candidate.language
            ) else {
                summary.notPossible += 1
                continue
            }
            candidate.wine.notes = translated
            summary.translated += 1
        }
        if summary.translated > 0 {
            context.saveChanges()
        }
        logger.info("Notiz-Übersetzung: \(summary.translated) übersetzt, \(summary.notPossible) nicht möglich.")
        return summary
    }
}
