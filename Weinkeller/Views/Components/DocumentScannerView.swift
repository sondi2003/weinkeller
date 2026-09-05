import SwiftUI
import UIKit
import VisionKit

/// Apples Dokumentenscanner (VisionKit): erkennt das Etikett live im Kamerabild, löst
/// automatisch aus, schneidet zu und begradigt perspektivisch. Mehrere Seiten pro Durchgang
/// möglich – erste Seite = Vorderseite, zweite = Rückseite.
///
/// Auf dem Simulator nicht verfügbar (`DocumentScannerView.isSupported`).
struct DocumentScannerView: UIViewControllerRepresentable {

    static var isSupported: Bool {
        VNDocumentCameraViewController.isSupported
    }

    /// Wird mit den zugeschnittenen Seiten aufgerufen (leer bei Abbruch).
    let onFinish: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onFinish: ([UIImage]) -> Void

        init(onFinish: @escaping ([UIImage]) -> Void) {
            self.onFinish = onFinish
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            onFinish(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish([])
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onFinish([])
        }
    }
}
