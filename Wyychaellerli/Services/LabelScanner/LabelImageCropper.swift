import Foundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import Vision

/// Ergebnis des Zuschnitts – mit Diagnose, welche Strategie gegriffen hat.
struct LabelCropResult: @unchecked Sendable {
    enum Strategy: String, Sendable { case document, rectangle, textBounds, fullImage }
    let jpegData: Data
    let strategy: Strategy
    /// Drehung in Grad (0, 90, 180, 270), die angewendet wurde, damit der Text lesbar liegt.
    let rotation: Int
    /// Das aufrechte Etikett in Lese-Auflösung (längste Kante bis 2400 px), aus dem
    /// vollen Foto geschnitten – für den zweiten Durchgang der Texterkennung.
    let ocrImage: CGImage?
}

/// Schneidet ein Flaschenfoto aufs Etikett zu und dreht es so, dass der Text lesbar ist.
///
/// 1. Dokument-Segmentierung (Vision, ML-basiert): findet die Etikettenkante auch auf
///    dunklem, gewölbtem Glas. Das Ergebnis wird perspektivisch entzerrt.
/// 2. Sonst Rechteck-Erkennung: Wenn ein erkanntes Rechteck den Grossteil des Textes enthält.
/// 3. Sonst: Umriss aller Textzeilen plus Rand – aber nur, wenn das Bild nicht ohnehin
///    schon fast nur aus Etikett besteht.
/// 4. Sonst: das ganze Bild.
/// Danach wird geprüft, in welcher Drehung die Texterkennung am besten liest (Querformat-Fotos).
///
/// Bewusst ohne UIKit, damit sich der Zuschnitt auch am Mac testen lässt.
enum LabelImageCropper {

    /// Längste Kante des gespeicherten Bilds – reicht für Detailseite und Miniaturen.
    private static let maxDimension: CGFloat = 1200

    /// Ab diesem Flächenanteil gilt ein Textumriss als „das Bild ist schon das Etikett“.
    /// Gemessen: volle Flaschenfotos 9–13 %, bereits zugeschnittene Etiketten 72–88 %.
    private static let croppedAlreadyThreshold: CGFloat = 0.55

