import Foundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import Vision

/// Ergebnis des Zuschnitts – mit Diagnose, welche Strategie gegriffen hat.
struct LabelCropResult: Sendable {
    enum Strategy: String, Sendable { case rectangle, textBounds, fullImage }
    let jpegData: Data
    let strategy: Strategy
    /// Drehung in Grad (0, 90, 180, 270), die angewendet wurde, damit der Text lesbar liegt.
    let rotation: Int
}

/// Schneidet ein Flaschenfoto aufs Etikett zu und dreht es so, dass der Text lesbar ist.
///
/// 1. Rechteck-Erkennung (Vision): Wenn ein erkanntes Rechteck den Großteil des Textes enthält,
///    wird es perspektivisch entzerrt – das Etikett erscheint dann frontal und gerade.
/// 2. Sonst: Umriss aller Textzeilen plus Rand.
/// 3. Sonst: das ganze Bild.
/// Danach wird geprüft, in welcher Drehung die Texterkennung am besten liest (Querformat-Fotos).
///
/// Bewusst ohne UIKit, damit sich der Zuschnitt auch am Mac testen lässt.
enum LabelImageCropper {

    /// Längste Kante des gespeicherten Bilds – reicht für Detailseite und Miniaturen.
    private static let maxDimension: CGFloat = 1200

