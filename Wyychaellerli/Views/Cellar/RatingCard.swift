import SwiftUI

/// Bewertungen zu einem Wein: gemeinsames Ergebnis, wer schon bewertet hat, Kaufhinweis.
///
/// Die Einzelbewertungen stehen bewusst neben dem Mittelwert. Ein Durchschnitt allein
/// verwischt, ob sich beide einig waren oder ob einer begeistert und einer enttäuscht war.
struct RatingCard: View {

    @ObservedObject var wine: Wine
    @Environment(CurrentRater.self) private var rater

    /// Wird getippt, um den eigenen Bogen zu öffnen.
    let onRate: () -> Void

    /// Die eigene Bewertung, sofern schon Sterne vergeben wurden.
    private var ownRating: Rating? {
        guard let rating = wine.rating(by: rater.identifier), rating.stars > 0 else { return nil }
        return rating
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Bewertung")
                    .font(.headline)
                Spacer()
                if let average = wine.averageRating {
                    Text("\(average.formatted(.number.precision(.fractionLength(0...1)))) von 5")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if wine.ratingList.isEmpty {
                Text("Noch niemand hat diesen Wein bewertet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(wine.ratingList) { rating in
                    personRow(rating)
                }
                buyAgainRow
            }

            if rater.name.isEmpty {
                Label("Trage in den Einstellungen deinen Namen ein, damit man sieht, von wem die Bewertung stammt.", systemImage: "person.crop.circle.badge.questionmark")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            Button(action: onRate) {
                Label(
                    ownRating == nil ? "Jetzt bewerten" : "Meine Bewertung ändern",
                    systemImage: ownRating == nil ? "star" : "square.and.pencil"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
        }
        .cardStyle()
    }

    private func personRow(_ rating: Rating) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(rating.displayName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                StarRatingView(value: .constant(rating.stars), isEditable: false, size: 14)
            }
            if !rating.tags.isEmpty {
                Text(rating.tags.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !rating.note.isEmpty {
                Text(rating.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
    }

    @ViewBuilder
    private var buyAgainRow: some View {
        let verdict = wine.buyAgain
        HStack(spacing: 8) {
            Label(verdict.title, systemImage: verdict.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color(for: verdict))
            Spacer()
        }
        .padding(.top, 2)
        // Bei nur einer Bewertung ist das noch kein gemeinsames Urteil – das muss dastehen.
        if wine.ratingList.count == 1 {
            Text("Vorläufig, es hat erst eine Person bewertet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func color(for verdict: Wine.BuyAgain) -> Color {
        switch verdict {
        case .yes:     return .green
        case .maybe:   return .orange
        case .no:      return .red
        case .unrated: return .secondary
        }
    }
}