    static func cropLabel(from image: ScanImage, textLines: [RecognizedLine]) async -> LabelCropResult? {
        await Task.detached(priority: .userInitiated) {
            // Erkannt wird auf der verkleinerten Fassung, geschnitten aus dem vollen Foto:
            // Die Vision-Koordinaten sind normiert und gelten für beide. So behält ein
            // kleines Etikett auf einer schmalen Flasche seine Pixel.
            let source = image.original.map { CIImage(cgImage: $0).oriented(image.orientation) }
                ?? CIImage(cgImage: image.cgImage).oriented(image.orientation)
            let extent = source.extent
            // Kurze Fragmente (z. B. "•LE" von der Kapsel) würden den Umriss unnötig aufblähen.
            let textBoxes = textLines
                .filter { $0.text.filter(\.isLetter).count >= 3 }
                .map(\.boundingBox)

            let textUnion = textBoxes.reduce(nil as CGRect?) { accumulated, box in accumulated?.union(box) ?? box }
            let document = detectLabelDocument(in: image, containing: textBoxes)
            let rectangle = document == nil ? detectLabelRectangle(in: image, containing: textBoxes) : nil

            var cropped: CIImage
            let strategy: LabelCropResult.Strategy
            if let document {
                // Etikettenkante gefunden → frontal entzerren. Nur wenig wachsen lassen,
                // die Segmentierung liegt bereits genau auf der Kante.
                cropped = perspectiveCorrected(source, quad: grown(document, by: 1.02), extent: extent)
                strategy = .document
            } else if let rectangle, let textUnion, rectangle.boundingBox.insetBy(dx: -0.03, dy: -0.03).contains(textUnion) {
                // Das Rechteck umfasst den ganzen Text → Etikett perspektivisch entzerren.
                cropped = perspectiveCorrected(source, quad: grown(rectangle, by: 1.06), extent: extent)
                strategy = .rectangle
            } else if let textUnion, textUnion.width * textUnion.height < croppedAlreadyThreshold {
                // Gerader Zuschnitt: Text plus erkanntes Rechteck (falls vorhanden) plus Rand.
                let area = rectangle.map { $0.boundingBox.union(textUnion) } ?? textUnion
                cropped = source.cropped(to: expanded(area, by: 0.05, in: extent))
                strategy = .textBounds
            } else {
                // Das Bild ist bereits im Wesentlichen das Etikett – nichts wegschneiden.
                cropped = source
                strategy = .fullImage
            }

            // Ursprung auf 0/0 normieren, damit Drehung und Skalierung sauber rechnen.
            cropped = cropped.transformed(by: CGAffineTransform(translationX: -cropped.extent.minX, y: -cropped.extent.minY))

            let context = CIContext()
            let rotation = uprightRotation(for: cropped, context: context)
            let upright = rotated(cropped, degrees: rotation)
            let scaled = downscaled(upright)

            guard let jpeg = context.jpegRepresentation(
                of: scaled,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.85]
            ) else { return nil }

            // Fürs zweite Lesen: nur wenn wirklich geschnitten wurde – das ganze Bild
            // wurde ja schon gelesen.
            var ocrImage: CGImage?
            if strategy != .fullImage {
                let readable = downscaled(upright, maxDimension: ocrDimension)
                ocrImage = context.createCGImage(readable, from: readable.extent)
            }
            return LabelCropResult(jpegData: jpeg, strategy: strategy, rotation: rotation, ocrImage: ocrImage)
        }.value
    }

    /// Längste Kante des Zuschnitts fürs zweite Lesen – dieselbe Grösse wie das ganze
    /// Foto im ersten Durchgang, jetzt aber nur fürs Etikett.
    private static let ocrDimension: CGFloat = 2400

    // MARK: Etikettenkante

    private struct Quad {
        let topLeft: CGPoint, topRight: CGPoint, bottomLeft: CGPoint, bottomRight: CGPoint
    }

    /// Apples ML-Dokumentsegmentierung – dieselbe Technik, die auch den Dokumentenscanner
    /// speist, hier aber auf das volle Foto angewendet und mit eigenen Prüfungen abgesichert.
    ///
    /// Sie findet die Etikettenkante auch dann, wenn Etikett und Flasche beide dunkel sind:
    /// gemessen an den Referenzfotos bis hinunter zu EV −2 mit Konfidenz ≥ 0,90.
    ///
    /// Zwei Prüfungen halten Fehltreffer ab:
    /// - **Fläche**: Deckt das Viereck fast das ganze Bild, ist nichts gefunden worden
    ///   (das passiert bei bereits zugeschnittenen Bildern). Dann lieber nicht schneiden.
    /// - **Text**: Das Viereck muss den Grossteil der erkannten Zeilen enthalten, sonst
    ///   wurde etwas anderes gefunden – ein Buch, ein Tisch, ein Blatt Papier daneben.
    private static func detectLabelDocument(in image: ScanImage, containing textBoxes: [CGRect]) -> VNRectangleObservation? {
        guard !textBoxes.isEmpty else { return nil }

        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cgImage: image.cgImage, orientation: image.orientation, options: [:])
        guard (try? handler.perform([request])) != nil, let observation = request.results?.first else {
            return nil
        }

        let box = observation.boundingBox
        guard box.width * box.height < 0.88 else { return nil }

        let centers = textBoxes.map { CGPoint(x: $0.midX, y: $0.midY) }
        let covered = centers.filter { box.insetBy(dx: -0.02, dy: -0.02).contains($0) }.count
        guard Double(covered) >= Double(centers.count) * 0.7 else { return nil }
        return observation
    }

    private static func perspectiveCorrected(_ source: CIImage, quad: Quad, extent: CGRect) -> CIImage {
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = source
        filter.topLeft = point(quad.topLeft, in: extent)
        filter.topRight = point(quad.topRight, in: extent)
        filter.bottomLeft = point(quad.bottomLeft, in: extent)
        filter.bottomRight = point(quad.bottomRight, in: extent)
        return filter.outputImage ?? source
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

    /// Vergrössert das Viereck um seinen Schwerpunkt, damit Ränder nicht abgeschnitten werden.
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

    /// Liefert die Drehung, die den Text aufrecht stellt – gemessen, nicht geraten.
    ///
    /// `VNRecognizedTextObservation` erbt von `VNRectangleObservation` und gibt das **gedrehte**
    /// Viereck der Zeile zurück. Die Strecke von `bottomLeft` nach `bottomRight` ist damit die
    /// Leserichtung: 0° = aufrecht, 90° = von unten nach oben, 180° = kopfstehend.
    ///
    /// Der frühere Weg verglich stattdessen die „Lesbarkeit“ zweier Drehungen (Zeichen × Konfidenz).
    /// Das trägt nicht: An den Referenzbildern liegen alle vier Drehungen dicht beieinander, und
    /// die Sprachkorrektur macht aus kopfstehendem Text plausibel aussehende Wörter. Gemessen an
    /// einem kopfstehenden Ergebnis gewann dort die falsche Richtung.
    private static func uprightRotation(for image: CIImage, context: CIContext) -> Int {
        // Für die Winkelmessung reicht eine kleine Version.
        let probe = downscaled(image, maxDimension: 700)
        guard let cgImage = context.createCGImage(probe, from: probe.extent) else { return 0 }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil else { return 0 }

        // Jede Zeile stimmt für eine Vierteldrehung ab; die Mehrheit gewinnt.
        var votes: [Int: Int] = [:]
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first,
                  candidate.string.filter(\.isLetter).count >= 3 else { continue }
            let dx = observation.bottomRight.x - observation.bottomLeft.x
            let dy = observation.bottomRight.y - observation.bottomLeft.y
            let degrees = Double(atan2(dy, dx)) * 180 / .pi
            let quarter = ((Int((degrees / 90).rounded()) % 4) + 4) % 4
            votes[quarter, default: 0] += 1
        }
        guard let quarter = votes.max(by: { $0.value < $1.value })?.key else { return 0 }
        // Gegenrichtung anwenden, damit die Zeilen waagrecht liegen.
        return (360 - quarter * 90) % 360
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
