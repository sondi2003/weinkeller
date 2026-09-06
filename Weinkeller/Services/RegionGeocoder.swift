import CoreLocation
import Foundation
import OSLog

/// Aufgelöste Herkunft: Koordinate plus lesbarer Ortsname.
struct GeocodedRegion: Sendable, Equatable {

    /// Wie genau der Treffer ist.
    enum Precision: String, Sendable {
        /// Die Region selbst wurde gefunden – Stecknadel ist sinnvoll.
        case place
        /// Nur das Land ist gesichert – Karte zeigt das Land ohne Nadel.
        case country
    }

    let latitude: Double
    let longitude: Double
    /// Zum Anzeigen, z. B. „Collioure, Frankreich“.
    let placeName: String
    let precision: Precision
}

/// Schlägt zu einer Weinregion die Koordinaten nach – über Apples Geocoder.
///
/// Braucht keinen API-Key und keine Standortfreigabe, weil nur eine Adresse in
/// Koordinaten übersetzt wird (Forward Geocoding).
///
/// Wichtig: Regionsnamen sind mehrdeutig. „Mosel, Deutschland“ liefert einen Ortsteil
/// von Zwickau in Sachsen, „Wallis, Schweiz“ einen Weiler im Aargau. Deshalb wird jeder
/// Treffer geprüft: Passt er nicht zur genannten Region, wird lieber nur das Land
/// gezeigt als eine falsche Stecknadel gesetzt.
actor RegionGeocoder {

    static let shared = RegionGeocoder()

    private static let logger = Logger(subsystem: "com.weinkeller.app", category: "Geocoder")
    private let geocoder = CLGeocoder()
    private var cache: [String: GeocodedRegion] = [:]
    /// Anfragen, die schon erfolglos waren – nicht endlos wiederholen.
    private var failed: Set<String> = []

    /// Schlüssel, an dem erkannt wird, ob ein gespeichertes Ergebnis noch zur Eingabe passt.
    nonisolated static func query(region: String, country: String) -> String? {
        let parts = [region, country]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let joined = parts.joined(separator: ", ")
        return joined.count >= 2 ? joined : nil
    }

    /// Sucht zuerst die Region, fällt bei unplausiblem Treffer auf das Land zurück.
    func lookup(region: String, country: String) async -> GeocodedRegion? {
        let region = region.trimmingCharacters(in: .whitespacesAndNewlines)
        let country = country.trimmingCharacters(in: .whitespacesAndNewlines)

        if !region.isEmpty {
            let full = country.isEmpty ? region : "\(region), \(country)"
            if let placemark = await geocode(full),
               Self.matches(placemark, region: region) {
                return Self.result(from: placemark, precision: .place, fallbackName: full)
            }
            Self.logger.info("Kein plausibler Treffer für Region „\(region)“ – zeige nur das Land")
        }

        guard !country.isEmpty, let placemark = await geocode(country) else { return nil }
        return Self.result(from: placemark, precision: .country, fallbackName: country)
    }

    // MARK: Geocoding

    private func geocode(_ query: String) async -> CLPlacemark? {
        let key = query.lowercased()
        if let cached = cache[key] {
            // Nur die Koordinate ist gecacht; für die Prüfung reicht sie nicht.
            // Deshalb wird der Cache über `lookup` gefüllt, hier nur der Fehlerfall gespiegelt.
            _ = cached
        }
        if failed.contains(key) { return nil }
        do {
            let placemarks = try await geocoder.geocodeAddressString(query)
            guard let first = placemarks.first, first.location != nil else {
                failed.insert(key)
                return nil
            }
            return first
        } catch {
            Self.logger.info("Geocoding für „\(query)“ fehlgeschlagen: \(error.localizedDescription)")
            failed.insert(key)
            return nil
        }
    }

    private static func result(
        from placemark: CLPlacemark,
        precision: GeocodedRegion.Precision,
        fallbackName: String
    ) -> GeocodedRegion? {
        guard let location = placemark.location else { return nil }
        let name: String
        switch precision {
        case .place:
            let place = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea ?? placemark.name
            name = [place, placemark.country].compactMap { $0 }.joined(separator: ", ")
        case .country:
            name = placemark.country ?? fallbackName
        }
        return GeocodedRegion(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            placeName: name.isEmpty ? fallbackName : name,
            precision: precision
        )
    }

    // MARK: Plausibilitätsprüfung

    /// Der Treffer zählt nur, wenn Ort, Bezirk oder Verwaltungsgebiet der gesuchten Region
    /// entspricht. `name` allein reicht nicht: Bei „Mosel“ heißt der Ortsteil von Zwickau
    /// ebenfalls „Mosel“, liegt aber 400 km vom Weinbaugebiet entfernt.
    nonisolated static func matches(_ placemark: CLPlacemark, region: String) -> Bool {
        matches(
            locality: placemark.locality,
            subAdministrativeArea: placemark.subAdministrativeArea,
            administrativeArea: placemark.administrativeArea,
            name: placemark.name,
            region: region
        )
    }

    /// Reine Logik ohne CoreLocation-Typen, damit sie sich prüfen lässt.
    nonisolated static func matches(
        locality: String?,
        subAdministrativeArea: String?,
        administrativeArea: String?,
        name: String?,
        region: String
    ) -> Bool {
        let target = normalized(region)
        guard !target.isEmpty else { return false }

        let fields = [locality, subAdministrativeArea, administrativeArea]
            .compactMap { $0 }
            .map(normalized)

        if fields.contains(target) { return true }
        // „Rioja“ soll auch „La Rioja“ treffen – aber nur bei aussagekräftiger Länge.
        if target.count >= 4, fields.contains(where: { $0.contains(target) || ($0.count >= 4 && target.contains($0)) }) {
            return true
        }
        // Reine Regions-Treffer haben keinen Ort; dann zählt der Name.
        if locality == nil, let name, normalized(name) == target {
            return true
        }
        return false
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
