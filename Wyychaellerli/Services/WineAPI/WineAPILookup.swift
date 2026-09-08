import CoreData
import Foundation
import os

/// Verbindet WineAPI mit dem Wein: Anfrage bauen, Profil holen, ins Deutsche bringen,
/// am Wein speichern. Läuft auf dem Hauptakteur, weil am Ende Core Data schreibt.
@MainActor
enum WineAPILookup {

    private static let logger = Logger(subsystem: "com.weinkeller.app", category: "WineAPI")

    /// Was `identify/text` bekommt – alles, was wir über die Flasche wissen, in einer Zeile.
    static func query(for wine: Wine) -> String {
        var parts: [String] = []
        if !wine.producer.isEmpty { parts.append(wine.producer) }
        parts.append(wine.name)
        if wine.vintage > 0 { parts.append(String(wine.vintage)) }
        if !wine.grape.isEmpty { parts.append(wine.grape) }
        if !wine.region.isEmpty { parts.append(wine.region) }
        if !wine.country.isEmpty { parts.append(wine.country) }
        return parts.joined(separator: ", ")
    }

    /// Schlägt den Wein nach und speichert das Ergebnis. Bei erneutem Aufruf mit
    /// bekannter WineAPI-Kennung wird nur das Profil aufgefrischt – spart die Suche.
    static func refresh(_ wine: Wine, aiService: AIService, context: NSManagedObjectContext) async throws -> WineAPIProfile {
        guard let key = WineAPIClient.storedKey else { throw WineAPIError.missingKey }
        let client = WineAPIClient(apiKey: key)

        var profile: WineAPIProfile
        if !wine.wineAPIWineID.isEmpty {
            profile = try await client.profile(id: wine.wineAPIWineID)
            profile.matchConfidence = wine.wineAPIProfile?.matchConfidence
        } else {
            profile = try await client.lookup(query: query(for: wine))
        }

        await germanize(&profile, aiService: aiService)

        wine.wineAPIWineID = profile.id ?? ""
        wine.wineAPIProfileJSON = profile.encodedJSON()
        wine.wineAPIPairings = profile.displayPairings
        wine.wineAPIFetchedAt = .now
        context.saveChanges()
        logger.info("WineAPI-Profil gespeichert für „\(wine.name)“ (Sicherheit \(profile.matchConfidence ?? -1))")
        return profile
    }

    /// Vergisst das Profil, etwa nach einer Korrektur der Weindaten.
    static func forget(_ wine: Wine, context: NSManagedObjectContext) {
        wine.wineAPIWineID = ""
        wine.wineAPIProfileJSON = ""
        wine.wineAPIPairings = []
        wine.wineAPIFetchedAt = nil
        context.saveChanges()
    }

    // MARK: Übersetzung

    /// Beschreibung und Speiseempfehlungen auf Deutsch – auf dem Gerät, ohne Kosten.
    /// Ist das Sprachpaket nicht installiert, bleibt das Original stehen.
    private static func germanize(_ profile: inout WineAPIProfile, aiService: AIService) async {
        if let description = profile.description, !description.isEmpty {
            let german = await LabelNotesTranslator.germanized(description, aiService: aiService, cloud: nil)
            if german != description { profile.descriptionGerman = german }
        }
        let foods = (profile.pairings ?? []).map(\.food)
        guard !foods.isEmpty else { return }
        // Als eine Zeile übersetzen: Einzelne Begriffe sind zu kurz für die Spracherkennung.
        let separator = " ; "
        let joined = foods.joined(separator: separator)
        let german = await LabelNotesTranslator.germanized(joined, aiService: aiService, cloud: nil)
        guard german != joined else { return }
        let parts = german.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        // Nur übernehmen, wenn die Übersetzung die Liste nicht zerlegt oder verschmolzen hat.
        if parts.count == foods.count, parts.allSatisfy({ !$0.isEmpty }) {
            profile.pairingsGerman = parts
        }
    }
}

// MARK: - Zugriff am Wein

extension Wine {

    /// Das gespeicherte Profil, falls schon nachgeschlagen.
    var wineAPIProfile: WineAPIProfile? {
        WineAPIProfile.decoded(from: wineAPIProfileJSON)
    }

    /// Speiseempfehlungen von WineAPI, eine je Zeile – für den Wein-Berater.
    var wineAPIPairings: [String] {
        get {
            wineAPIPairingsRaw
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        set { wineAPIPairingsRaw = newValue.joined(separator: "\n") }
    }

    /// Etikett und WineAPI zusammen, ohne Doppelte – das, worin der Berater sucht.
    var allPairings: [String] {
        var seen = Set<String>()
        return (foodPairings + wineAPIPairings).filter { seen.insert($0.lowercased()).inserted }
    }
}
