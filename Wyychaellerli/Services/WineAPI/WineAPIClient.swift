import Foundation
import os

/// Zugang zu wineapi.io – Bewertungen, Beschreibung, Preise und Speiseempfehlungen
/// aus dem Netz, zusätzlich zu dem, was auf dem Etikett steht.
///
/// Zwei Schritte: `POST /identify/text` findet den Wein anhand unserer Angaben
/// (Name, Weingut, Jahrgang …), `GET /wines/{id}` liefert das Profil. Kennt der Dienst
/// den Wein noch nicht, legt er ihn an und ergänzt ihn im Hintergrund; die Antwort trägt
/// dann `X-Update-Status: pending`, und wir fragen nach `Retry-After` nochmals nach.
///
/// Der Free-Tarif erlaubt 100 Anfragen am Tag – ein Nachschlagen kostet zwei bis vier.
struct WineAPIClient: Sendable {

    static let baseURL = URL(string: "https://api.wineapi.io")!
    /// Kontoname in der Keychain.
    static let keychainAccount = "wineapi"

    private static let logger = Logger(subsystem: "com.weinkeller.app", category: "WineAPI")

    private let apiKey: String
    private let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    /// Der hinterlegte Key, falls einer da ist.
    static var storedKey: String? {
        KeychainStore.string(for: keychainAccount).flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: Nachschlagen

    /// Sucht den Wein und holt sein Profil. Wartet begrenzt auf die Ergänzung im Hintergrund.
    func lookup(query: String) async throws -> WineAPIProfile {
        let identification = try await identify(query: query)
        guard let id = identification.wineID else {
            throw WineAPIError.notFound
        }
        var profile = try await profile(id: id)
        profile.matchConfidence = identification.confidence
        return profile
    }

    /// Holt das Profil erneut, etwa wenn die Ergänzung beim ersten Mal noch lief.
    func profile(id: String) async throws -> WineAPIProfile {
        var attempt = 0
        while true {
            attempt += 1
            let (data, http) = try await get(path: "/wines/\(id)")
            var profile = try decode(WineAPIProfile.self, from: data)
            profile.id = id
            let pending = http.value(forHTTPHeaderField: "X-Update-Status")?.lowercased() == "pending"
            profile.isPending = pending
            // Höchstens zweimal nachfassen, und nie länger als 15 s je Wartezeit. Wer
            // länger will, tippt später auf „Aktualisieren“.
            guard pending, attempt < 3 else { return profile }
            let retryAfter = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 8
            let wait = min(max(retryAfter, 3), 15)
            Self.logger.info("Profil \(id) wird noch ergänzt – warte \(wait, format: .fixed(precision: 0)) s")
            try await Task.sleep(for: .seconds(wait))
        }
    }

    // MARK: Einzelne Aufrufe

    private struct Identification {
        let wineID: String?
        let confidence: Double?
    }

    private func identify(query: String) async throws -> Identification {
        var request = URLRequest(url: Self.baseURL.appending(path: "/identify/text"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        let (data, _) = try await send(request)

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WineAPIError.decoding("Antwort auf die Identifikation ist kein JSON.")
        }
        let confidence = object["confidence"] as? Double
        if let wine = object["wine"] as? [String: Any], let id = wine["id"] as? String {
            return Identification(wineID: id, confidence: confidence)
        }
        // Kein sicherer Treffer, aber Vorschläge: den ersten nehmen. Die Karte zeigt
        // die Sicherheit an, damit man einen Fehlgriff erkennt.
        if let suggestions = object["suggestions"] as? [[String: Any]],
           let first = suggestions.first, let id = first["id"] as? String {
            return Identification(wineID: id, confidence: (first["confidence"] as? Double) ?? confidence)
        }
        return Identification(wineID: nil, confidence: confidence)
    }

    private func get(path: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: Self.baseURL.appending(path: path))
        request.httpMethod = "GET"
        request.timeoutInterval = 60
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard !apiKey.isEmpty else { throw WineAPIError.missingKey }
        var request = request
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw WineAPIError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw WineAPIError.network("Keine HTTP-Antwort erhalten.")
        }
        switch http.statusCode {
        case 200..<300: return (data, http)
        case 401, 403: throw WineAPIError.invalidKey
        case 404: throw WineAPIError.notFound
        case 429: throw WineAPIError.rateLimited
        default:
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw WineAPIError.http(status: http.statusCode, message: message ?? "")
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw WineAPIError.decoding(error.localizedDescription)
        }
    }
}

// MARK: - Fehler

enum WineAPIError: LocalizedError {
    case missingKey
    case invalidKey
    case rateLimited
    case notFound
    case http(status: Int, message: String)
    case decoding(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "Für WineAPI ist kein Key hinterlegt. Bitte in den Einstellungen eintragen."
        case .invalidKey:
            return "WineAPI hat den Key abgelehnt. Bitte den Key in den Einstellungen prüfen."
        case .rateLimited:
            return "Das Tageskontingent bei WineAPI ist aufgebraucht. Es wird um Mitternacht (UTC) erneuert."
        case .notFound:
            return "WineAPI kennt diesen Wein nicht."
        case .http(let status, let message):
            return "WineAPI hat mit HTTP \(status) geantwortet." + (message.isEmpty ? "" : " \(message)")
        case .decoding(let detail):
            return "Die Antwort von WineAPI konnte nicht gelesen werden: \(detail)"
        case .network(let detail):
            return "Netzwerkfehler: \(detail)"
        }
    }
}
