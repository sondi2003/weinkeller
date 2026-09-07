import CoreData
import SwiftUI

/// Das Regal für **einen** Wein: entweder eine Flasche entnehmen oder eine einräumen.
///
/// Dieselbe Darstellung für beides, weil es dieselbe Frage ist – welches Fach? Nur die
/// bedienbaren Fächer unterscheiden sich: beim Entnehmen die eigenen, beim Einräumen
/// die freien. Alle übrigen bleiben sichtbar, damit man sich im Regal zurechtfindet,
/// sind aber nicht antippbar.
struct WineRackSheet: View {

    enum Mode {
        case take
        case place

        var title: String {
            switch self {
            case .take:  return "Flasche entnehmen"
            case .place: return "Flasche einräumen"
            }
        }

        var hint: String {
            switch self {
            case .take:  return "Tippe auf das Fach, aus dem du die Flasche nimmst. Der Bestand geht um eins runter und das Fach wird frei."
            case .place: return "Tippe auf ein freies Fach, um die Flasche dort abzulegen."
            }
        }
    }

    @ObservedObject var wine: Wine
    let mode: Mode

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: true)],
        animation: .default
    )
    private var racks: FetchedResults<Rack>

    @State private var pendingSlot: Slot?

    private var rack: Rack? { racks.first }

    var body: some View {
        NavigationStack {
            Group {
                if let rack {
                    content(rack)
                } else {
                    ContentUnavailableView(
                        "Noch kein Regal",
                        systemImage: "square.grid.3x3",
                        description: Text("Lege zuerst ein Regal an, dann kannst du Flaschen darin verorten.")
                    )
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .confirmationDialog(
                pendingSlot.map { "Fach \($0.position.label)" } ?? "",
                isPresented: Binding(
                    get: { pendingSlot != nil },
                    set: { if !$0 { pendingSlot = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingSlot
            ) { slot in
                Button("Flasche entnehmen") { take(slot) }
                Button("Abbrechen", role: .cancel) { }
            } message: { _ in
                Text("Der Bestand von „\(wine.name)“ geht um eins runter.")
            }
        }
    }

    private func content(_ rack: Rack) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(mode.hint)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                ScrollView(.horizontal, showsIndicators: false) {
                    RackGridView(
                        rows: rack.rowCount,
                        columns: rack.columnCount,
                        occupancy: rack.occupancy(),
                        highlighted: highlighted(in: rack),
                        tile: rack.columnCount > 10 ? 40 : 50
                    ) { position in
                        tapped(position, in: rack)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                }

                if mode == .take, !wine.placedSlots.isEmpty {
                    Text(wine.placedSlots.count == 1
                         ? "Diese Flasche liegt in Fach \(wine.placedSlots[0].position.label)."
                         : "Fächer: \(wine.placedSlots.map(\.position.label).joined(separator: ", "))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if mode == .place, rack.freeCount == 0 {
                    Label("Das Regal ist voll.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: Bedienung

    private func highlighted(in rack: Rack) -> Set<Position> {
        switch mode {
        case .take:
            return Set(wine.placedSlots.map(\.position))
        case .place:
            let taken = Set(rack.placedSlots.map(\.position))
            var free: Set<Position> = []
            for row in 0..<rack.rowCount {
                for column in 0..<rack.columnCount {
                    let position = Position(row: row, column: column)
                    if !taken.contains(position) { free.insert(position) }
                }
            }
            return free
        }
    }

    private func tapped(_ position: Position, in rack: Rack) {
        switch mode {
        case .take:
            // Nur die eigenen Fächer reagieren.
            guard let slot = rack.occupancy()[position], slot.wine == wine else { return }
            pendingSlot = slot
        case .place:
            guard rack.occupancy()[position] == nil, wine.canPlaceAnotherBottle else { return }
            Slot.place(wine, at: position, in: rack, context: context)
            dismiss()
        }
    }

    private func take(_ slot: Slot) {
        wine.consumeBottle(from: slot)
        pendingSlot = nil
        dismiss()
    }
}
