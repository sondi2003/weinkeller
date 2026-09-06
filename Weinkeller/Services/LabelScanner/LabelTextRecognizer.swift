import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import OSLog
import Vision

/// Ein Bild plus Ausrichtung, sicher über Actor-Grenzen hinweg übergebbar.
/// `CGImage` ist unveränderlich, daher unbedenklich.
struct ScanImage: @unchecked Sendable {
    let cgImage: CGImage
    let orientation: CGImagePropertyOrientation
    /// `true`, wenn das Bild bereits vom Dokumentenscanner zugeschnitten und begradigt wurde.
    var isPreCropped: Bool = false
}

/// Eine erkannte Textzeile mit ihrer Position (normalisiert, Ursprung unten links – Vision-Konvention).
struct RecognizedLine: Sendable {
    let text: String
    let boundingBox: CGRect
    let confidence: Float
}

/// Texterkennung auf dem Gerät mit dem Vision-Framework.
/// Kein Netzwerk, keine Kosten – das Foto verlässt das iPhone nicht.
///
/// Weinetiketten sind oft dunkel bedruckt auf dunklem Glas und zusätzlich gewölbt.
/// Deshalb wird bei schwachem Ergebnis mit aufbereiteten Varianten nachgelegt und die
/// beste genommen.
enum LabelTextRecognizer {

    private static let logger = Logger(subsystem: "com.weinkeller.app", category: "OCR")

    /// Sprachen, in denen Weinetiketten typischerweise beschriftet sind.
    private static let languages = ["fr-FR", "de-DE", "it-IT", "es-ES", "en-US"]

    /// Aufbereitungen, die nacheinander probiert werden, bis das Ergebnis gut genug ist.
    private enum Preparation: String, CaseIterable {
        /// Unverändert – reicht bei gut ausgeleuchteten Etiketten.
        case original
        /// Apples Dokument-Aufbereitung: entfernt Schatten, hellt den Untergrund auf.
        case enhanced
        /// Kräftig aufgehellt und kontrastiert – für dunkle Schrift auf dunklem Glas.
        case brightened
    }

    /// Fügt erkannte Zeilen mehrerer Bilder zu einem Text zusammen. Abschnitte werden mit
    /// einer Überschrift getrennt, damit die KI Vorder- und Rückseite unterscheiden kann.
    static func combinedText(_ sections: [(title: String, lines: [RecognizedLine])]) -> String {
        sections
            .filter { !$0.lines.isEmpty }
            .map { "[\($0.title)]\n" + $0.lines.map(\.text).joined(separator: "\n") }
            .joined(separator: "\n\n")
    }

    /// Erkennt die Textzeilen eines Bildes, sortiert von oben nach unten.
    static func recognizeLines(in image: ScanImage) async throws -> [RecognizedLine] {
        try await Task.detached(priority: .userInitiated) {
            let source = CIImage(cgImage: image.cgImage).oriented(image.orientation)
            let context = CIContext()

            // Alle Varianten durchlaufen und die beste nehmen. Ein früher Abbruch bei
            // „genug Zeilen“ wäre trügerisch: Bei dunklen Etiketten liefert das Original
            // ein paar unbrauchbare Zeilen und die Aufbereitung käme nie zum Zug.
            var best: [RecognizedLine] = []
            var bestScore = 0.0
            var bestPreparation = Preparation.original
            for preparation in Preparation.allCases {
                guard let prepared = prepare(source, with: preparation, context: context) else { continue }
                let lines = try recognize(prepared)
                let score = lines.reduce(0.0) { $0 + Double($1.text.count) * Double($1.confidence) }
                if score > bestScore {
                    bestScore = score
                    best = lines
                    bestPreparation = preparation
                }
            }
            logger.info("Texterkennung: „\(bestPreparation.rawValue)“ mit \(best.count) Zeilen")
            return best
        }.value
    }

    // MARK: Aufbereitung

    private static func prepare(_ image: CIImage, with preparation: Preparation, context: CIContext) -> CGImage? {
        let output: CIImage
        switch preparation {
        case .original:
            output = image
        case .enhanced:
            let filter = CIFilter.documentEnhancer()
            filter.inputImage = image
            filter.amount = 1
            guard let result = filter.outputImage else { return nil }
            output = result
        case .brightened:
            // Belichtung anheben, dann Kontrast – so treten dunkle Buchstaben auf
            // dunklem Glas überhaupt erst hervor.
            let exposure = CIFilter.exposureAdjust()
            exposure.inputImage = image
            exposure.ev = 1.4
            guard let brightened = exposure.outputImage else { return nil }
            let controls = CIFilter.colorControls()
            controls.inputImage = brightened
            controls.contrast = 1.6
            controls.saturation = 0          // Farbe hilft beim Lesen nicht
            guard let result = controls.outputImage else { return nil }
            output = result
        }
        return context.createCGImage(output, from: output.extent)
    }

    private static func recognize(_ cgImage: CGImage) throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages
        request.automaticallyDetectsLanguage = true

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        // Vision liefert Koordinaten mit Ursprung unten links – oben zuerst sortieren.
        return observations
            .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            .compactMap { observation -> RecognizedLine? in
                guard let candidate = observation.topCandidates(1).first, candidate.confidence > 0.3 else { return nil }
                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return RecognizedLine(
                    text: text,
                    boundingBox: observation.boundingBox,
                    confidence: candidate.confidence
                )
            }
    }
}
