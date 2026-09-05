import Foundation

/// Baut System- und User-Prompts. Die Texte sind für alle drei Anbieter identisch –
/// nur die Verpackung (Request-Body) unterscheidet sich und liegt in den jeweiligen Clients.
enum PromptBuilder {

    // MARK: Wein-Empfehlung

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
        und Textur des Gerichts. Nutze dafür auch Rebsorte, Region und Notizen (Terroir, \
        Vinifikation) aus dem Inventar. Nenne ruhig auch, was nicht perfekt passt.
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

    // MARK: Etikett-Erkennung

    /// Anweisungen für die Zuordnung von OCR-Text zu Feldern – identisch für
    /// Apple Intelligence (auf dem Gerät) und die Cloud-Anbieter.
    static let labelSystemPrompt = """
        Du liest Weinetiketten. Du bekommst den per Texterkennung ausgelesenen Text von \
        Vorder- und Rückseite einer Flasche – oft mit Erkennungsfehlern, Zeilenumbrüchen \
        an falschen Stellen und in Französisch, Italienisch, Spanisch, Deutsch oder Englisch.

        Ordne den Text den Feldern zu:
        - name: Name des Weins oder der Cuvée, ohne Produzent (z. B. "La Pinède"). Wenn es \
        keinen eigenen Namen gibt, nimm die Appellation oder Rebsorte als Name.
        - producer: Weingut, Domaine, Château, Cantina, Bodega, Weingut …
        - vintage: Jahrgang als Zahl, 0 wenn keiner erkennbar ist.
        - grape: Rebsorten kommagetrennt (z. B. "Grenache noir, Mourvèdre, Carignan"). \
        Nicht raten – nur, was auf dem Etikett steht oder aus der Appellation zwingend folgt.
        - region: Region oder Appellation (z. B. "Collioure", "Mosel", "Barolo").
        - type: red, white, sparkling, rose oder unknown. Hinweise: "rouge/red/rosso/tinto" = red, \
        "blanc/white/bianco/blanco/weiss" = white, "rosé/rosato/rosado" = rose, \
        "brut/champagne/crémant/prosecco/spumante/sekt/cava/mousseux" = sparkling.
        - alcoholPercent: Volumenprozent als Zahl, 0 wenn unbekannt.
        - notes: In ein bis zwei deutschen Sätzen, was für das Pairing wichtig ist: Terroir \
        (z. B. Schiefer), Vinifikation, Ausbau, Stil. Leer, wenn nichts dazu steht.

        Erfinde nichts. Unbekannte Felder bleiben leer bzw. 0.
        """

    static func labelUserPrompt(recognizedText: String) -> String {
        """
        Erkannter Etikett-Text:
        ---
        \(recognizedText)
        ---
        Bitte ordne den Text den Feldern zu.
        """
    }
}
