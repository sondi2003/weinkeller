import Testing
@testable import Wyychaellerli

/// Doppelte Flaschen erkennen.
///
/// Die Schwellen sind an echten Fällen gewählt; diese Tests halten sie fest. Wer sie
/// verschiebt, sieht sofort, welcher Fall dadurch kippt.
struct DuplicateFinderTests {

    private func candidate(_ name: String, _ producer: String = "", _ vintage: Int = 2020) -> DuplicateFinder.Candidate {
        DuplicateFinder.Candidate(name: name, producer: producer, vintage: vintage)
    }

    @Test("Erkennungsfehler im Namen trifft trotzdem")
    func typo() {
        // Fehlender Akzent aus der Texterkennung – dieselbe Flasche.
        let score = DuplicateFinder.similarity(candidate("La Pinède"), candidate("La Pinede"))
        #expect(score != nil)
    }

    @Test("Ein Zusatz macht einen anderen Wein")
    func riserva() {
        // „Riserva“ ist ein eigener Wein, kein Tippfehler.
        let score = DuplicateFinder.similarity(
            candidate("Chianti Classico"),
            candidate("Chianti Classico Riserva")
        )
        #expect(score == nil)
    }

    @Test("Verschiedene Jahrgänge sind verschiedene Flaschen")
    func differentVintage() {
        let score = DuplicateFinder.similarity(candidate("Barolo", "", 2018), candidate("Barolo", "", 2019))
        #expect(score == nil)
    }

    @Test("Gleicher Name, anderer Produzent – nicht dieselbe Flasche")
    func differentProducer() {
        let score = DuplicateFinder.similarity(
            candidate("Pinot Noir", "Weingut Müller"),
            candidate("Pinot Noir", "Domaine Dupont")
        )
        #expect(score == nil)
    }

    @Test("Identische Angaben ergeben volle Ähnlichkeit")
    func identical() throws {
        let score = try #require(DuplicateFinder.similarity(candidate("Barolo", "Conterno"), candidate("Barolo", "Conterno")))
        #expect(score > 0.99)
    }

    @Test("Ohne Namen wird nichts verglichen")
    func emptyName() {
        #expect(DuplicateFinder.similarity(candidate(""), candidate("Barolo")) == nil)
    }

    @Test("Normalisierung entfernt Akzente und Gross/Klein")
    func normalization() {
        #expect(DuplicateFinder.normalized("La Pinède") == DuplicateFinder.normalized("LA PINEDE"))
    }

    @Test("Ähnlichkeit zweier Zeichenketten")
    func ratio() {
        #expect(DuplicateFinder.ratio("barolo", "barolo") == 1.0)
        #expect(DuplicateFinder.ratio("barolo", "barolp") > 0.8)
        #expect(DuplicateFinder.ratio("barolo", "sushi") < 0.5)
    }

    @Test("Der Keller wird durchsucht, Archiv eingeschlossen")
    @MainActor
    func findsInArchive() {
        let context = TestStack.makeContext()
        TestStack.makeWine(in: context, name: "Barolo Riserva", producer: "Conterno", vintage: 2018, isArchived: true)

        let matches = DuplicateFinder.findDuplicates(
            of: candidate("Barolo Riserva", "Conterno", 2018),
            in: context
        )
        // Genau dafür ist die Suche da: Man scannt neu und weiss nicht mehr,
        // dass die Flasche schon im Archiv liegt.
        #expect(matches.count == 1)
        #expect(matches.first?.wine.name == "Barolo Riserva")
    }

    @Test("Der eigene Eintrag zählt beim Bearbeiten nicht als Duplikat")
    @MainActor
    func excludesSelf() {
        let context = TestStack.makeContext()
        let wine = TestStack.makeWine(in: context, name: "Barolo", producer: "Conterno", vintage: 2018)

        let matches = DuplicateFinder.findDuplicates(
            of: candidate("Barolo", "Conterno", 2018),
            in: context,
            excluding: wine
        )
        #expect(matches.isEmpty)
    }
}
