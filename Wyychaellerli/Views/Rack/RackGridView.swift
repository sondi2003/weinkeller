import SwiftUI

/// Das Regal als Raster.
///
/// Bewusst ein eigener, dummer Baustein ohne Datenzugriff: Dieselbe Darstellung wird
/// später auf der Detailseite eines Weins gebraucht, dort aber nur mit hervorgehobenen
/// Plätzen und ohne Bedienung.
struct RackGridView: View {

    let rows: Int
    let columns: Int
    /// Was in welchem Fach liegt. Fehlt ein Eintrag, ist das Fach frei.
    let occupancy: [Position: Slot]
    /// Diese Plätze werden hervorgehoben und pulsieren.
    var highlighted: Set<Position> = []
    /// Diese Plätze sind ausgewählt (Mehrfachauswahl beim Einräumen).
    var selected: Set<Position> = []
    /// Kantenlänge eines Fachs.
    var tile: CGFloat = 44
    /// Enger, wenn das ganze Regal auf die Breite passen soll.
    var spacing: CGFloat = 6
    var onTap: ((Position) -> Void)?
    /// Wird beim Wischen über ein Fach gemeldet. Nur gesetzt, wenn Wischen erlaubt ist.
    var onDragOver: ((Position) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0..<max(rows, 1), id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<max(columns, 1), id: \.self) { column in
                        cell(at: Position(row: row, column: column))
                    }
                }
            }
        }
        // Wischen über mehrere Fächer. Die Rasterweite ist bekannt, deshalb lässt sich
        // die Position aus dem Berührungspunkt rechnen – zuverlässiger als Treffer je Feld.
        .gesture(dragSelection, isEnabled: onDragOver != nil)
        .onAppear {
            guard !reduceMotion, !highlighted.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var dragSelection: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let step = tile + spacing
                let column = Int(value.location.x / step)
                let row = Int(value.location.y / step)
                guard row >= 0, row < rows, column >= 0, column < columns else { return }
                onDragOver?(Position(row: row, column: column))
            }
    }

    @ViewBuilder
    private func cell(at position: Position) -> some View {
        let slot = occupancy[position]
        let isHighlighted = highlighted.contains(position)
        let isSelected = selected.contains(position)
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)

        Button {
            onTap?(position)
        } label: {
            ZStack {
                shape.fill(isSelected ? Color.accentColor : fill(for: slot, highlighted: isHighlighted))
                shape.strokeBorder(
                    isSelected ? Color.accentColor : border(for: slot, highlighted: isHighlighted),
                    lineWidth: isHighlighted || isSelected ? 2 : 1
                )
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: tile * 0.4, weight: .bold))
                        .foregroundStyle(.white)
                } else if let slot, let wine = slot.wine {
                    Image(systemName: wine.type.symbolName)
                        .font(.system(size: tile * 0.42))
                        .foregroundStyle(isHighlighted ? Color.accentColor : wine.type.color)
                }
            }
            .frame(width: tile, height: tile)
            // Nur der hervorgehobene Platz pulsiert, und nur wenn Bewegung erlaubt ist.
            .scaleEffect(isHighlighted && pulse && !reduceMotion ? 1.09 : 1)
            .shadow(
                color: isHighlighted ? Color.accentColor.opacity(pulse && !reduceMotion ? 0.55 : 0.3) : .clear,
                radius: isHighlighted ? 7 : 0
            )
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        .accessibilityLabel(label(for: position, slot: slot))
    }

    private func fill(for slot: Slot?, highlighted: Bool) -> Color {
        guard let wine = slot?.wine else {
            return highlighted ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill)
        }
        return wine.type.color.opacity(highlighted ? 0.3 : 0.16)
    }

    private func border(for slot: Slot?, highlighted: Bool) -> Color {
        if highlighted { return .accentColor }
        return slot?.wine == nil ? Color.secondary.opacity(0.25) : (slot?.wine?.type.color ?? .secondary).opacity(0.4)
    }

    private func label(for position: Position, slot: Slot?) -> String {
        if selected.contains(position) { return "Fach \(position.label), ausgewählt" }
        guard let wine = slot?.wine else { return "Fach \(position.label), frei" }
        return "Fach \(position.label), \(wine.name)"
    }
}

#Preview {
    RackGridView(rows: 3, columns: 6, occupancy: [:], highlighted: [Position(row: 1, column: 2)])
        .padding()
}
