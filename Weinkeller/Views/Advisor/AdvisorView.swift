import SwiftUI
import SwiftData

/// Tab 2: Essens-Stichwort eingeben und Top-3-Empfehlung vom aktiven Anbieter holen.
struct AdvisorView: View {

    @Binding var selectedTab: AppTab

    @Environment(AISettings.self) private var settings
    @Environment(\.aiService) private var aiService
    @Query private var wines: [Wine]
    @State private var viewModel = PairingViewModel()
    @FocusState private var dishFieldFocused: Bool
    @State private var openedBottleCount = 0

    /// Nur was wirklich im Keller liegt, geht an die KI.
    private var availableWines: [Wine] {
        wines.filter { !$0.isArchived && $0.quantity > 0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    dishInputCard
                    requestButton

                    if viewModel.isLoading {
                        loadingCard
                    } else if let error = viewModel.error {
                        errorCard(error)
                    } else if let response = viewModel.response {
                        resultSection(response)
                    } else {
                        introCard
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Wein-Berater")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ProviderStatusBadge(settings: settings) { selectedTab = .settings }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .sensoryFeedback(.success, trigger: viewModel.response)
            .sensoryFeedback(.decrease, trigger: openedBottleCount)
        }
    }

    // MARK: Eingabe

    private var dishInputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Was gibt es zu essen?", systemImage: "fork.knife")
                .font(.headline)

            HStack {
                TextField("z. B. Raclette, Spaghetti Bolognese …", text: $viewModel.dish)
                    .focused($dishFieldFocused)
                    .submitLabel(.go)
                    .onSubmit { Task { await request() } }
                if !viewModel.dish.isEmpty {
                    Button {
                        viewModel.dish = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PairingViewModel.suggestions, id: \.self) { suggestion in
                        Button(suggestion) {
                            viewModel.dish = suggestion
                            dishFieldFocused = false
                        }
                        .font(.subheadline)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                    }
                }
            }
        }
        .cardStyle()
    }

    // MARK: Aktion

    private var requestButton: some View {
        VStack(spacing: 10) {
            Button {
                Task { await request() }
            } label: {
                Label("Empfehlung holen", systemImage: "sparkles")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canRequest(settings: settings, hasInventory: !availableWines.isEmpty))

            hintLine
        }
    }

    /// Eine Zeile unter dem Button: entweder was fehlt, oder was gleich passiert.
    @ViewBuilder
    private var hintLine: some View {
        if let provider = settings.activeProvider, let model = settings.activeModel {
            if availableWines.isEmpty {
                Text("Im Keller liegt gerade keine Flasche mit Bestand.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(provider.shortName) · \(model) · \(availableWines.count) \(availableWines.count == 1 ? "Wein" : "Weine") mit Bestand")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Noch kein API-Key hinterlegt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Einstellungen") { selectedTab = .settings }
                    .font(.footnote.weight(.semibold))
            }
        }
    }

    private func request() async {
        dishFieldFocused = false
        await viewModel.requestRecommendation(
            inventory: availableWines.map(\.inventoryItem),
            settings: settings,
            service: aiService
        )
    }

    // MARK: Zustände

    private var loadingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("\(settings.activeProvider?.shortName ?? "Die KI") schaut in deinen Keller …")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private var introCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "wineglass")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
            Text("Sag mir, was du kochst.")
                .font(.headline)
            Text("Ich schlage dir bis zu drei passende Weine aus deinem eigenen Keller vor – mit Begründung und Serviertipp.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .cardStyle()
    }

    private func errorCard(_ error: AIServiceError) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(error.title, systemImage: "xmark.octagon.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text(error.localizedDescription)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if error.suggestsSettings {
                    Button {
                        selectedTab = .settings
                    } label: {
                        Label("Einstellungen", systemImage: "gearshape")
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                Button {
                    Task { await request() }
                } label: {
                    Label("Erneut versuchen", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canRequest(settings: settings, hasInventory: !availableWines.isEmpty))
            }
        }
        .cardStyle()
    }

    // MARK: Ergebnis

    private func resultSection(_ response: PairingResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Empfehlung für „\(viewModel.resultDish)“")
                    .font(.headline)
                Spacer()
                if let provider = viewModel.resultProvider {
                    Text(provider.shortName)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                        .help(viewModel.resultModel)
                }
            }

            if !response.generalNote.isEmpty {
                CalloutBox(kind: .info, text: response.generalNote)
            }

            if response.recommendations.isEmpty {
                CalloutBox(kind: .warning, text: "Es wurde kein passender Wein gefunden.")
            }

            ForEach(response.sortedRecommendations) { recommendation in
                let wine = matchingWine(for: recommendation)
                RecommendationCard(recommendation: recommendation, wine: wine) {
                    if let wine, wine.quantity > 0 {
                        wine.consumeBottle()
                        openedBottleCount += 1
                    }
                }
            }
        }
    }

    /// Ordnet eine Empfehlung dem Wein im Keller zu (Name + Jahrgang, Name-Fallback).
    private func matchingWine(for recommendation: PairingRecommendation) -> Wine? {
        let name = recommendation.wineName.lowercased()
        return wines.first { $0.name.lowercased() == name && $0.vintage == recommendation.vintage }
            ?? wines.first { $0.name.lowercased() == name }
    }
}

// MARK: - Statusanzeige in der Toolbar

/// Zeigt, welcher Anbieter gerade aktiv ist – oder dass keiner eingerichtet ist.
/// Tippen führt in die Einstellungen.
struct ProviderStatusBadge: View {
    let settings: AISettings
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                if let provider = settings.activeProvider {
                    Image(systemName: provider.symbolName)
                    Text(provider.shortName)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Kein Anbieter")
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 4)
        }
        .tint(settings.activeProvider == nil ? .orange : .accentColor)
        .accessibilityLabel(
            settings.activeProvider.map { "Aktiver Anbieter: \($0.displayName), Modell \(settings.model(for: $0))" }
                ?? "Kein Anbieter eingerichtet"
        )
    }
}

#Preview {
    AdvisorView(selectedTab: .constant(.advisor))
        .modelContainer(PreviewData.container)
        .environment(AISettings(defaults: PreviewData.defaults))
}
