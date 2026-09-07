import CoreData
import SwiftUI

/// Das Regal: ansehen, einräumen, Fach räumen.
///
/// Der Einstieg beim Einräumen ist bewusst das **Fach**, nicht der Wein. So läuft es
/// auch in echt: Man steht vor dem Regal, hat eine Flasche in der Hand und sucht ein
/// freies Fach. Der umgekehrte Weg – vom Wein aus einräumen – kommt auf der Detailseite.
struct RackView: View {

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: true)],
        animation: .default
    )
    private var racks: FetchedResults<Rack>

    @State private var isEditingRack = false
    /// Freies Fach, für das gerade ein Wein gewählt wird.
    @State private var fillingPosition: Position?
    /// Belegtes Fach, das gerade angetippt wurde.
    @State private var selectedSlot: Slot?
    @State private var mergeResult: String?

    private var rack: Rack? { Rack.preferred(from: Array(racks), in: context) }

    var body: some View {
        NavigationStack {
            Group {
                if let rack {
                    content(rack)
                } else {
                    ContentUnavailableView {
                        Label("Noch kein Regal", systemImage: "square.grid.3x3")
                    } description: {
                        // Hinweis auf den Abgleich: Wer hier vorschnell anlegt, hat gleich
                        // zwei Regale, sobald das erste über iCloud eintrifft.
                        Text("Lege dein Regal an, dann kannst du deine Flaschen darin einräumen und später wiederfinden.\n\nHast du auf einem anderen Gerät schon eines eingerichtet, warte kurz – es kommt über iCloud von selbst.")
                    } actions: {
                        Button("Regal anlegen") { createRack() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle(rack?.name ?? "Regal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
                if rack != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Bearbeiten") { isEditingRack = true }
                    }
                }
            }
            .sheet(isPresented: $isEditingRack) {
                if let rack { RackEditorView(rack: rack) }
            }
            .sheet(item: $fillingPosition) { position in
                if let rack { SlotFillerView(rack: rack, position: position) }
            }
            .confirmationDialog(
                selectedSlot?.wine?.name ?? "",
                isPresented: Binding(
                    get: { selectedSlot != nil },
                    set: { if !$0 { selectedSlot = nil } }
                ),
                titleVisibility: .visible,
                presenting: selectedSlot
            ) { slot in
                Button("Fach räumen") { clear(slot) }
                Button("Abbrechen", role: .cancel) { }
            } message: { slot in
                Text("Fach \(slot.position.label). „Fach räumen“ nimmt die Flasche nur aus dem Regal, der Bestand bleibt gleich.")
            }
        }
    }

    // MARK: Inhalt

    private func content(_ rack: Rack) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                Text(summary(rack))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    RackGridView(
                        rows: rack.rowCount,
                        columns: rack.columnCount,
                        occupancy: rack.occupancy(),
                        tile: tileSize(for: rack)
                    ) { position in
                        tapped(position, in: rack)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                }

                if duplicateCount > 0 {
                    duplicateCard
                }

                if unplacedWines.isEmpty {
                    Label("Alle Flaschen sind eingeräumt.", systemImage: "checkmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    unplacedSection
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private var unplacedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Noch nicht im Regal")
                .font(.headline)
            Text("Tippe auf ein freies Fach, um eine dieser Flaschen einzuräumen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(unplacedWines) { wine in
                UnplacedWineRow(wine: wine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    /// Mehrere Regale für denselben Keller – entstanden, wenn auf zwei Geräten angelegt
    /// wurde, bevor das erste eingetroffen war.
    private var duplicateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Mehrere Regale gefunden", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(duplicateCount == 1
                 ? "Es gibt ein zweites Regal für diesen Keller. Das passiert, wenn auf einem anderen Gerät eines angelegt wurde, bevor deines dort ankam."
                 : "Es gibt \(duplicateCount) weitere Regale für diesen Keller. Das passiert, wenn auf anderen Geräten eines angelegt wurde, bevor deines dort ankam.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                merge()
            } label: {
                Label("Regale zusammenführen", systemImage: "arrow.triangle.merge")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            if let mergeResult {
                Text(mergeResult)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: Daten

    private var duplicateCount: Int {
        guard let cellar = Cellar.current(in: context) else { return 0 }
        return max(0, Rack.all(in: context, for: cellar).count - 1)
    }

    private func merge() {
        guard let cellar = Cellar.current(in: context) else { return }
        let result = Rack.mergeDuplicates(in: context, for: cellar)
        mergeResult = result.released == 0
            ? "\(result.moved) Fächer übernommen."
            : "\(result.moved) Fächer übernommen, \(result.released) Flaschen aus dem Regal genommen, weil das Fach schon belegt war. Der Bestand ist unverändert."
    }

    /// Weine mit Bestand, von denen noch nicht jede Flasche einen Platz hat.
    private var unplacedWines: [Wine] {
        let request = Wine.fetchRequest()
        request.predicate = NSPredicate(format: "isArchived == NO AND quantity > 0")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return ((try? context.fetch(request)) ?? []).filter { $0.canPlaceAnotherBottle }
    }

    private func summary(_ rack: Rack) -> String {
        let used = rack.usedCount
        let capacity = rack.capacity
        let free = rack.freeCount
        return "\(used) von \(capacity) Fächern belegt · \(free) frei"
    }

    /// Kleinere Fächer, sobald das Regal breit wird, damit möglichst viel aufs Bild passt.
    private func tileSize(for rack: Rack) -> CGFloat {
        switch rack.columnCount {
        case ...6:  return 52
        case 7...10: return 44
        case 11...14: return 38
        default: return 32
        }
    }

    private func tapped(_ position: Position, in rack: Rack) {
        if let slot = rack.occupancy()[position] {
            selectedSlot = slot
        } else {
            fillingPosition = position
        }
    }

    private func createRack() {
        Rack.findOrCreate(in: context, cellar: Cellar.active(in: context))
    }

    /// Nimmt die Flasche aus dem Fach, ohne den Bestand zu ändern.
    private func clear(_ slot: Slot) {
        context.delete(slot)
        context.saveChanges()
        selectedSlot = nil
    }
}

// MARK: - Zeile eines noch nicht eingeräumten Weins

/// Eigene kleine Ansicht mit `@ObservedObject`.
///
/// Ohne die Beobachtung bleibt die Zahl der freien Flaschen stehen, sobald man eine
/// einräumt: Es ändert sich nur eine **Beziehung** des Weins, und SwiftUI hätte keinen
/// Anlass, die Zeile neu zu zeichnen.
private struct UnplacedWineRow: View {

    @ObservedObject var wine: Wine

    var body: some View {
        HStack(spacing: 10) {
            LabelThumbnail(wine: wine, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(wine.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(wine.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("\(wine.unplacedCount)×")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Position als Sheet-Auslöser

extension Position: Identifiable {
    var id: String { "\(row)-\(column)" }
}
