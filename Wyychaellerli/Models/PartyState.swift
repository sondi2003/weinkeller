import Foundation

/// Der Stand einer laufenden Abstimmung.
///
/// Bewusst ein einfacher `Codable`-Wert und **nicht** Core Data: Der Ablauf gehört zu
/// diesem einen Gerät, das gerade herumgereicht wird. Nichts davon soll über iCloud auf
/// andere Geräte wandern – nur das Ergebnis (`PartyWin`) wird später gespeichert.
///
/// Gesichert wird nach jeder Änderung in `UserDefaults`. Wischt ein Gast die App weg
/// oder stürzt sie ab, ist der Abend nicht verloren – und der gesperrte Modus ist beim
/// nächsten Start sofort wieder da, statt den ganzen Keller freizugeben.
struct PartyState: Codable, Equatable {

    enum Phase: String, Codable {
        /// Der Gastgeber wählt die Flaschen, die zur Wahl stehen.
        case candidates
        /// Namen der Anwesenden erfassen.
        case guests
        /// „Bitte an Peter weitergeben“ – Zwischenschirm, damit niemand die Wahl des
        /// Vorgängers sieht.
        case handover
        /// Der aktuelle Gast vergibt seine Stimmen.
        case voting
        /// Gleichstand an der Spitze: Das Los entscheidet.
        case draw
        /// Podest.
        case podium
    }

    struct Guest: Codable, Equatable, Identifiable {
        let id: UUID
        var name: String
        /// `nil`, solange dieser Gast noch nicht abgestimmt hat.
        var votes: [UUID]?

        var hasVoted: Bool { votes != nil }
    }

    var phase: Phase = .candidates
    /// Anlass für die Erinnerung: „Silvester“. Leer = Datum.
    var title: String = ""
    /// Kennungen der Weine, die zur Wahl stehen.
    var candidateIDs: [UUID] = []
    var guests: [Guest] = []
    /// Wer gerade das Gerät in der Hand hat.
    var currentGuestID: UUID?
    /// Stimmen pro Gast – ergibt sich aus der Zahl der Flaschen.
    var votesPerGuest: Int = 3
    var startedAt: Date = .now
    /// Ergebnis, sobald es feststeht: Kennung der Siegerflasche.
    var winnerID: UUID?
    /// `true`, wenn das Los entschieden hat.
    var wasDrawn: Bool = false

    // MARK: Regeln

    /// Wie viele Stimmen bei dieser Zahl von Flaschen sinnvoll sind.
    ///
    /// Drei Stimmen bei drei Flaschen wären sinnlos – jeder gäbe jeder eine. Es müssen
    /// immer weniger Stimmen als Flaschen sein, damit eine Wahl entsteht.
    static func votesPerGuest(forCandidates count: Int) -> Int {
        switch count {
        case ...2:  return 1
        case 3...4: return 2
        default:    return 3
        }
    }

    /// Gäste, die noch nicht abgestimmt haben – in Reihenfolge der Erfassung.
    var pendingGuests: [Guest] { guests.filter { !$0.hasVoted } }

    var currentGuest: Guest? {
        currentGuestID.flatMap { id in guests.first { $0.id == id } }
    }

    /// Stimmen des aktuellen Gasts, solange er dran ist.
    var currentVotes: [UUID] { currentGuest?.votes ?? [] }

    /// Summe aller abgegebenen Stimmen je Wein.
    func tally() -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        for guest in guests {
            for vote in guest.votes ?? [] {
                result[vote, default: 0] += 1
            }
        }
        return result
    }

    /// Rangliste, beste zuerst. Flaschen ohne Stimme sind mit 0 dabei.
    func ranking() -> [(id: UUID, votes: Int)] {
        let counts = tally()
        return candidateIDs
            .map { (id: $0, votes: counts[$0] ?? 0) }
            .sorted { $0.votes > $1.votes }
    }

    /// Alle Flaschen, die an der Spitze gleichauf liegen. Eine = klarer Sieger.
    func leaders() -> [UUID] {
        let ranked = ranking()
        guard let top = ranked.first?.votes, top > 0 else { return [] }
        return ranked.filter { $0.votes == top }.map(\.id)
    }

    var totalVotes: Int { guests.reduce(0) { $0 + ($1.votes?.count ?? 0) } }

    // MARK: Sichern

    private static let storageKey = "party.state"

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    static func restore(from defaults: UserDefaults = .standard) -> PartyState? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(PartyState.self, from: data)
    }

    static func clear(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }
}
