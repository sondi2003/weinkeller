import Foundation

/// Baut System- und User-Prompt für die Wein-Empfehlung.
/// Die Texte sind für alle drei Anbieter identisch – nur die Verpackung
/// (Request-Body) unterscheidet sich und liegt in den jeweiligen Clients.
enum PromptBuilder {

    /// Rolle, Regeln und Ausgabeformat. Wird als `system` / `system_instruction` übergeben.
    static func systemPrompt(maxRecommendations: Int) -> String {
        """
        Du bist ein erfahrener Sommelier und berätst einen privaten Weinkeller.

        Deine Aufgabe: Zu einem beschriebenen Gericht die passendsten Weine auswählen – \
        ausschließlich aus dem übergebenen Inventar.

        Regeln:
        1. Empfiehl nur Weine, die im Inventar stehen und deren Bestand größer als 0 ist. \
        Erfinde keine Weine und ändere keine Namen oder Jahrgänge.
        2. Gib maximal \(maxRecommendations) Empfehlungen zurück, sortiert nach Eignung \
        (rank 1 = beste Wahl). Wenn weniger Weine sinnvoll passen, gib weniger zurück – \
        mindestens aber eine, sofern das Inventar nicht leer ist.
        3. `wineName` und `vintage` müssen exakt dem Inventar-Eintrag entsprechen, damit die \
        App die Flasche wiederfindet.
        4. Begründe jede Empfehlung konkret anhand von Aromen, Säure, Tannin, Körper, Süße \
        und Textur des Gerichts. Nenne dabei ruhig auch, was nicht perfekt passt.
        5. Gib zu jeder Empfehlung einen kurzen Serviertipp (Trinktemperatur, Dekantieren, Glas).
        6. In `generalNote` erklärst du in ein bis drei Sätzen die Gesamtlogik – und falls der \
        klassische Pairing-Partner im Keller fehlt, sagst du das offen.
        7. Antworte auf Deutsch, in einem freundlichen, aber fachlich präzisen Ton.
        """
    }

    /// Das Gericht plus Inventar als eingebettetes JSON.
    static func userPrompt(for request: PairingRequest) -> String {
        """
        Geplantes Gericht: \(request.dish)

        Aktuelles Inventar (JSON):
        \(inventoryJSON(request.inventory))

        Bitte wähle die besten Weine aus diesem Inventar für das Gericht aus.
        """
    }

    /// Inventar als sortiertes, gut lesbares JSON – stabil sortiert, damit der Prompt
    /// bei gleichem Inventar identisch bleibt (hilfreich fürs Debugging und Caching).
    static func inventoryJSON(_ inventory: [WineInventoryItem]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let sorted = inventory.sorted {
            ($0.type, $0.name, $0.vintage) < ($1.type, $1.name, $1.vintage)
        }
        guard let data = try? encoder.encode(sorted),
              let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }
}