    static func cropLabel(from image: ScanImage, textLines: [RecognizedLine]) async -> LabelCropResult? {
        await Task.detached(priority: .userInitiated) {
            let source = CIImage(cgImage: image.cgImage).oriented(image.orientation)
            let extent = source.extent
            // Kurze Fragmente (z. B. "•LE" von der Kapsel) würden den Umriss unnötig aufblähen.
            let textBoxes = textLines
                .filter { $0.text.filter(\.isLetter).count >= 3 }
                .map(\.boundingBox)

            let textUnion = textBoxes.reduce(nil as CGRect?) { accumulated, box in accumulated?.union(box) ?? box }
            let rectangle = detectLabelRectangle(in: image, containing: textBoxes)

            var cropped: CIImage
            let strategy: LabelCropResult.Strategy
            if let rectangle, let textUnion, rectangle.boundingBox.insetBy(dx: -0.03, dy: -0.03).contains(textUnion) {
                // Das Rechteck umfasst den ganzen Text → Etikett perspektivisch entzerren.
                let quad = grown(rectangle, by: 1.06)
                let filter = CIFilter.perspectiveCorrection()
                filter.inputImage = source
                filter.topLeft = point(quad.topLeft, in: extent)
                filter.topRight = point(quad.topRight, in: extent)
                filter.bottomLeft = point(quad.bottomLeft, in: extent)
                filter.bottomRight = point(quad.bottomRight, in: extent)
                cropped = filter.outputImage ?? source
                strategy = .rectangle
            } else if let textUnion {
                // Gerader Zuschnitt: Text plus erkanntes Rechteck (falls vorhanden) plus Rand.
                let area = rectangle.map { $0.boundingBox.union(textUnion) } ?? textUnion
                cropped = source.cropped(to: expanded(area, by: 0.05, in: extent))
                strategy = .textBounds
            } else {
                cropped = source
                strategy = .fullImage
            }

            // Ursprung auf 0/0 normieren, damit Drehung und Skalierung sauber rechnen.
            cropped = cropped.transformed(by: CGAffineTransform(translationX: -cropped.extent.minX, y: -cropped.extent.minY))

            let context = CIContext()
            let rotation = bestRotation(for: cropped, textBoxes: textBoxes, sourceExtent: extent, context: context)
            let upright = rotated(cropped, degrees: rotation)
            let scaled = downscaled(upright)

            guard let jpeg = context.jpegRepresentation(
                of: scaled,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.85]
            ) else { return nil }
            return LabelCropResult(jpegData: jpeg, strategy: strategy, rotation: rotation)
        }.value
    }

    // MARK: Rechteck-Erkennung

    private struct Quad {
        let topLeft: CGPoint, topRight: CGPoint, bottomLeft: CGPoint, bottomRight: CGPoint
    }

    /// Liefert das Rechteck, das die meisten Textzeilen enthält – sofern es mindestens die Hälfte davon abdeckt.
    private static func detectLabelRectangle(in image: ScanImage, containing textBoxes: [CGRect]) -> VNRectangleObservation? {
        guard !textBoxes.isEmpty else { return nil }

        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.2
        request.maximumAspectRatio = 1.0
        request.minimumSize = 0.1
        request.minimumConfidence = 0.1
        request.maximumObservations = 10
        request.quadratureTolerance = 30

        let handler = VNImageRequestHandler(cgImage: image.cgImage, orientation: image.orientation, options: [:])
        guard (try? handler.perform([request])) != nil, let rectangles = request.results, !rectangles.isEmpty else {
            return nil
        }

        let centers = textBoxes.map { CGPoint(x: $0.midX, y: $0.midY) }
        var best: (observation: VNRectangleObservation, covered: Int)?
        for rectangle in rectangles {
            let covered = centers.filter { rectangle.boundingBox.contains($0) }.count
            if covered > (best?.covered ?? 0) {
                best = (rectangle, covered)
            }
        }
        guard let best, Double(best.covered) >= Double(centers.count) * 0.5 else { return nil }
        return best.observation
    }

    /// Vergrößert das Viereck um seinen Schwerpunkt, damit Ränder nicht abgeschnitten werden.
    private static func grown(_ o: VNRectangleObservation, by factor: CGFloat) -> Quad {
        let corners = [o.topLeft, o.topRight, o.bottomLeft, o.bottomRight]
        let centroid = CGPoint(
            x: corners.map(\.x).reduce(0, +) / 4,
            y: corners.map(\.y).reduce(0, +) / 4
        )
        func grow(_ p: CGPoint) -> CGPoint {
            CGPoint(
                x: min(max(centroid.x + (p.x - centroid.x) * factor, 0), 1),
                y: min(max(centroid.y + (p.y - centroid.y) * factor, 0), 1)
            )
        }
        return Quad(topLeft: grow(o.topLeft), topRight: grow(o.topRight),
                    bottomLeft: grow(o.bottomLeft), bottomRight: grow(o.bottomRight))
    }

    // MARK: Ausrichtung

    /// Prüft, ob das Etikett um 90° gedreht liegt (Querformat-Foto), und liefert die nötige Drehung.
    ///
    /// Entscheidung über die Geometrie: Aufrechte Textzeilen sind breiter als hoch. Stehen die
    /// erkannten Zeilen mehrheitlich hochkant, wird gedreht – und nur die Richtung (90° oder 270°)
    /// wird per Lesbarkeit bestimmt. 180° wird bewusst nicht geprüft: Fotos sind praktisch nie
    /// kopfstehend, und kopfstehender Text wird von der Erkennung gern als „sicherer“ Unsinn gelesen.
    private static func bestRotation(for image: CIImage, textBoxes: [CGRect], sourceExtent: CGRect, context: CIContext) -> Int {
        guard !textBoxes.isEmpty else { return 0 }
        // Normalisierte Boxen in Pixel-Seitenverhältnisse umrechnen.
        let ratios = textBoxes.map { ($0.height * sourceExtent.height) / max($0.width * sourceExtent.width, 1) }.sorted()
        let medianRatio = ratios[ratios.count / 2]
        guard medianRatio > 1.2 else { return 0 }

        // Für die Richtungsprüfung reicht eine kleine Version.
        let probe = downscaled(image, maxDimension: 700)
        var scores: [Int: Double] = [:]
        for degrees in [90, 270] {
            let candidate = rotated(probe, degrees: degrees)
            guard let cgImage = context.createCGImage(candidate, from: candidate.extent) else { continue }
            scores[degrees] = readabilityScore(of: cgImage)
        }
        return scores.max { $0.value < $1.value }?.key ?? 0
    }

    /// Summe aus Zeichenzahl × Konfidenz aller erkannten Zeilen.
    private static func readabilityScore(of cgImage: CGImage) -> Double {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil else { return 0 }
        return (request.results ?? []).reduce(0.0) { score, observation in
            guard let candidate = observation.topCandidates(1).first else { return score }
            return score + Double(candidate.string.count) * Double(candidate.confidence)
        }
    }

    // MARK: Bildoperationen

    private static func rotated(_ image: CIImage, degrees: Int) -> CIImage {
        guard degrees != 0 else { return image }
        let radians = CGFloat(degrees) * .pi / 180
        let rotated = image.transformed(by: CGAffineTransform(rotationAngle: radians))
        return rotated.transformed(by: CGAffineTransform(translationX: -rotated.extent.minX, y: -rotated.extent.minY))
    }

    private static func downscaled(_ image: CIImage, maxDimension: CGFloat = maxDimension) -> CIImage {
        let longest = max(image.extent.width, image.extent.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    // MARK: Koordinaten

    /// Normalisierter Vision-Punkt (Ursprung unten links) → CIImage-Pixelkoordinaten (ebenfalls unten links).
    private static func point(_ normalized: CGPoint, in extent: CGRect) -> CGPoint {
        CGPoint(
            x: extent.minX + normalized.x * extent.width,
            y: extent.minY + normalized.y * extent.height
        )
    }

    private static func expanded(_ normalized: CGRect, by margin: CGFloat, in extent: CGRect) -> CGRect {
        let rect = CGRect(
            x: extent.minX + (normalized.minX - margin) * extent.width,
            y: extent.minY + (normalized.minY - margin) * extent.height,
            width: (normalized.width + 2 * margin) * extent.width,
            height: (normalized.height + 2 * margin) * extent.height
        )
        return rect.intersection(extent)
    }
}
