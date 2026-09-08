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
        VStack(alignment: .leading, spacing: 6) {
            Text(matchedName(profile))
                .font(.subheadline.weight(.semibold))
            matchCheck(profile)
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
            scoresRow(scores)
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
            notesButton(text)
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

        if !profile.displayPairings.isEmpty {
            // Die Empfehlungen selbst stehen in der Karte „Passt zu“ weiter oben.
            Label("\(profile.displayPairings.count) Speiseempfehlungen – siehe „Passt zu“", systemImage: "fork.knife")
                .font(.caption)
                .foregroundStyle(.secondary)
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

    // MARK: Ist es wirklich dieser Wein?

    /// Vergleicht die eigenen Angaben mit dem Treffer. Man kann selbst nicht beurteilen,
    /// ob WineAPI richtig liegt – aber ob Jahrgang und Weingut übereinstimmen, schon.
    @ViewBuilder
    private func matchCheck(_ profile: WineAPIProfile) -> some View {
        let differences = differences(profile)
        if differences.isEmpty {
            Label("Weingut, Name und Jahrgang stimmen mit deinen Angaben überein.", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Label("Bitte prüfen – das weicht von deinen Angaben ab:", systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                ForEach(differences, id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Passt es nicht, wähle im Menü „Zuordnung verwerfen“ und ergänze Weingut oder Jahrgang, bevor du erneut nachschlägst.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        if let confidence = profile.matchConfidence {
            Text("Sicherheit laut WineAPI: \(Int((confidence * 100).rounded())) %")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func differences(_ profile: WineAPIProfile) -> [String] {
        var lines: [String] = []
        if wine.vintage > 0, let found = profile.vintage, found > 0, Int(wine.vintage) != found {
            lines.append("Jahrgang: bei dir \(wine.vintage), gefunden \(found)")
        }
        if !wine.producer.isEmpty, let winery = profile.winery?.name, !winery.isEmpty,
           !looselyEqual(wine.producer, winery) {
            lines.append("Weingut: bei dir „\(wine.producer)“, gefunden „\(winery)“")
        }
        if !looselyEqual(wine.name, profile.name), !looselyEqual(wine.producer + " " + wine.name, profile.name) {
            lines.append("Name: bei dir „\(wine.name)“, gefunden „\(profile.name)“")
        }
        return lines
    }

    /// Gleich genug: Gross-/Kleinschreibung, Akzente und Beiwerk zählen nicht,
    /// und ein Name darf im anderen enthalten sein („Barolo“ in „Barolo Riserva“).
    private func looselyEqual(_ a: String, _ b: String) -> Bool {
        let na = normalized(a), nb = normalized(b)
        guard !na.isEmpty, !nb.isEmpty else { return true }
        return na == nb || na.contains(nb) || nb.contains(na)
    }

    private func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: Kritikerpunkte

    /// Quer blätterbar, eine Karte je Kritiker. Verkostungstexte liefert WineAPI nicht,
    /// nur Punkte und allenfalls ein Wort wie „Gold“.
    private func scoresRow(_ scores: [WineAPIProfile.Score]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(scores.count == 1 ? "Kritikerwertung" : "\(scores.count) Kritikerwertungen")
                .font(.footnote.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(scores.enumerated()), id: \.offset) { _, score in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(score.score.map { $0.truncatingRemainder(dividingBy: 1) == 0 ? String(Int($0)) : String($0) }
                                 ?? score.scoreText ?? "–")
                                .font(.title3.weight(.bold).monospacedDigit())
                            Text(score.reviewer)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if let date = score.reviewDate {
                                Text(date.formatted(.dateTime.year()))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(10)
                        .frame(minWidth: 96, alignment: .leading)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
    }

    // MARK: In die Notizen

    /// Fehlen Notizen vom Scan, übernimmt ein Tipp die Beschreibung – oder hängt sie an.
    @ViewBuilder
    private func notesButton(_ text: String) -> some View {
        let alreadyThere = wine.notes.contains(text.prefix(40))
        if alreadyThere {
            Label("In den Notizen", systemImage: "checkmark")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Button {
                withAnimation {
                    wine.notes = wine.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? text
                        : wine.notes + "\n\n" + text
                    context.saveChanges()
                }
            } label: {
                Label(wine.notes.isEmpty ? "In die Notizen übernehmen" : "An die Notizen anhängen", systemImage: "note.text.badge.plus")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func matchedName(_ profile: WineAPIProfile) -> String {
        var parts: [String] = []
        if let winery = profile.winery?.name, !winery.isEmpty { parts.append(winery) }
        parts.append(profile.name)
        if let vintage = profile.vintage, vintage > 0 { parts.append(String(vintage)) }
        return parts.joined(separator: " · ")
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
