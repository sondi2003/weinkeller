import CoreData
import SwiftUI

/// Was an welchem Abend gewonnen hat.
///
/// Die Einträge sind Kopien: Name und Etikett stehen darin, nicht als Verweis auf den
/// Wein. Die Flasche von Silvester ist längst leer – die Erinnerung bleibt trotzdem.
struct PartyHistoryView: View {

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)],
        animation: .default
    )
    private var fetched: FetchedResults<PartyWin>

    /// Nur die Ergebnisse **dieses** Kellers.
    ///
    /// Auf dem Gerät der eingeladenen Person liegen ein leerer eigener und der geteilte
    /// Keller nebeneinander – ungefiltert stünden dort zwei Historien durcheinander.
    private var wins: [PartyWin] {
        guard let cellar = Cellar.current(in: context) else { return Array(fetched) }
        return fetched.filter { $0.cellar == cellar }
    }

    var body: some View {
        NavigationStack {
            Group {
                if wins.isEmpty {
                    ContentUnavailableView {
                        Label("Noch keine Party", systemImage: "party.popper")
                    } description: {
                        Text("Wenn deine Gäste abgestimmt haben, steht die Siegerflasche hier – mit Anlass, Datum und Stimmen. Die Historie gehört zum Keller und ist auf allen Geräten gleich.")
                    }
                } else {
                    List {
                        ForEach(wins) { win in
                            row(win)
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Party-Historie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }

    private func row(_ win: PartyWin) -> some View {
        HStack(spacing: 12) {
            if let image = win.labelImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 55)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 44, height: 55)
                    .overlay { Image(systemName: "trophy").foregroundStyle(.secondary) }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(win.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let date = win.date {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(win.wineName)
                    .font(.subheadline)
                    .lineLimit(1)
                if !win.wineSubtitle.isEmpty {
                    Text(win.wineSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("\(win.resultText) · \(win.guestCount) \(win.guestCount == 1 ? "Gast" : "Gäste") · \(win.candidateCount) zur Wahl")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(wins[index])
        }
        context.saveChanges()
    }
}
