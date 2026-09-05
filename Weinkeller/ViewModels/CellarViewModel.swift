import Foundation
import SwiftData
import Observation

/// UI-Zustand und Aktionen für den Tab „Weinkeller“.
///
/// Die Weine selbst kommen per `@Query` in die View (so ist SwiftData gedacht);
/// dieses ViewModel kümmert sich um Filter, Suche, Sheets und die Bestandsaktionen.
@Observable
@MainActor
final class CellarViewModel {

    // MARK: Filter & Suche

    /// `nil` = alle Typen.
    var typeFilter: WineType?
    var searchText = ""
    var showArchived = false

    // MARK: Sheet- und Dialog-Zustand

    var isShowingAddSheet = false
    var wineToEdit: Wine?

    /// Wird gesetzt, wenn durch „Flasche trinken“ die letzte Flasche abgebucht wurde.
    var justEmptiedWine: Wine?

    /// Trigger für haptisches Feedback beim Abbuchen.
    var consumeCount = 0

    // MARK: Abgeleitete Daten

    /// Wendet Archiv-, Typ- und Suchfilter auf die Query-Ergebnisse an.
    func filtered(_ wines: [Wine]) -> [Wine] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return wines.filter { wine in
            guard wine.isArchived == showArchived else { return false }
            if let typeFilter, wine.type != typeFilter { return false }
            guard !query.isEmpty else { return true }
            return wine.name.lowercased().contains(query)
                || wine.grapeOrRegion.lowercased().contains(query)
                || String(wine.vintage).contains(query)
        }
    }

    /// Gruppiert nach Typ in der Reihenfolge von `WineType.allCases`.
    func grouped(_ wines: [Wine]) -> [(type: WineType, wines: [Wine])] {
        WineType.allCases.compactMap { type in
            let matching = wines
                .filter { $0.type == type }
                .sorted { ($0.name, $0.vintage) < ($1.name, $1.vintage) }
            return matching.isEmpty ? nil : (type, matching)
        }
    }

    /// "12 Flaschen · 7 Weine" für die Kopfzeile.
    func summary(for wines: [Wine]) -> String {
        let active = wines.filter { !$0.isArchived }
        let bottles = active.reduce(0) { $0 + $1.quantity }
        return "\(bottles) \(bottles == 1 ? "Flasche" : "Flaschen") · \(active.count) \(active.count == 1 ? "Wein" : "Weine")"
    }

    // MARK: Bestandsaktionen

    func consume(_ wine: Wine) {
        guard wine.quantity > 0 else { return }
        wine.consumeBottle()
        consumeCount += 1
        if wine.isOutOfStock {
            justEmptiedWine = wine
        }
    }

    func addBottle(_ wine: Wine) {
        wine.addBottle()
    }

    func archive(_ wine: Wine) {
        wine.isArchived = true
    }

    func unarchive(_ wine: Wine) {
        wine.isArchived = false
    }

    func delete(_ wine: Wine, in context: ModelContext) {
        context.delete(wine)
    }
}
