import Foundation

/// Prüft, ob ein Gericht direkt zu den Speiseempfehlungen auf dem Etikett passt.
///
/// Bewusst nur ein Wortabgleich, keine Bedeutungsanalyse: „Raclette“ trifft „Raclette“,
/// „Lammbraten“ trifft „Lamm“. Dass „Lasagne“ zu „Pasta“ gehört, erkennt nur die KI –
/// dafür ist dieser Abgleich kostenlos, offline und sofort.
enum LabelPairingMatcher {

    /// Kürzere Begriffe führen zu Zufallstreffern („Ei“ in „Eintopf“).
    private static let minimumTermLength = 4

    /// Liefert die Etikett-Begriffe, die zum Gericht passen. Leer = kein direkter Treffer.
    static func matchingTerms(dish: String, pairings: [String]) -> [String] {
        let dishNormalized = normalized(dish)
        guard dishNormalized.count >= minimumTermLength else { return [] }
        let dishWords = dishNormalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= minimumTermLength }

        return pairings.filter { pairing in
            let term = normalized(pairing)
            guard term.count >= minimumTermLength else { return false }
            // Etikett-Begriff steht im Gericht („Lamm“ in „Lammbraten“)
            if dishNormalized.contains(term) { return true }
            // Oder ein Wort des Gerichts steht im Etikett-Begriff („Fisch“ in „Fisch und Meeresfrüchte“)
            return dishWords.contains { term.contains($0) }
        }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
