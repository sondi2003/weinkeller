import Foundation
import SwiftData
import Observation

/// Formularzustand für „Wein hinzufügen“ und „Wein bearbeiten“.
@Observable
@MainActor
final class WineFormViewModel {

    enum Mode {
        case add
        case edit(Wine)

        var title: String {
            switch self {
            case .add:  return "Wein hinzufügen"
            case .edit: return "Wein bearbeiten"
            }
        }
    }

    let mode: Mode

    var name: String
    var producer: String
    var vintage: Int
    var grape: String
    var region: String
    var type: WineType
    var quantity: Int
    var notes: String

    /// Zugeschnittenes Etikett-Foto (JPEG), wird mit dem Wein gespeichert.
    var labelImageData: Data?

    /// Quelle der letzten Etikett-Erkennung – für den Hinweis im Formular.
    var lastScanSource: LabelExtractionSource?

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .add:
            name = ""
            producer = ""
            vintage = Calendar.current.component(.year, from: .now) - 2
            grape = ""
            region = ""
            type = .red
            quantity = 1
            notes = ""
            labelImageData = nil
        case .edit(let wine):
            name = wine.name
            producer = wine.producer
            vintage = wine.vintage
            grape = wine.grape
            region = wine.region
            type = wine.type
            quantity = wine.quantity
            notes = wine.notes
            labelImageData = wine.labelImageData
        }
    }

    /// Sinnvolle Jahrgangsspanne für den Picker.
    static var vintageRange: ClosedRange<Int> {
        let current = Calendar.current.component(.year, from: .now)
        return 1950...current
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var canSave: Bool {
        !trimmedName.isEmpty && quantity >= 0
    }

    /// Übernimmt erkannte Etikett-Felder. Leere Werte überschreiben nichts.
    func apply(_ scan: LabelScanResult) {
        let extraction = scan.extraction
        if !extraction.name.isEmpty { name = extraction.name }
        if !extraction.producer.isEmpty { producer = extraction.producer }
        if Self.vintageRange.contains(extraction.vintage) { vintage = extraction.vintage }
        if !extraction.grape.isEmpty { grape = extraction.grape }
        if !extraction.region.isEmpty { region = extraction.region }
        if let wineType = extraction.wineType { type = wineType }
        if let imageData = scan.labelImageData { labelImageData = imageData }

        var extraNotes: [String] = []
        if !extraction.notes.isEmpty { extraNotes.append(extraction.notes) }
        if extraction.alcoholPercent > 0 {
            extraNotes.append("Alkohol: \(extraction.alcoholPercent.formatted(.number.precision(.fractionLength(0...1)))) % vol.")
        }
        if !extraNotes.isEmpty {
            let existing = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            notes = ([existing] + extraNotes).filter { !$0.isEmpty }.joined(separator: "\n")
        }
        lastScanSource = scan.source
    }

    /// Schreibt das Formular in den Context (neu anlegen oder aktualisieren).
    func save(in context: ModelContext) {
        let trimmed = { (value: String) in value.trimmingCharacters(in: .whitespacesAndNewlines) }
        switch mode {
        case .add:
            let wine = Wine(
                name: trimmedName,
                producer: trimmed(producer),
                vintage: vintage,
                grape: trimmed(grape),
                region: trimmed(region),
                type: type,
                quantity: quantity,
                notes: trimmed(notes),
                labelImageData: labelImageData
            )
            context.insert(wine)
        case .edit(let wine):
            wine.name = trimmedName
            wine.producer = trimmed(producer)
            wine.vintage = vintage
            wine.grape = trimmed(grape)
            wine.region = trimmed(region)
            wine.type = type
            wine.quantity = max(0, quantity)
            wine.notes = trimmed(notes)
            wine.labelImageData = labelImageData
        }
    }
}
