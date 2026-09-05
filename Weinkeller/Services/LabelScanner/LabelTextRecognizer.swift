import Foundation
import CoreGraphics
import ImageIO
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
}

/// Texterkennung auf dem Gerät mit dem Vision-Framework (iOS 13+).
/// Kein Netzwerk, keine Kosten – das Foto verlässt das iPhone nicht.
enum LabelTextRecognizer {

    /// Sprachen, in denen Weinetiketten typischerweise beschriftet sind.
    private static let languages = ["fr-FR", "de-DE", "it-IT", "es-ES", "en-US"]

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
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = languages
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(cgImage: image.cgImage, orientation: image.orientation, options: [:])
            try handler.perform([request])

            let observations = request.results ?? []
            // Vision liefert Koordinaten mit Ursprung unten links – oben zuerst sortieren.
            return observations
                .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                .compactMap { observation -> RecognizedLine? in
                    guard let candidate = observation.topCandidates(1).first, candidate.confidence > 0.3 else { return nil }
                    let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return nil }
                    return RecognizedLine(text: text, boundingBox: observation.boundingBox)
                }
        }.value
    }
}
