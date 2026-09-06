import CloudKit
import CoreData
import Foundation
import Observation
import OSLog

/// Wer an diesem Gerät bewertet.
///
/// **Kennung**: Bevorzugt die stabile Benutzerkennung des iCloud-Containers
/// (`CKContainer.userRecordID()`). Sie unterscheidet die beiden Apple-IDs zuverlässig,
/// auch wenn beide denselben Anzeigenamen wählen, und übersteht eine Neuinstallation.
///
/// Ist iCloud gerade nicht erreichbar – kein Konto, kein Netz, Simulator –, wird eine
/// lokale Kennung erzeugt, damit trotzdem bewertet werden kann. Sobald die iCloud-Kennung
/// später eintrifft, werden die eigenen Bewertungen darauf umgeschrieben; sonst stünde
/// dieselbe Person plötzlich zweimal in der Liste.
///
/// **Name**: Muss die Person selbst eintragen. Apple hat die Namensauflösung fremder
/// iCloud-Konten mit iOS 17 abgekündigt, und bei einer Einladung per Link bleibt das
/// Namensfeld der Teilnehmer teilweise leer – ein automatisch ermittelter Name wäre
/// also mal da und mal nicht.
@Observable
@MainActor
final class CurrentRater {

    private static let logger = Logger(subsystem: "com.weinkeller.app", category: "Persistence")
    private static let nameKey = "raterName"
    private static let identifierKey = "raterID"
    /// Kennzeichnet eine Notkennung, die noch nicht von iCloud stammt.
    private static let localPrefix = "local-"

    private let defaults: UserDefaults

    /// Anzeigename, den die Person in den Einstellungen einträgt.
    var name: String {
        didSet { defaults.set(name, forKey: Self.nameKey) }
    }

    /// Kennung dieser Person. Nie leer.
    private(set) var identifier: String

    /// Alte Kennung, deren Bewertungen noch umgeschrieben werden müssen.
    private var identifierToReplace: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.name = defaults.string(forKey: Self.nameKey) ?? ""
        if let stored = defaults.string(forKey: Self.identifierKey), !stored.isEmpty {
            self.identifier = stored
        } else {
            self.identifier = Self.localPrefix + UUID().uuidString
            defaults.set(self.identifier, forKey: Self.identifierKey)
        }
    }

    /// Holt die iCloud-Kennung, falls bisher nur eine lokale vorliegt.
    func refresh(container: CKContainer = CKContainer(identifier: PersistenceController.cloudContainerIdentifier)) async {
        guard identifier.hasPrefix(Self.localPrefix) else { return }
        do {
            let recordID = try await container.userRecordID()
            let previous = identifier
            identifier = recordID.recordName
            identifierToReplace = previous
            defaults.set(identifier, forKey: Self.identifierKey)
            Self.logger.info("Bewerter-Kennung von iCloud übernommen.")
        } catch {
            // Kein Drama: Mit der lokalen Kennung lässt sich weiterarbeiten.
            Self.logger.info("Keine iCloud-Kennung verfügbar, lokale Kennung bleibt: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Schreibt Bewertungen von der alten auf die neue Kennung um.
    func adoptExistingRatings(in context: NSManagedObjectContext) {
        guard let old = identifierToReplace else { return }
        identifierToReplace = nil
        let request = Rating.fetchRequest()
        request.predicate = NSPredicate(format: "raterID == %@", old)
        guard let ratings = try? context.fetch(request), !ratings.isEmpty else { return }
        for rating in ratings {
            rating.raterID = identifier
        }
        context.saveChanges()
        Self.logger.info("\(ratings.count) Bewertung(en) auf die iCloud-Kennung übertragen.")
    }
}
