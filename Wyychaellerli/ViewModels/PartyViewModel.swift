import CoreData
import Foundation
import Observation

/// Führt durch die Abstimmung: Flaschen wählen, Gäste erfassen, reihum abstimmen,
/// auswerten, Podest. Jede Änderung wird sofort gesichert (siehe `PartyState`).
@Observable
@MainActor
final class PartyViewModel {

    private(set) var state: PartyState
    /// Die Weine zu den Kennungen – bei jedem Laden frisch aufgelöst.
    private(set) var candidates: [Wine] = []

    /// Läuft gerade eine Auslosung? Steuert das Aufleuchten der Flaschen.
    var drawHighlight: UUID?
    private(set) var isDrawing = false

    init(state: PartyState = PartyState()) {
        self.state = state
    }

    /// Stellt eine unterbrochene Party wieder her, falls eine gesichert ist.
    static func restored(in context: NSManagedObjectContext) -> PartyViewModel? {
        guard let state = PartyState.restore() else { return nil }
        let model = PartyViewModel(state: state)
        model.resolveCandidates(in: context)
        return model
    }

    // MARK: Kandidaten

    /// Nur echte Kandidaten: im Keller, nicht archiviert, mindestens eine Flasche da.
    static func selectableWines(in context: NSManagedObjectContext) -> [Wine] {
        let request = Wine.fetchRequest()
        request.predicate = NSPredicate(format: "isArchived == NO AND quantity > 0")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    func isSelected(_ wine: Wine) -> Bool {
        wine.uuid.map { state.candidateIDs.contains($0) } ?? false
    }

    func toggleCandidate(_ wine: Wine) {
        guard let id = wine.uuid else { return }
        if let index = state.candidateIDs.firstIndex(of: id) {
            state.candidateIDs.remove(at: index)
        } else {
            state.candidateIDs.append(id)
        }
        // Die Stimmenzahl folgt der Zahl der Flaschen, ohne Zutun.
        state.votesPerGuest = PartyState.votesPerGuest(forCandidates: state.candidateIDs.count)
        persist()
    }

    /// Weine zu den gespeicherten Kennungen holen. Fehlt einer (gelöscht), fällt er weg.
    func resolveCandidates(in context: NSManagedObjectContext) {
        let all = Self.selectableWines(in: context) + Self.archivedOrEmpty(in: context)
        let byID = Dictionary(all.compactMap { wine in wine.uuid.map { ($0, wine) } },
                              uniquingKeysWith: { first, _ in first })
        let resolved = state.candidateIDs.compactMap { byID[$0] }
        if resolved.count != state.candidateIDs.count {
            state.candidateIDs = resolved.compactMap(\.uuid)
            persist()
        }
        candidates = resolved
    }

    /// Auch Weine ohne Bestand nachschlagen: Während der Party kann die letzte Flasche
    /// abgebucht worden sein – der Kandidat soll trotzdem im Podest stehen.
    private static func archivedOrEmpty(in context: NSManagedObjectContext) -> [Wine] {
        let request = Wine.fetchRequest()
        request.predicate = NSPredicate(format: "isArchived == YES OR quantity <= 0")
        return (try? context.fetch(request)) ?? []
    }

    func wine(for id: UUID) -> Wine? {
        candidates.first { $0.uuid == id }
    }

    var canStartGuests: Bool { state.candidateIDs.count >= 2 }

    func goToGuests(in context: NSManagedObjectContext) {
        resolveCandidates(in: context)
        state.votesPerGuest = PartyState.votesPerGuest(forCandidates: state.candidateIDs.count)
        state.phase = .guests
        persist()
    }

    func backToCandidates() {
        state.phase = .candidates
        persist()
    }

    // MARK: Gäste

    /// Fügt einen Gast hinzu – vor dem Start und mitten in der Runde (Nachzügler).
    func addGuest(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state.guests.append(PartyState.Guest(id: UUID(), name: trimmed, votes: nil))
        persist()
    }

    func removeGuest(_ guest: PartyState.Guest) {
        state.guests.removeAll { $0.id == guest.id }
        if state.currentGuestID == guest.id { state.currentGuestID = nil }
        persist()
    }

    var canStartVoting: Bool { !state.guests.isEmpty && state.candidateIDs.count >= 2 }

    /// Startet die Runde beim ersten Gast.
    func startVoting() {
        state.currentGuestID = state.pendingGuests.first?.id
        state.phase = .handover
        persist()
    }

    // MARK: Abstimmen

    /// Der Gast hat das Gerät übernommen – ab jetzt sieht er die Flaschen.
    func beginTurn() {
        guard state.currentGuestID != nil else { return }
        state.phase = .voting
        persist()
    }

    var remainingVotes: Int {
        max(0, state.votesPerGuest - state.currentVotes.count)
    }

    func hasVoted(for id: UUID) -> Bool {
        state.currentVotes.contains(id)
    }

    /// Stimme geben oder zurücknehmen. Höchstens eine Stimme je Flasche, damit niemand
    /// alles auf eine Karte setzt.
    func toggleVote(for id: UUID) {
        guard let index = state.guests.firstIndex(where: { $0.id == state.currentGuestID }) else { return }
        var votes = state.guests[index].votes ?? []
        if let existing = votes.firstIndex(of: id) {
            votes.remove(at: existing)
        } else {
            guard votes.count < state.votesPerGuest else { return }
            votes.append(id)
        }
        state.guests[index].votes = votes
        persist()
    }

    /// Der Gast ist fertig – weiter zum nächsten oder zur Auswertung.
    func finishTurn() {
        guard let index = state.guests.firstIndex(where: { $0.id == state.currentGuestID }) else { return }
        // Ohne diese Zeile bliebe ein Gast „offen“, der bewusst keine Stimme vergibt.
        if state.guests[index].votes == nil { state.guests[index].votes = [] }
        advance()
    }

    /// Aussetzen: Der Gast ist gerade nicht am Tisch und bleibt offen.
    func skipTurn() {
        guard let current = state.currentGuestID,
              let index = state.guests.firstIndex(where: { $0.id == current }) else { return }
        // Angefangene Stimmen verwerfen, sonst zählt eine halbe Wahl mit.
        state.guests[index].votes = nil
        let pending = state.pendingGuests
        let next = pending.first { $0.id != current } ?? pending.first
        state.currentGuestID = next?.id
        state.phase = .handover
        persist()
    }

    private func advance() {
        if let next = state.pendingGuests.first {
            state.currentGuestID = next.id
            state.phase = .handover
        } else {
            state.currentGuestID = nil
            evaluate()
        }
        persist()
    }

    /// Alle offenen Gäste überspringen und sofort auswerten.
    func evaluateNow() {
        state.currentGuestID = nil
        evaluate()
        persist()
    }

    var hasAnyVote: Bool { state.totalVotes > 0 }

    // MARK: Auswertung

    private func evaluate() {
        let leaders = state.leaders()
        if leaders.count == 1 {
            state.winnerID = leaders[0]
            state.wasDrawn = false
            state.phase = .podium
        } else if leaders.count > 1 {
            // Gleichstand an der Spitze: Das Los entscheidet, sichtbar für alle.
            state.winnerID = nil
            state.phase = .draw
        } else {
            // Niemand hat gestimmt – zurück zur Runde statt ein leeres Podest zu zeigen.
            state.phase = .guests
        }
    }

    /// Auslosung: Die gleichauf liegenden Flaschen leuchten der Reihe nach auf, immer
    /// langsamer, bis eine übrig bleibt.
    func runDraw() async {
        let leaders = state.leaders()
        guard leaders.count > 1, !isDrawing else { return }
        isDrawing = true
        defer { isDrawing = false }

        let winner = leaders.randomElement() ?? leaders[0]
        var delay: Double = 0.08
        var index = 0
        // Erst schnell rundum, dann auslaufen lassen – wie ein Glücksrad.
        while delay < 0.55 {
            drawHighlight = leaders[index % leaders.count]
            try? await Task.sleep(for: .seconds(delay))
            index += 1
            delay *= 1.18
        }
        // Auf dem Gewinner stehen bleiben.
        while drawHighlight != winner {
            drawHighlight = leaders[index % leaders.count]
            try? await Task.sleep(for: .seconds(0.55))
            index += 1
        }
        try? await Task.sleep(for: .seconds(0.6))

        state.winnerID = winner
        state.wasDrawn = true
        state.phase = .podium
        persist()
    }

    var winner: Wine? { state.winnerID.flatMap(wine(for:)) }

    /// Podest: höchstens die ersten drei, Flaschen ohne Stimme fallen weg.
    func podium() -> [(wine: Wine, votes: Int)] {
        state.ranking()
            .filter { $0.votes > 0 }
            .prefix(3)
            .compactMap { entry in wine(for: entry.id).map { ($0, entry.votes) } }
    }

    // MARK: Abschluss

    /// Ergebnis in die Historie schreiben. Einmal pro Party.
    func recordResult(in context: NSManagedObjectContext) {
        guard let winner, let winnerID = state.winnerID else { return }
        let votes = state.tally()[winnerID] ?? 0
        PartyWin.record(
            title: state.title,
            wine: winner,
            votes: votes,
            totalVotes: state.totalVotes,
            guestCount: state.guests.filter(\.hasVoted).count,
            candidateCount: state.candidateIDs.count,
            wasDrawn: state.wasDrawn,
            in: context
        )
    }

    func setTitle(_ title: String) {
        state.title = title
        persist()
    }

    /// Alles verwerfen – der Party-Modus ist beendet.
    func discard() {
        PartyState.clear()
    }

    private func persist() {
        state.save()
    }
}
