import Testing
@testable import Wyychaellerli

/// Landesflaggen aus freiem Text.
///
/// Das Land ist ein Textfeld: Der Scanner schreibt Deutsch, im Formular tippt man
/// vielleicht Französisch. Eine falsche Flagge ist schlimmer als keine.
struct CountryFlagTests {

    @Test("Deutsche Ländernamen", arguments: [
        ("Frankreich", "🇫🇷"), ("Italien", "🇮🇹"), ("Spanien", "🇪🇸"),
        ("Schweiz", "🇨🇭"), ("Deutschland", "🇩🇪"), ("Österreich", "🇦🇹"),
        ("Portugal", "🇵🇹"), ("Griechenland", "🇬🇷"), ("Südafrika", "🇿🇦")
    ])
    func german(name: String, flag: String) {
        #expect(CountryFlag.emoji(for: name) == flag)
    }

    @Test("Fremdsprachige Schreibweisen", arguments: [
        ("France", "🇫🇷"), ("Italia", "🇮🇹"), ("Italy", "🇮🇹"),
        ("España", "🇪🇸"), ("Suisse", "🇨🇭"), ("Switzerland", "🇨🇭"),
        ("New Zealand", "🇳🇿"), ("South Africa", "🇿🇦")
    ])
    func foreign(name: String, flag: String) {
        #expect(CountryFlag.emoji(for: name) == flag)
    }

    @Test("Umlaute und Akzente dürfen fehlen", arguments: [
        ("Osterreich", "🇦🇹"), ("Sudafrika", "🇿🇦"), ("Espana", "🇪🇸")
    ])
    func withoutAccents(name: String, flag: String) {
        #expect(CountryFlag.emoji(for: name) == flag)
    }

    @Test("Kurzformen und Weinregionen", arguments: [
        ("USA", "🇺🇸"), ("Kalifornien", "🇺🇸"), ("Wallis", "🇨🇭"),
        ("Toskana", "🇮🇹"), ("Bordeaux", "🇫🇷"), ("Rioja", "🇪🇸")
    ])
    func aliases(name: String, flag: String) {
        #expect(CountryFlag.emoji(for: name) == flag)
    }

    @Test("Leerzeichen und Gross/Klein sind egal")
    func trimming() {
        #expect(CountryFlag.emoji(for: "  frankreich  ") == "🇫🇷")
        #expect(CountryFlag.emoji(for: "FRANKREICH") == "🇫🇷")
    }

    @Test("Unbekanntes gibt keine Flagge – nie eine falsche", arguments: [
        "", "   ", "Weinland", "Rotwein", "12345"
    ])
    func unknown(name: String) {
        #expect(CountryFlag.emoji(for: name) == nil)
    }
}
