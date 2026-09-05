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
    var vintage: Int
    var grapeOrRegion: String
    var type: WineType
    var quantity: Int
    var notes: String

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .add:
            name = ""
            vintage = Calendar.current.component(.year, from: .now) - 2
            grapeOrRegion = ""
            type = .red
            quantity = 1
            notes = ""
        case .edit(let wine):
            name = wine.name
            vintage = wine.vintage
            grapeOrRegion = wine.grapeOrRegion
            type = wine.type
            quantity = wine.quantity
            notes = wine.notes
        }
    }

    /// Sinnvolle Jahrgangsspanne für den Picker.
    static var vintageRange: ClosedRange<Int> {
        let current = Calendar.current.component(.year, from: .now)
        return 1950...current
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedGrapeOrRegion: String { grapeOrRegion.trimmingCharacters(in: .whitespacesAndNewlines) }

    var canSave: Bool {
        !trimmedName.isEmpty && quantity >= 0
    }

    /// Schreibt das Formular in den Context (neu anlegen oder aktualisieren).
    func save(in context: ModelContext) {
        switch mode {
        case .add:
            let wine = Wine(
                name: trimmedName,
                vintage: vintage,
                grapeOrRegion: trimmedGrapeOrRegion,
                type: type,
                quantity: quantity,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            context.insert(wine)
        case .edit(let wine):
            wine.name = trimmedName
            wine.vintage = vintage
            wine.grapeOrRegion = trimmedGrapeOrRegion
            wine.type = type
            wine.quantity = max(0, quantity)
            wine.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
