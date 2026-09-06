import CoreData
import Foundation
import OSLog
import SQLite3

/// Einmalige Übernahme der Daten aus der früheren SwiftData-Ablage.
///
/// Gelesen wird die SQLite-Datei direkt, nicht über SwiftData. Grund: SwiftData besteht
/// beim Öffnen auf einem exakt passenden Modell und versucht sonst zu migrieren, was in
/// der App fehlschlägt. Der direkte Weg kommt ohne SwiftData-Abhängigkeit aus und arbeitet
/// auf einer Kopie, der Originalspeicher wird nie verändert.
enum LegacyImporter {

    private static let logger = Logger(subsystem: "com.weinkeller.app", category: "LegacyImport")
    private static let doneKey = "legacyImport.completed"

    /// Ergebnis der Übernahme, damit die App den Nutzer informieren kann.
    struct Result: Equatable {
        let importedCount: Int
    }

    /// Übernimmt einmalig alle Flaschen aus der SwiftData-Ablage.
    /// Läuft danach nie wieder, auch wenn nichts gefunden wurde.
    @MainActor
    @discardableResult
    static func importIfNeeded(into context: NSManagedObjectContext, defaults: UserDefaults = .standard) -> Result? {
        guard !defaults.bool(forKey: doneKey) else { return nil }
        defer { defaults.set(true, forKey: doneKey) }

        guard let storeURL = legacyStoreURL(), FileManager.default.fileExists(atPath: storeURL.path) else {
            logger.info("Keine frühere Ablage gefunden.")
            return nil
        }

        let rows = readRows(from: storeURL)
        guard !rows.isEmpty else {
            logger.info("Frühere Ablage enthält keine Flaschen.")
            return nil
        }

        let cellar = Cellar.findOrCreateDefault(in: context)
        for row in rows {
            let wine = Wine.create(
                in: context,
                cellar: cellar,
                name: row.string("ZNAME"),
                producer: row.string("ZPRODUCER"),
                vintage: row.int("ZVINTAGE"),
                grape: row.string("ZGRAPE"),
                region: row.string("ZREGION"),
                country: row.string("ZCOUNTRY"),
                type: WineType(rawValue: row.string("ZTYPE")) ?? .red,
                quantity: row.int("ZQUANTITY"),
                notes: row.string("ZNOTES"),
                foodPairings: row.stringArray("ZFOODPAIRINGS"),
                labelImageData: row.externalData("ZLABELIMAGEDATA", storeURL: storeURL),
                isArchived: row.int("ZISARCHIVED") != 0,
                createdAt: row.date("ZCREATEDAT") ?? .now
            )
            // Bereits ermittelte Koordinaten mitnehmen, spart erneutes Nachschlagen.
            let precision = row.string("ZGEOCODEPRECISION")
            if !precision.isEmpty {
                wine.geocodedQuery = row.string("ZGEOCODEDQUERY")
                wine.geocodedPlaceName = row.string("ZGEOCODEDPLACENAME")
                wine.geocodePrecision = precision
                wine.setValue(row.double("ZLATITUDE"), forKey: "latitude")
                wine.setValue(row.double("ZLONGITUDE"), forKey: "longitude")
            }
        }
        context.saveChanges()
        logger.info("\(rows.count) Flaschen aus der früheren Ablage übernommen.")
        return Result(importedCount: rows.count)
    }

    /// SwiftData legt die Datei standardmässig als „default.store“ in Application Support ab.
    private static func legacyStoreURL() -> URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("default.store")
    }

    // MARK: SQLite lesen

    /// Eine Zeile als Spaltenname → Wert.
    struct Row {
        let values: [String: Any]

        func string(_ column: String) -> String { values[column] as? String ?? "" }
        func int(_ column: String) -> Int { values[column] as? Int ?? 0 }
        func double(_ column: String) -> Double { values[column] as? Double ?? 0 }

        /// Core Data speichert Datumswerte als Sekunden seit dem 1.1.2001.
        func date(_ column: String) -> Date? {
            guard let seconds = values[column] as? Double else { return nil }
            return Date(timeIntervalSinceReferenceDate: seconds)
        }

        /// SwiftData legt `[String]` als Keyed Archive ab.
        func stringArray(_ column: String) -> [String] {
            guard let data = values[column] as? Data, !data.isEmpty else { return [] }
            let classes = [NSArray.self, NSString.self]
            let unarchived = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: classes, from: data)
            return (unarchived as? [String]) ?? []
        }

        /// Grosse Binärwerte liegen als eigene Datei neben der Datenbank; der Wert in der
        /// Tabelle enthält dann nur den Dateinamen.
        func externalData(_ column: String, storeURL: URL) -> Data? {
            guard let data = values[column] as? Data, !data.isEmpty else { return nil }
            guard let reference = String(data: data, encoding: .ascii),
                  let uuid = firstUUID(in: reference) else {
                return data      // kleiner Wert, direkt in der Tabelle
            }
            let external = storeURL
                .deletingLastPathComponent()
                .appendingPathComponent(".\(storeURL.deletingPathExtension().lastPathComponent)_SUPPORT")
                .appendingPathComponent("_EXTERNAL_DATA")
                .appendingPathComponent(uuid)
            return try? Data(contentsOf: external)
        }

        private func firstUUID(in text: String) -> String? {
            let pattern = "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }

    /// Liest alle Zeilen der Tabelle ZWINE. Arbeitet auf einer Kopie, damit die
    /// ursprüngliche Ablage unangetastet bleibt.
    private static func readRows(from storeURL: URL) -> [Row] {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("legacy-import-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: tempDirectory) }

        do {
            try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            // Auch Journal-Dateien kopieren, sonst fehlen die zuletzt geschriebenen Daten.
            for suffix in ["", "-wal", "-shm"] {
                let source = URL(fileURLWithPath: storeURL.path + suffix)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                try fileManager.copyItem(
                    at: source,
                    to: tempDirectory.appendingPathComponent(source.lastPathComponent)
                )
            }
        } catch {
            logger.error("Kopie der früheren Ablage fehlgeschlagen: \(error.localizedDescription)")
            return []
        }

        let copyURL = tempDirectory.appendingPathComponent(storeURL.lastPathComponent)
        var database: OpaquePointer?
        guard sqlite3_open(copyURL.path, &database) == SQLITE_OK else {
            logger.error("Frühere Ablage liess sich nicht öffnen.")
            sqlite3_close(database)
            return []
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT * FROM ZWINE", -1, &statement, nil) == SQLITE_OK else {
            logger.info("Tabelle ZWINE nicht vorhanden.")
            return []
        }
        defer { sqlite3_finalize(statement) }

        var rows: [Row] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var values: [String: Any] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                guard let nameC = sqlite3_column_name(statement, index) else { continue }
                let name = String(cString: nameC)
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER:
                    values[name] = Int(sqlite3_column_int64(statement, index))
                case SQLITE_FLOAT:
                    values[name] = sqlite3_column_double(statement, index)
                case SQLITE_TEXT:
                    if let text = sqlite3_column_text(statement, index) {
                        values[name] = String(cString: text)
                    }
                case SQLITE_BLOB:
                    let length = Int(sqlite3_column_bytes(statement, index))
                    if let bytes = sqlite3_column_blob(statement, index), length > 0 {
                        values[name] = Data(bytes: bytes, count: length)
                    }
                default:
                    break
                }
            }
            rows.append(Row(values: values))
        }
        return rows
    }
}
