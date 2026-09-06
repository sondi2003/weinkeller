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
        var backLabelImageData: Data?

        if let front {
            let lines = try await LabelTextRecognizer.recognizeLines(in: front)
            sections.append(("Vorderseite", lines))
            if let crop = await LabelImageCropper.cropLabel(from: front, textLines: lines) {
                labelImageData = crop.jpegData
                Self.logger.info("Etikett vorne: \(crop.jpegData.count) Bytes, Zuschnitt \(crop.strategy.rawValue), Drehung \(crop.rotation)°")
            }
        }
        if let back {
            let lines = try await LabelTextRecognizer.recognizeLines(in: back)
            sections.append(("Rückseite", lines))
            if let crop = await LabelImageCropper.cropLabel(from: back, textLines: lines) {
                backLabelImageData = crop.jpegData
                Self.logger.info("Etikett hinten: \(crop.jpegData.count) Bytes, Zuschnitt \(crop.strategy.rawValue), Drehung \(crop.rotation)°")
            }
        }

        let text = LabelTextRecognizer.combinedText(sections)
        guard !text.isEmpty else { throw LabelScanError.noTextFound }
        Self.logger.info("OCR: \(text.count) Zeichen erkannt")

        var (extraction, source) = await structure(text: text, cloud: cloud)
        // Speiseempfehlungen nur übernehmen, wenn sie im Etikett-Text belegt sind.
        extraction = Self.verifyingFoodPairings(extraction, against: text)
        // Die Modelle übernehmen den Rückseitentext gern in der Originalsprache.
        if !extraction.notes.isEmpty {
            extraction.notes = await LabelNotesTranslator.germanized(
                extraction.notes,
                aiService: aiService,
                cloud: cloud
            )
        }
        guard extraction.hasContent else { throw LabelScanError.nothingRecognized(text) }
        Self.logger.info("Zuordnung via \(source.displayName)")
        return LabelScanResult(
            extraction: extraction,
            recognizedText: text,
            source: source,
            labelImageData: labelImageData,
            backLabelImageData: backLabelImageData
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

    /// Verwirft Speiseempfehlungen, für die es im erkannten Text keinen Beleg gibt.
    ///
    /// Ein Modell neigt dazu, aus Rebsorte und Region eine Empfehlung abzuleiten. Die App
    /// behauptet aber „laut Etikett“, also muss das Etikett es auch hergeben. Als Beleg
    /// dient der wörtlich kopierte Abschnitt; er muss sich im erkannten Text wiederfinden.
    static func verifyingFoodPairings(_ extraction: WineLabelExtraction, against recognizedText: String) -> WineLabelExtraction {
        guard !extraction.foodPairings.isEmpty else { return extraction }
        var checked = extraction
        guard isSupported(extraction.foodPairingSource, by: recognizedText) else {
            Self.logger.info("Speiseempfehlung ohne Beleg im Etikett-Text verworfen: \(extraction.foodPairings.joined(separator: ", "))")
            checked.foodPairings = []
            checked.foodPairingSource = ""
            return checked
        }
        return checked
    }

    /// Der Beleg gilt, wenn genügend seiner Wörter im erkannten Text vorkommen.
    /// Eine exakte Übereinstimmung wäre zu streng, weil die Texterkennung Buchstaben verdreht.
    private static func isSupported(_ source: String, by recognizedText: String) -> Bool {
        let haystack = normalized(recognizedText)
        let words = normalized(source)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 }
        guard words.count >= 2 else { return false }
        let found = words.filter { haystack.contains($0) }.count
        return Double(found) / Double(words.count) >= 0.6
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de"))
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
        if merged.foodPairingSource.isEmpty { merged.foodPairingSource = fallback.foodPairingSource }
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
