import CloudKit
import OSLog
import SwiftUI
import UIKit

/// Apples Standard-Dialog zum Teilen: Einladung per Nachricht oder Mail verschicken,
/// Teilnehmer verwalten, Rechte ändern, Freigabe beenden.
struct CloudSharingView: UIViewControllerRepresentable {

    let share: CKShare
    let container: CKContainer
    /// Wird angezeigt, während die Einladung vorbereitet wird.
    let title: String

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(title: title)
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {

        private static let logger = Logger(subsystem: "com.weinkeller.app", category: "Persistence")
        private let title: String

        init(title: String) {
            self.title = title
        }

        func itemTitle(for csc: UICloudSharingController) -> String? { title }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            // Der Dialog zeigt den Fehler bereits selbst an; fürs Protokoll trotzdem notiert.
            Self.logger.error("Freigabe nicht gespeichert: \(error.localizedDescription, privacy: .public)")
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            guard let share = csc.share else { return }
            let others = share.participants.filter { $0.role != .owner }.count
            Self.logger.info("Freigabe gespeichert, \(others) Teilnehmer ausser dem Eigentümer.")
            PersistenceController.shared.persist(share)
        }

        /// Wird auf **beiden** Seiten aufgerufen: Beendet der Eigentümer die Freigabe,
        /// verlieren alle Teilnehmer den Zugriff; entfernt sich ein Teilnehmer selbst,
        /// betrifft es nur ihn. Das Aufräumen der geteilten Zone übernimmt CloudKit, und
        /// Core Data entfernt die Datensätze beim nächsten Abgleich aus dem geteilten
        /// Speicher. Hier wird nur mitgeschrieben, damit sich im Zweifel nachvollziehen
        /// lässt, ob das Beenden überhaupt angekommen ist.
        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            Self.logger.info("Freigabe beendet.")
        }
    }
}
