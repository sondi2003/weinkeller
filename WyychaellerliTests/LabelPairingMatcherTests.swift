import Testing
@testable import Wyychaellerli

/// Der Abgleich zwischen Gericht und den Speiseempfehlungen vom Etikett.
///
/// Er entscheidet, ob der Wein-Berater ohne KI-Anfrage auskommt. Ein Fehltreffer
/// wäre schlimmer als kein Treffer: Die App behauptete dann etwas übers Etikett,
/// das dort nicht steht.
struct LabelPairingMatcherTests {

    @Test("Etikett-Begriff steckt im Gericht")
    func termInDish() {
        // Steht „Lamm“ auf dem Etikett, trifft es „Lammbraten“.
        let hits = LabelPairingMatcher.matchingTerms(dish: "Lammbraten", pairings: ["Lamm", "Fisch"])
        #expect(hits == ["Lamm"])
    }

    @Test("Grenze: zwei verschiedene Zusammensetzungen treffen sich nicht")
    func compoundWordsDoNotMatch() {
        // „Lammfleisch“ und „Lammbraten“ haben denselben Stamm, aber keines steckt im
        // anderen – der Abgleich vergleicht ganze Zeichenketten, nicht Wortstämme.
        // Festgehalten als bekannte Grenze, nicht als gewünschtes Verhalten.
        let hits = LabelPairingMatcher.matchingTerms(dish: "Lammbraten", pairings: ["Lammfleisch"])
        #expect(hits.isEmpty)
    }

    @Test("Wort des Gerichts steckt im Etikett-Begriff")
    func dishWordInTerm() {
        let hits = LabelPairingMatcher.matchingTerms(
            dish: "Gegrillter Fisch",
            pairings: ["Fisch und Meeresfrüchte", "Rindfleisch"]
        )
        #expect(hits == ["Fisch und Meeresfrüchte"])
    }

    @Test("Genaue Übereinstimmung")
    func exact() {
        #expect(LabelPairingMatcher.matchingTerms(dish: "Raclette", pairings: ["Raclette"]) == ["Raclette"])
    }

    @Test("Akzente und Gross/Klein sind egal")
    func folding() {
        let hits = LabelPairingMatcher.matchingTerms(dish: "PÂTÉ", pairings: ["Pate"])
        #expect(hits == ["Pate"])
    }

    @Test("Kurze Begriffe treffen nicht – sonst gäbe es Zufallstreffer")
    func tooShort() {
        // „Ei“ steckt in „Eintopf“, meint aber etwas anderes.
        #expect(LabelPairingMatcher.matchingTerms(dish: "Eintopf", pairings: ["Ei"]).isEmpty)
        #expect(LabelPairingMatcher.matchingTerms(dish: "Ei", pairings: ["Eintopf"]).isEmpty)
    }

    @Test("Was nicht passt, trifft nicht")
    func noMatch() {
        #expect(LabelPairingMatcher.matchingTerms(dish: "Sushi", pairings: ["Rindfleisch", "Käse"]).isEmpty)
    }

    @Test("Ohne Empfehlungen gibt es nichts zu treffen")
    func empty() {
        #expect(LabelPairingMatcher.matchingTerms(dish: "Raclette", pairings: []).isEmpty)
    }

    @Test("Mehrere Treffer kommen alle zurück")
    func multiple() {
        let hits = LabelPairingMatcher.matchingTerms(
            dish: "Rindfleisch mit Käse",
            pairings: ["Rindfleisch", "Käseplatte", "Fisch"]
        )
        #expect(hits.count == 2)
    }
}
