import Foundation
import CoreGraphics
import ImageIO
import Vision

/// Ein Bild plus Ausrichtung, sicher über Actor-Grenzen hinweg übergebbar.
/// `CGImage` ist unveränderlich, daher unbedenklich.
struct ScanImage: @unchecked Sendable {
    let cgImage: CGImage
    let orientation: CGImagePropertyOrientation
}

/// Texterkennung auf dem Gerät mit dem Vision-Framework (iOS 13+).
/// Kein Netzwerk, keine Kosten – das Foto verlässt das iPhone nicht.
enum LabelTextRecognizer {

    /// Sprachen, in denen Weinetiketten typischerweise beschriftet sind.
    private static let languages = ["fr-FR", "de-DE", "it-IT", "es-ES", "en-US"]

    /// Erkennt den Text aller Bilder und fügt ihn zeilenweise zusammen.
    /// Bilder werden mit einer Überschrift getrennt, damit die KI Vorder- und Rückseite unterscheiden kann.
    static func recognizeText(in images: [(title: String, image: ScanImage)]) async throws -> String {
        var sections: [String] = []
        for entry in images {
            let lines = try await recognizeLines(in: entry.image)
            guard !lines.isEmpty else { continue }
            sections.append("[\(entry.title)]\n" + lines.joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n")
    }

    /// Erkennt die Textzeilen eines Bildes, sortiert von oben nach unten.
    static func recognizeLines(in image: ScanImage) async throws -> [String] {
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
                .compactMap { $0.topCandidates(1).first }
                .filter { $0.confidence > 0.3 }
                .map { $0.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }.value
    }
}
