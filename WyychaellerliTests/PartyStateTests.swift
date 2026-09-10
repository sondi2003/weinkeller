import Foundation
import Testing
@testable import Wyychaellerli

/// Die Abstimmung: Stimmenzahl, Auszählung, Gleichstand, Sichern.
///
/// Der Teil, der am Abend funktionieren muss, wenn zwölf Leute am Tisch sitzen –
/// und der sich als Einziger vollständig ohne Oberfläche prüfen lässt.
struct PartyStateTests {

    private func guest(_ name: String, _ votes: [UUID]?) -> PartyState.Guest {
        PartyState.Guest(id: UUID(), name: name, votes: votes)
    }

    @Test("Stimmenzahl folgt der Zahl der Flaschen")
    func votesPerGuest() {
        // Drei Stimmen bei drei Flaschen wären sinnlos: Jeder gäbe jeder eine.
        #expect(PartyState.votesPerGuest(forCandidates: 2) == 1)
        #expect(PartyState.votesPerGuest(forCandidates: 3) == 2)
        #expect(PartyState.votesPerGuest(forCandidates: 4) == 2)
        #expect(PartyState.votesPerGuest(forCandidates: 5) == 3)
        #expect(PartyState.votesPerGuest(forCandidates: 12) == 3)
    }

    @Test("Auszählung und Rangliste")
    func tally() {
        let a = UUID(), b = UUID(), c = UUID()
        var state = PartyState()
        state.candidateIDs = [a, b, c]
        state.guests = [guest("Ines", [a, b]), guest("Peter", [a, c]), guest("Anna", [a, b])]

        #expect(state.tally()[a] == 3)
        #expect(state.tally()[b] == 2)
        #expect(state.tally()[c] == 1)
        #expect(state.ranking().map(\.votes) == [3, 2, 1])
        #expect(state.leaders() == [a])
        #expect(state.totalVotes == 6)
    }

    @Test("Flaschen ohne Stimme stehen mit 0 in der Rangliste")
    func rankingIncludesUnvoted() {
        let a = UUID(), b = UUID()
        var state = PartyState()
        state.candidateIDs = [a, b]
        state.guests = [guest("Ines", [a])]

        #expect(state.ranking().count == 2)
        #expect(state.ranking().last?.votes == 0)
        #expect(state.leaders() == [a])
    }

    @Test("Gleichstand liefert alle Anführer")
    func tie() {
        let a = UUID(), b = UUID(), c = UUID()
        var state = PartyState()
        state.candidateIDs = [a, b, c]
        state.guests = [guest("Ines", [a, b]), guest("Peter", [b, a])]

        #expect(Set(state.leaders()) == Set([a, b]))
        // Die Flasche ohne Stimme darf nie zur Auslosung gehören.
        #expect(!state.leaders().contains(c))
    }

    @Test("Ohne abgegebene Stimme gibt es keinen Sieger")
    func noVotes() {
        let a = UUID()
        var state = PartyState()
        state.candidateIDs = [a]
        state.guests = [guest("Ines", []), guest("Peter", [])]

        #expect(state.leaders().isEmpty)
        #expect(state.totalVotes == 0)
    }

    @Test("Offene Gäste behalten die Reihenfolge der Erfassung")
    func pendingOrder() {
        let a = UUID()
        var state = PartyState()
        state.candidateIDs = [a]
        state.guests = [guest("Ines", [a]), guest("Peter", nil), guest("Anna", nil)]

        #expect(state.pendingGuests.count == 2)
        #expect(state.pendingGuests.map(\.name) == ["Peter", "Anna"])
    }

    @Test("Der Stand übersteht das Sichern und Wiederherstellen")
    func persistence() throws {
        let suite = "party.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let a = UUID()
        var state = PartyState()
        state.phase = .voting
        state.title = "Silvester"
        state.candidateIDs = [a]
        state.guests = [guest("Ines", [a])]
        state.votesPerGuest = 2
        state.save(to: defaults)

        // Wischt ein Gast die App weg, muss genau das zurückkommen.
        let restored = try #require(PartyState.restore(from: defaults))
        #expect(restored.title == "Silvester")
        #expect(restored.phase == .voting)
        #expect(restored.guests.first?.votes == [a])
        #expect(restored.votesPerGuest == 2)

        PartyState.clear(in: defaults)
        #expect(PartyState.restore(from: defaults) == nil)
    }
}
