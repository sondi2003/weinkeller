import SwiftUI
import UIKit

/// Kamera für die Etikett-Aufnahme – liefert bewusst das **ungeschnittene** Foto.
///
/// Vorher lief das über Apples Dokumentenscanner (`VNDocumentCameraViewController`).
/// Der ist auf Papier ausgelegt: Er sucht ein helles Blatt vor dunklem Grund und liefert
/// nur sein eigenes Ergebnis zurück, nie das Originalbild. Bei einem Etikett auf einer
/// runden, dunklen Flasche rastet sein Rahmen regelmäßig auf der Flaschenkontur statt auf
/// dem Etikett ein – dann steckt Glas und Hintergrund im Bild und muss von Hand
/// nachgeschnitten werden. Und weil das Original verworfen ist, kann die App das
/// nachträglich nicht mehr geradebiegen.
///
/// Deshalb hier eine schlichte Aufnahme des ganzen Bildes. Die Etikettenkante findet
/// anschließend `LabelImageCropper` mit Apples Dokument-Segmentierung auf dem vollen Foto.
struct CameraCaptureView: UIViewControllerRepresentable {

    static var isSupported: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    /// Wird mit dem aufgenommenen Foto aufgerufen – `nil` bei Abbruch.
    let onCapture: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        // Kein Zuschneiden durch das System: Die Etikettenerkennung braucht das volle Bild.
        controller.allowsEditing = false
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (UIImage?) -> Void

        init(onCapture: @escaping (UIImage?) -> Void) {
            self.onCapture = onCapture
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            onCapture(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
        }
    }
}
