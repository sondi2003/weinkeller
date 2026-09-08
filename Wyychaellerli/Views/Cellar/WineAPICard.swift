import CoreData
import SwiftUI

/// Was das Netz über diesen Wein weiss – nachgeschlagen bei wineapi.io.
///
/// Nur sichtbar, wenn ein Key hinterlegt ist. Vor dem Nachschlagen ein Knopf, danach
/// Bewertung, Kritikerpunkte, Beschreibung, Preisspanne und Speiseempfehlungen.
struct WineAPICard: View {

    @ObservedObject var wine: Wine

    @Environment(\.managedObjectContext) private var context
    @Environment(\.aiService) private var aiService

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasKey = WineAPIClient.storedKey != nil

    var body: some View {
        if hasKey {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Aus dem Netz", systemImage: "globe")
                        .font(.headline)
                    Spacer()
                    if wine.wineAPIProfile != nil, !isLoading {
                        Menu {
                            Button {
                                Task { await lookup() }
                            } label: {
                                Label("Aktualisieren", systemImage: "arrow.clockwise")
                            }
                            Button(role: .destructive) {
                                WineAPILookup.forget(wine, context: context)
                            } label: {
                                Label("Zuordnung verwerfen", systemImage: "xmark.circle")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Optionen")
                    }
                }

                if isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Wird bei WineAPI gesucht …")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if let profile = wine.wineAPIProfile {
                    profileBody(profile)
                } else {
                    Text("Bewertungen, Beschreibung, Preisspanne und Speiseempfehlungen von wineapi.io.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await lookup() }
                    } label: {
                        Label("Nachschlagen", systemImage: "text.magnifyingglass")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
            .onAppear { hasKey = WineAPIClient.storedKey != nil }
        }
    }

    // MARK: Profil

    @ViewBuilder
    private func profileBody(_ profile: WineAPIProfile) -> some View {
        // Was WineAPI meint, gefunden zu haben – damit ein Fehlgriff auffällt.
        VStack(alignment: .leading, spacing: 2) {
            Text(matchedName(profile))
                .font(.subheadline.weight(.semibold))
            if let confidence = profile.matchConfidence, confidence < 0.8 {
                Label("Zuordnung unsicher (\(Int(confidence * 100)) %) – bitte Name und Jahrgang vergleichen.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }

        if profile.hasRating, let rating = profile.averageRating {
            HStack(spacing: 8) {
                // Die Skala ist nicht dokumentiert; Sterne nur, wenn es plausibel „von 5“ ist.
                if rating <= 5 {
                    StarRatingView(value: .constant(rating), isEditable: false, size: 18)
                }
                Text(rating.formatted(.number.precision(.fractionLength(1))))
                    .font(.subheadline.weight(.semibold))
                if let count = profile.ratingsCount, count > 0 {
                    Text("· \(count) Bewertungen")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }

        let scores = profile.usableScores
        if !scores.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(Array(scores.prefix(6).enumerated()), id: \.offset) { _, score in
                    Text(scoreText(score))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
            }
        }

        if let text = profile.displayDescription {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if profile.descriptionGerman == nil, LabelNotesTranslator.foreignLanguage(in: text) != nil {
                Text("Nicht übersetzt – das Sprachpaket fehlt auf diesem Gerät.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        let facts = factLine(profile)
        if !facts.isEmpty {
            Text(facts)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        if let price = profile.priceText {
            Label("Preisspanne \(price)", systemImage: "tag")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        let pairings = profile.displayPairings
        if !pairings.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Passt laut WineAPI zu")
                    .font(.footnote.weight(.semibold))
                FlowLayout(spacing: 8) {
                    ForEach(pairings, id: \.self) { pairing in
                        Text(pairing)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(wine.type.color.opacity(0.12), in: Capsule())
                            .foregroundStyle(wine.type.color)
                    }
                }
            }
        }

        HStack {
            if let date = wine.wineAPIFetchedAt {
                Text("Stand \(date.formatted(date: .abbreviated, time: .omitted))")
            }
            if profile.isPending == true {
                Text("· wird bei WineAPI noch ergänzt, später aktualisieren")
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }

    private func matchedName(_ profile: WineAPIProfile) -> String {
        var parts: [String] = []
        if let winery = profile.winery?.name, !winery.isEmpty { parts.append(winery) }
        parts.append(profile.name)
        if let vintage = profile.vintage, vintage > 0 { parts.append(String(vintage)) }
        return parts.joined(separator: " · ")
    }

    private func scoreText(_ score: WineAPIProfile.Score) -> String {
        if let value = score.score {
            let number = value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
            return "\(score.reviewer) \(number)"
        }
        return "\(score.reviewer) \(score.scoreText ?? "")"
    }

    private func factLine(_ profile: WineAPIProfile) -> String {
        var parts: [String] = []
        if let grapes = profile.grapes, !grapes.isEmpty { parts.append(grapes.map(\.name).joined(separator: ", ")) }
        if let region = profile.region?.name, !region.isEmpty { parts.append(region) }
        if let body = profile.body, !body.isEmpty { parts.append(body) }
        if let alcohol = profile.alcoholContent, alcohol > 0 {
            parts.append("\(alcohol.formatted(.number.precision(.fractionLength(0...1)))) % Vol.")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Laden

    private func lookup() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            _ = try await WineAPILookup.refresh(wine, aiService: aiService, context: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
