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
    /// Kantenlänge eines Fachs.
    var tile: CGFloat = 44
    var onTap: ((Position) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private let spacing: CGFloat = 6

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
        .onAppear {
            guard !reduceMotion, !highlighted.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    @ViewBuilder
    private func cell(at position: Position) -> some View {
        let slot = occupancy[position]
        let isHighlighted = highlighted.contains(position)
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)

        Button {
            onTap?(position)
        } label: {
            ZStack {
                shape.fill(fill(for: slot, highlighted: isHighlighted))
                shape.strokeBorder(border(for: slot, highlighted: isHighlighted), lineWidth: isHighlighted ? 2 : 1)
                if let slot, let wine = slot.wine {
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
        guard let wine = slot?.wine else { return "Fach \(position.label), frei" }
        return "Fach \(position.label), \(wine.name)"
    }
}

#Preview {
    RackGridView(rows: 3, columns: 6, occupancy: [:], highlighted: [Position(row: 1, column: 2)])
        .padding()
}
