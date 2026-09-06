import Foundation
import OSLog

/// Snapshot der Cloud-Zugangsdaten, damit der Service nicht am Main Actor hängt.
struct CloudCredentials: Sendable {
    let provider: AIProvider
    let apiKey: String
    let model: String
}

/// Orchestriert die Etikett-Erkennung:
/// 1. Texterkennung auf dem Gerät (Vision)
/// 2. Zuschnitt des Vorderseiten-Fotos aufs Etikett
/// 3. Zuordnung zu Feldern – Apple Intelligence, sonst aktiver Cloud-Anbieter, sonst Regeln
struct LabelScanService: Sendable {

    private static let logger = Logger(subsystem: "com.weinkeller.app", category: "LabelScan")
    private let aiService: AIService

    init(aiService: AIService) {
        self.aiService = aiService
    }

    /// Erkennt Text in den Bildern, schneidet die Vorderseite zu und ordnet die Felder zu.
    /// - Parameter cloud: Zugangsdaten des aktiven Anbieters oder `nil`, wenn keiner eingerichtet ist.
    func scan(front: ScanImage?, back: ScanImage?, cloud: CloudCredentials?) async throws -> LabelScanResult {
        var sections: [(title: String, lines: [RecognizedLine])] = []
        var labelImageData: Data?

        if let front {
            let lines = try await LabelTextRecognizer.recognizeLines(in: front)
            sections.append(("Vorderseite", lines))
            if let crop = await LabelImageCropper.cropLabel(from: front, textLines: lines) {
                labelImageData = crop.jpegData
                Self.logger.info("Etikett-Foto: \(crop.jpegData.count) Bytes, Zuschnitt \(crop.strategy.rawValue), Drehung \(crop.rotation)°")
            }
        }
        if let back {
            let lines = try await LabelTextRecognizer.recognizeLines(in: back)
            sections.append(("Rückseite", lines))
        }

        let text = LabelTextRecognizer.combinedText(sections)
        guard !text.isEmpty else { throw LabelScanError.noTextFound }
        Self.logger.info("OCR: \(text.count) Zeichen erkannt")

        let (extraction, source) = await structure(text: text, cloud: cloud)
        guard extraction.hasContent else { throw LabelScanError.nothingRecognized(text) }
        Self.logger.info("Zuordnung via \(source.displayName)")
        return LabelScanResult(
            extraction: extraction,
            recognizedText: text,
            source: source,
            labelImageData: labelImageData
        )
    }

    /// Wählt die beste verfügbare Zuordnung und fällt bei Fehlern eine Stufe zurück.
    private func structure(text: String, cloud: CloudCredentials?) async -> (WineLabelExtraction, LabelExtractionSource) {
        let heuristic = HeuristicLabelParser.parse(recognizedText: text)

        // 1. Apple Intelligence auf dem Gerät
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), OnDeviceLabelParser.isAvailable {
            do {
                let extraction = try await OnDeviceLabelParser.parse(recognizedText: text)
                if extraction.hasContent {
                    return (merge(extraction, with: heuristic), .onDevice)
                }
                Self.logger.warning("Apple Intelligence lieferte keine Felder")
            } catch {
                Self.logger.error("Apple Intelligence fehlgeschlagen: \(String(describing: error))")
            }
        }
        #endif

        // 2. Aktiver Cloud-Anbieter (nur Text, kein Foto)
        if let cloud {
            do {
                let extraction = try await aiService.extractLabel(
                    recognizedText: text,
                    provider: cloud.provider,
                    apiKey: cloud.apiKey,
                    model: cloud.model
                )
                if extraction.hasContent {
                    return (merge(extraction, with: heuristic), .cloud(cloud.provider))
                }
                Self.logger.warning("\(cloud.provider.shortName) lieferte keine Felder")
            } catch {
                Self.logger.error("\(cloud.provider.shortName) fehlgeschlagen: \(error.localizedDescription)")
            }
        }

        // 3. Regeln ohne KI
        return (heuristic, .heuristic)
    }

    /// Füllt Lücken der KI-Zuordnung mit den regelbasierten Treffern (z. B. Jahrgang, Alkohol).
    private func merge(_ primary: WineLabelExtraction, with fallback: WineLabelExtraction) -> WineLabelExtraction {
        var merged = primary
        if merged.vintage == 0 { merged.vintage = fallback.vintage }
        if merged.alcoholPercent == 0 { merged.alcoholPercent = fallback.alcoholPercent }
        if merged.wineType == nil, fallback.wineType != nil { merged.type = fallback.type }
        if merged.grape.isEmpty { merged.grape = fallback.grape }
        if merged.region.isEmpty { merged.region = fallback.region }
        if merged.country.isEmpty { merged.country = fallback.country }
        if merged.foodPairings.isEmpty { merged.foodPairings = fallback.foodPairings }
        return merged
    }
}

enum LabelScanError: LocalizedError {
    case noTextFound
    case nothingRecognized(String)

    var errorDescription: String? {
        switch self {
        case .noTextFound:
            return "Auf den Fotos wurde kein Text erkannt. Bitte das Etikett näher und bei gutem Licht fotografieren."
        case .nothingRecognized:
            return "Der Text konnte keinem Feld zugeordnet werden. Du kannst die Angaben manuell eintragen."
        }
    }
}
