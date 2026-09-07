import CoreData
import SwiftUI

/// Einmalige Nachübersetzung bestehender Notizen.
///
/// Bewusst mit Rückfrage: Der Durchlauf **ersetzt** vorhandenen Text im ganzen Keller und
/// lässt sich nicht rückgängig machen. Deshalb wird zuerst gezählt und die Zahl genannt,
/// bevor irgendetwas geschrieben wird.
struct NotesMigrationSection: View {

    @Environment(\.managedObjectContext) private var context

    private enum Phase: Equatable {
        case idle
        case working
        case nothingToDo
        case done(translated: Int, notPossible: Int)
    }

    @State private var phase: Phase = .idle
    @State private var pending: [NotesMigration.Candidate] = []
    @State private var isConfirming = false

    var body: some View {
        Section {
            Button {
                pending = NotesMigration.candidates(in: context)
                if pending.isEmpty {
                    phase = .nothingToDo
                } else {
                    isConfirming = true
                }
            } label: {
                HStack {
                    Label("Notizen auf Deutsch übersetzen", systemImage: "character.book.closed")
                    if phase == .working {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(phase == .working)

            switch phase {
            case .nothingToDo:
                resultRow("Alle Notizen sind bereits auf Deutsch.", symbol: "checkmark.circle.fill", tint: .green)
            case .done(let translated, let notPossible):
                if translated > 0 {
                    resultRow(
                        translated == 1 ? "1 Notiz übersetzt." : "\(translated) Notizen übersetzt.",
                        symbol: "checkmark.circle.fill",
                        tint: .green
                    )
                }
                if notPossible > 0 {
                    resultRow(
                        notPossible == 1
                        ? "1 Notiz blieb stehen – für diese Sprache fehlt das Paket auf dem Gerät."
                        : "\(notPossible) Notizen blieben stehen – für diese Sprachen fehlt das Paket auf dem Gerät.",
                        symbol: "exclamationmark.triangle.fill",
                        tint: .orange
                    )
                }
            case .idle, .working:
                EmptyView()
            }
        } header: {
            Text("Notizen")
        } footer: {
            Text("Für Weine, die vor der automatischen Übersetzung erfasst wurden. Läuft ausschliesslich auf diesem Gerät, ohne Anfrage an einen KI-Anbieter und ohne Kosten. Archivierte Weine sind eingeschlossen.")
        }
        .confirmationDialog(
            pending.count == 1
            ? "1 Notiz ist nicht auf Deutsch."
            : "\(pending.count) Notizen sind nicht auf Deutsch.",
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button("Übersetzen") { run() }
            Button("Abbrechen", role: .cancel) { pending = [] }
        } message: {
            Text("Der bisherige Text wird durch die Übersetzung ersetzt. Das lässt sich nicht rückgängig machen.")
        }
    }

    private func resultRow(_ text: String, symbol: String, tint: Color) -> some View {
        Label {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint)
        }
    }

    private func run() {
        phase = .working
        let candidates = pending
        pending = []
        Task {
            let summary = await NotesMigration.translate(candidates, in: context)
            phase = .done(translated: summary.translated, notPossible: summary.notPossible)
        }
    }
}
