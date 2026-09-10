import CoreData
import Foundation
import Observation

/// Ob gerade eine Party läuft – und welche.
///
/// Liegt in der App ganz oben, weil der Party-Modus über allem liegen muss: Kein Tab,
/// keine Toolbar, kein Weg in den Keller. Beim Start der App wird geprüft, ob eine
/// unterbrochene Party gesichert ist; dann ist der gesperrte Modus sofort wieder da,
/// statt einem Gast den ganzen Keller zu zeigen.
@Observable
@MainActor
final class PartySession {

    private(set) var model: PartyViewModel?

    var isRunning: Bool { model != nil }

    /// Neue Party. Der Aufrufer prüft vorher den Code.
    func start() {
        model = PartyViewModel()
    }

    /// Unterbrochene Party fortsetzen, falls eine gesichert ist.
    func restoreIfNeeded(in context: NSManagedObjectContext) {
        guard model == nil, let restored = PartyViewModel.restored(in: context) else { return }
        model = restored
    }

    func end() {
        model = nil
    }
}
