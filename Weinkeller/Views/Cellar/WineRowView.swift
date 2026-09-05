import SwiftUI

/// Eine Zeile in der Kellerliste: Icon, Name, Jahrgang/Region, Bestand und Minus-Button.
struct WineRowView: View {

    let wine: Wine
    let onConsume: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            LabelThumbnail(wine: wine, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(wine.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(wine.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            StockBadge(quantity: wine.quantity)

            if !wine.isArchived {
                Button(action: onConsume) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(wine.isOutOfStock ? Color.secondary.opacity(0.4) : Color.accentColor)
                }
                .buttonStyle(.borderless)
                .disabled(wine.isOutOfStock)
                .accessibilityLabel("Eine Flasche \(wine.name) trinken")
            }
        }
        .padding(.vertical, 4)
        .opacity(wine.isOutOfStock && !wine.isArchived ? 0.6 : 1)
        .contentTransition(.numericText())
        .animation(.snappy, value: wine.quantity)
    }
}

#Preview {
    List {
        WineRowView(wine: PreviewData.sampleWines[0]) { }
        WineRowView(wine: PreviewData.sampleWines[3]) { }
    }
    .modelContainer(PreviewData.container)
}
