import CoreData
import Foundation
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
    var country: String
    var type: WineType
    var quantity: Int
    var notes: String
    /// Kommagetrennt im Formular, als Liste am Wein.
    var foodPairings: String
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
            country = ""
            type = .red
            quantity = 1
            notes = ""
            foodPairings = ""
            labelImageData = nil
        case .edit(let wine):
            name = wine.name
            producer = wine.producer
            vintage = Int(wine.vintage)
            grape = wine.grape
            region = wine.region
            country = wine.country
            type = wine.type
            quantity = Int(wine.quantity)
            notes = wine.notes
            foodPairings = wine.foodPairings.joined(separator: ", ")
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
        if !extraction.country.isEmpty { country = extraction.country }
        if let wineType = extraction.wineType { type = wineType }
        if let imageData = scan.labelImageData { labelImageData = imageData }
        if !extraction.foodPairings.isEmpty {
            foodPairings = extraction.foodPairings.joined(separator: ", ")
        }

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

    /// Kommaliste in einzelne Begriffe zerlegen.
    private var pairingList: [String] {
        foodPairings
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Schreibt das Formular in den Context (neu anlegen oder aktualisieren).
    func save(in context: NSManagedObjectContext) {
        let trimmed = { (value: String) in value.trimmingCharacters(in: .whitespacesAndNewlines) }
        switch mode {
        case .add:
            Wine.create(
                in: context,
                cellar: Cellar.findOrCreateDefault(in: context),
                name: trimmedName,
                producer: trimmed(producer),
                vintage: vintage,
                grape: trimmed(grape),
                region: trimmed(region),
                country: trimmed(country),
                type: type,
                quantity: quantity,
                notes: trimmed(notes),
                foodPairings: pairingList,
                labelImageData: labelImageData
            )
        case .edit(let wine):
            wine.name = trimmedName
            wine.producer = trimmed(producer)
            wine.vintage = Int64(vintage)
            wine.grape = trimmed(grape)
            wine.region = trimmed(region)
            wine.country = trimmed(country)
            wine.type = type
            wine.quantity = Int64(max(0, quantity))
            wine.notes = trimmed(notes)
            wine.foodPairings = pairingList
            wine.labelImageData = labelImageData
        }
        context.saveChanges()
    }
}
