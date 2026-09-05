import SwiftUI
import UIKit

// MARK: - Farben pro Weintyp

extension WineType {
    /// Charakterfarbe für Badges, Icons und Akzente.
    var color: Color {
        switch self {
        case .red:       return Color(red: 0.48, green: 0.11, blue: 0.20)   // Bordeaux
        case .white:     return Color(red: 0.80, green: 0.66, blue: 0.24)   // Strohgelb
        case .sparkling: return Color(red: 0.33, green: 0.58, blue: 0.64)   // kühles Petrol
        case .rose:      return Color(red: 0.89, green: 0.45, blue: 0.56)   // Rosé
        }
    }
}

// MARK: - Etikett-Bild

extension Wine {
    /// Dekodiertes Etikett-Foto, falls eines gespeichert ist.
    var labelImage: UIImage? {
        labelImageData.flatMap(UIImage.init(data:))
    }
}

/// Kleines Etikett-Vorschaubild für Listen und Cards; fällt auf das Typ-Icon zurück.
struct LabelThumbnail: View {
    let wine: Wine
    var size: CGFloat = 44

    var body: some View {
        if let image = wine.labelImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size * 1.25)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                .accessibilityHidden(true)
        } else {
            WineTypeIcon(type: wine.type, size: size)
        }
    }
}

// MARK: - Wiederverwendbare Bausteine

/// Rundes Icon mit Typfarbe – in Listen, Cards und Detailansichten.
struct WineTypeIcon: View {
    let type: WineType
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle()
                .fill(type.color.opacity(0.15))
            Image(systemName: type.symbolName)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(type.color)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Bestandsanzeige: "3" in einer Kapsel, bei 0 rot "Leer".
struct StockBadge: View {
    let quantity: Int

    var body: some View {
        Group {
            if quantity > 0 {
                Text("\(quantity)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
            } else {
                Text("Leer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(quantity > 0 ? Color(.tertiarySystemFill) : Color.red)
        )
        .accessibilityLabel(quantity > 0 ? "\(quantity) Flaschen" : "Keine Flaschen")
    }
}

/// Hinweisbox (Info, Warnung, Fehler) mit Icon.
struct CalloutBox: View {
    enum Kind {
        case info, warning, error

        var color: Color {
            switch self {
            case .info:    return .accentColor
            case .warning: return .orange
            case .error:   return .red
            }
        }

        var symbol: String {
            switch self {
            case .info:    return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error:   return "xmark.octagon.fill"
            }
        }
    }

    let kind: Kind
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: kind.symbol)
                .foregroundStyle(kind.color)
                .padding(.top, 1)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(kind.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Karten-Hintergrund für Cards außerhalb von Listen.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardBackground()) }
}
