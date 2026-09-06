import CloudKit
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

        private let title: String

        init(title: String) {
            self.title = title
        }

        func itemTitle(for csc: UICloudSharingController) -> String? { title }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            // Der Dialog zeigt den Fehler bereits selbst an.
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            guard let share = csc.share else { return }
            PersistenceController.shared.persist(share)
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            // Nach dem Beenden räumt CloudKit die geteilte Zone selbst auf.
        }
    }
}
