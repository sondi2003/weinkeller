import Foundation
import Observation
import UIKit
import ImageIO

/// Zustand der Scan-Ansicht: zwei Fotos, Verarbeitung, Ergebnis oder Fehler.
@Observable
@MainActor
final class LabelScanViewModel {

    /// Ein Etikettfoto samt Herkunft.
    struct Photo {
        let image: UIImage
        /// Vom Dokumentenscanner bereits zugeschnitten und begradigt.
        let isPreCropped: Bool
    }

    var front: Photo?
    var back: Photo?
    var isProcessing = false
    var result: LabelScanResult?
    var errorMessage: String?
    /// Erkannter Rohtext – zum Aufklappen, falls die Zuordnung mal danebenliegt.
    var recognizedText = ""

    var hasImages: Bool { front != nil || back != nil }

    /// Seiten aus dem Dokumentenscanner übernehmen: erste = Vorderseite, zweite = Rückseite.
    /// Ist die Vorderseite schon belegt, füllt eine einzelne Seite die Rückseite.
    func applyScannedPages(_ pages: [UIImage]) {
        guard !pages.isEmpty else { return }
        if pages.count >= 2 {
            front = Photo(image: pages[0], isPreCropped: true)
            back = Photo(image: pages[1], isPreCropped: true)
        } else if front == nil {
            front = Photo(image: pages[0], isPreCropped: true)
        } else {
            back = Photo(image: pages[0], isPreCropped: true)
        }
    }

    func scan(service: LabelScanService, settings: AISettings) async {
        guard hasImages, !isProcessing else { return }
        isProcessing = true
        errorMessage = nil
        result = nil
        defer { isProcessing = false }

        let frontScan = front.flatMap(Self.scanImage(from:))
        let backScan = back.flatMap(Self.scanImage(from:))

        let cloud: CloudCredentials? = settings.activeProvider.map {
            CloudCredentials(provider: $0, apiKey: settings.apiKey(for: $0), model: settings.model(for: $0))
        }

        do {
            let scanResult = try await service.scan(front: frontScan, back: backScan, cloud: cloud)
            result = scanResult
            recognizedText = scanResult.recognizedText
        } catch let error as LabelScanError {
            if case .nothingRecognized(let text) = error { recognizedText = text }
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Bild-Konvertierung

    /// `UIImage` → `CGImage` + Ausrichtung, ggf. auf eine sinnvolle Größe verkleinert.
    private static func scanImage(from photo: Photo) -> ScanImage? {
        let resized = photo.image.resizedForRecognition(maxDimension: 2400)
        guard let cgImage = resized.cgImage else { return nil }
        return ScanImage(
            cgImage: cgImage,
            orientation: CGImagePropertyOrientation(resized.imageOrientation),
            isPreCropped: photo.isPreCropped
        )
    }
}

// MARK: - Helfer

extension CGImagePropertyOrientation {
    /// Übersetzt die UIKit-Ausrichtung in die Vision-/ImageIO-Ausrichtung.
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up:            self = .up
        case .down:          self = .down
        case .left:          self = .left
        case .right:         self = .right
        case .upMirrored:    self = .upMirrored
        case .downMirrored:  self = .downMirrored
        case .leftMirrored:  self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default:    self = .up
        }
    }
}

extension UIImage {
    /// Verkleinert sehr große Fotos, damit die Texterkennung schnell bleibt.
    /// Behält die Orientierung bei, die Vision anschließend berücksichtigt.
    func resizedForRecognition(maxDimension: CGFloat) -> UIImage {
        let largest = max(size.width, size.height)
        guard largest > maxDimension, let cgImage else { return self }
        let scale = maxDimension / largest
        let newSize = CGSize(width: cgImage.width, height: cgImage.height).applying(CGAffineTransform(scaleX: scale, y: scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let rendered = renderer.image { _ in
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: newSize))
        }
        guard let renderedCG = rendered.cgImage else { return self }
        return UIImage(cgImage: renderedCG, scale: 1, orientation: imageOrientation)
    }
}
