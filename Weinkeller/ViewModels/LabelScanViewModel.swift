import Foundation
import Observation
import UIKit
import ImageIO

/// Zustand der Scan-Ansicht: zwei Fotos, Verarbeitung, Ergebnis oder Fehler.
@Observable
@MainActor
final class LabelScanViewModel {

    /// Ein Etikettfoto – immer das volle, ungeschnittene Bild.
    /// Den Zuschnitt aufs Etikett macht `LabelImageCropper`, der dafür das ganze Bild braucht.
    struct Photo {
        let image: UIImage
    }

    var front: Photo?
    var back: Photo?
    var isProcessing = false
    var result: LabelScanResult?
    var errorMessage: String?
    /// Erkannter Rohtext – zum Aufklappen, falls die Zuordnung mal danebenliegt.
    var recognizedText = ""

    var hasImages: Bool { front != nil || back != nil }

    /// Welche Seite gerade erfasst wird.
    enum Side: String, Identifiable {
        case front, back
        var id: String { rawValue }
        var title: String { self == .front ? "Vorderseite" : "Rückseite" }
    }

    /// Aufnahme der angetippten Seite übernehmen.
    func applyPhoto(_ image: UIImage?, to side: Side) {
        guard let image else { return }
        let photo = Photo(image: image)
        switch side {
        case .front: front = photo
        case .back:  back = photo
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
            orientation: CGImagePropertyOrientation(resized.imageOrientation)
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
