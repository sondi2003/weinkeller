import Foundation
import Observation

/// Das Abbuchen einer Flasche mit allem, was daran hängt – an **einer** Stelle, damit
/// Kellerliste, Berater und Detailseite dasselbe tun.
///
/// Liegen alle Flaschen im Regal, muss das Fach gewählt werden. War es die letzte
/// Flasche, folgt die Frage nach Bewerten, Archivieren oder Löschen. Die passenden
/// Sheets und Dialoge hängt `bottleConsumerFlow` an die Ansicht.
@Observable
@MainActor
final class BottleConsumer {

    /// Wein, dessen letzte Flasche gerade getrunken wurde.
    var justEmptiedWine: Wine?
    /// Wein, für den das Fach zu wählen ist, weil alle Flaschen verortet sind.
    var wineToTakeFromRack: Wine?
    /// Wein, der gerade bewertet wird.
    var wineToRate: Wine?
    /// Wein, dessen Löschen noch bestätigt werden muss.
    var wineToDelete: Wine?
    /// Trigger für haptisches Feedback.
    var consumeCount = 0

    func consume(_ wine: Wine) {
        guard wine.quantity > 0 else { return }
        guard !(wine.placedCount > 0 && wine.unplacedCount == 0) else {
            wineToTakeFromRack = wine
            return
        }
        wine.consumeBottle()
        consumeCount += 1
        if wine.isOutOfStock {
            justEmptiedWine = wine
        }
    }
}
