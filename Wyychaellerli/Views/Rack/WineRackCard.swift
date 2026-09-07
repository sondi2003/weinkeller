import CoreData
import SwiftUI

/// Zeigt auf der Detailseite, wo die Flaschen dieses Weins liegen.
///
/// Der eigentliche Zweck der ganzen Regalfunktion: vor dem Regal stehen und wissen,
/// wohin greifen. Deshalb pulsieren die eigenen Fächer, und ein Tipp darauf entnimmt
/// die Flasche gleich – ohne Umweg über eine zweite Ansicht.
struct WineRackCard: View {

    @ObservedObject var wine: Wine

    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: true)],
        animation: .default
    )
    private var racks: FetchedResults<Rack>

    @State private var pendingSlot: Slot?
    @State private var isPlacing = false

    private var rack: Rack? { Rack.preferred(from: Array(racks), in: context) }

    /// Nur die Fächer im **gezeigten** Regal.
    ///
    /// Solange zwei Regale desselben Kellers nebeneinander liegen, gehören manche Fächer des
    /// Weins zum anderen Regal. Ungefiltert würden deren Positionen hier im falschen Raster
    /// aufleuchten und ins Leere zeigen.
    private func ownSlots(in rack: Rack) -> [Slot] {
        wine.placedSlots.filter { $0.rack == rack }
    }

    var body: some View {
        if let rack, wine.placedCount > 0 || wine.canPlaceAnotherBottle {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Im Regal")
                        .font(.headline)
                    Spacer()
                    Text(status)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !ownSlots(in: rack).isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        RackGridView(
                            rows: rack.rowCount,
                            columns: rack.columnCount,
                            occupancy: rack.occupancy(),
                            highlighted: Set(ownSlots(in: rack).map(\.position)),
                            tile: rack.columnCount > 10 ? 30 : 38
                        ) { position in
                            guard let slot = rack.occupancy()[position], slot.wine == wine else { return }
                            pendingSlot = slot
                        }
                        .padding(.vertical, 6)
                    }
                    Text(positionsLine(in: rack))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if wine.canPlaceAnotherBottle {
                    Button {
                        isPlacing = true
                    } label: {
                        Label(
                            wine.unplacedCount == 1 ? "Flasche einräumen" : "\(wine.unplacedCount) Flaschen einräumen",
                            systemImage: "plus.square.on.square"
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .cardStyle()
            .sheet(isPresented: $isPlacing) {
                WineRackSheet(wine: wine, mode: .place)
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
                Button("Flasche entnehmen") {
                    wine.consumeBottle(from: slot)
                    pendingSlot = nil
                }
                Button("Abbrechen", role: .cancel) { }
            } message: { _ in
                Text("Der Bestand geht um eins runter und das Fach wird frei.")
            }
        }
    }

    private var status: String {
        if wine.placedCount == 0 { return "noch nicht verortet" }
        if wine.unplacedCount == 0 { return "alle verortet" }
        return "\(wine.placedCount) von \(wine.quantity) verortet"
    }

    private func positionsLine(in rack: Rack) -> String {
        let labels = ownSlots(in: rack).map(\.position.label)
        if labels.count == 1 { return "Fach \(labels[0]). Tippen entnimmt die Flasche." }
        return "Fächer \(labels.joined(separator: ", ")). Tippen entnimmt die Flasche."
    }
}
