import SwiftUI
import CoreData
import TipKit

/// Tab 1: Liste aller Weine mit Bestand, Schnell-Abbuchung und Hinzufügen.
struct CellarView: View {

    private let consumeTip = ConsumeTip()

    @Environment(\.managedObjectContext) private var context
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: false)],
        animation: .default
    ) private var fetchedWines: FetchedResults<Wine>
    @State private var viewModel = CellarViewModel()
    @State private var isShowingRatings = false
    @State private var isShowingRack = false
    /// Wein, der gerade bewertet wird – nach dem Austrinken der letzten Flasche.
    @State private var wineToRate: Wine?

    /// FetchedResults als Array, damit Filter und Zusammenfassung damit rechnen können.
    private var wines: [Wine] { Array(fetchedWines) }

    var body: some View {
        NavigationStack {
            Group {
                if wines.isEmpty {
                    emptyCellar
                } else {
                    wineList
                }
            }
            .navigationTitle("Wyychällerli")
            .toolbar { toolbarContent }
            .sheet(isPresented: $isShowingRatings) {
                RatingsOverviewView()
            }
            .sheet(isPresented: $isShowingRack) {
                RackView()
            }
            .searchable(text: $viewModel.searchText, prompt: "Name, Rebsorte, Region, Jahrgang")
            .sheet(item: $viewModel.addMode) { mode in
                WineFormView(mode: .add, startWithScanner: mode == .scan)
            }
            .sheet(item: $viewModel.wineToEdit) { wine in
                WineFormView(mode: .edit(wine))
            }
            .confirmationDialog(
                "Letzte Flasche getrunken",
                isPresented: Binding(
                    get: { viewModel.justEmptiedWine != nil },
                    set: { if !$0 { viewModel.justEmptiedWine = nil } }
                ),
                titleVisibility: .visible,
                presenting: viewModel.justEmptiedWine
            ) { wine in
                // Der natürliche Moment zum Bewerten: Die Flasche ist gerade ausgetrunken.
                Button("Bewerten") { wineToRate = wine }
                Button("Archivieren") { viewModel.archive(wine) }
                Button("Löschen", role: .destructive) { viewModel.delete(wine, in: context) }
                Button("Im Keller behalten", role: .cancel) { }
            } message: { wine in
                Text("„\(wine.name) \(String(wine.vintage))“ ist jetzt leer. Was soll damit passieren?")
            }
            .sheet(item: $wineToRate) { wine in
                RatingSheet(wine: wine)
            }
            .sheet(item: $viewModel.wineToTakeFromRack) { wine in
                WineRackSheet(wine: wine, mode: .take)
            }
            .sensoryFeedback(.decrease, trigger: viewModel.consumeCount)
        }
    }

    // MARK: Liste

    private var wineList: some View {
        let visible = viewModel.filtered(wines)
        let groups = viewModel.grouped(visible)

        return List {
            Section {
                summaryHeader
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                // Erst wenn es etwas abzubuchen gibt; im leeren Keller wäre er nur Rauschen.
                if !groups.isEmpty {
                    TipView(consumeTip)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)
                }
            }

            if groups.isEmpty {
                Group {
                    if !viewModel.searchText.isEmpty {
                        ContentUnavailableView.search(text: viewModel.searchText)
                    } else if viewModel.showArchived {
                        ContentUnavailableView(
                            "Archiv ist leer",
                            systemImage: "archivebox",
                            description: Text("Archivierte Weine erscheinen hier.")
                        )
                    } else {
                        ContentUnavailableView(
                            "Nichts in dieser Ansicht",
                            systemImage: "wineglass",
                            description: Text("Ändere den Filter oder lege einen neuen Wein an.")
                        )
                    }
                }
                .listRowBackground(Color.clear)
            }

            ForEach(groups, id: \.type) { group in
                Section {
                    ForEach(group.wines) { wine in
                        NavigationLink(value: wine) {
                            WineRowView(wine: wine) {
                                consumeTip.invalidate(reason: .actionPerformed)
                                viewModel.consume(wine)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                viewModel.delete(wine, in: context)
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                            if wine.isArchived {
                                Button {
                                    viewModel.unarchive(wine)
                                } label: {
                                    Label("Zurück in den Keller", systemImage: "tray.and.arrow.up")
                                }
                                .tint(.green)
                            } else {
                                Button {
                                    viewModel.archive(wine)
                                } label: {
                                    Label("Archivieren", systemImage: "archivebox")
                                }
                                .tint(.orange)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                viewModel.wineToEdit = wine
                            } label: {
                                Label("Bearbeiten", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                } header: {
                    Label(group.type.displayName, systemImage: group.type.symbolName)
                        .foregroundStyle(group.type.color)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: Wine.self) { wine in
            WineDetailView(wine: wine)
        }
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(viewModel.showArchived ? "Archiv" : viewModel.summary(for: wines))
                    .font(.headline)
                Spacer()
            }
            typeFilterChips
        }
    }

    private var typeFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "Alle", color: .accentColor, isSelected: viewModel.typeFilter == nil) {
                    viewModel.typeFilter = nil
                }
                ForEach(WineType.allCases) { type in
                    FilterChip(
                        title: type.displayName,
                        symbol: type.symbolName,
                        color: type.color,
                        isSelected: viewModel.typeFilter == type
                    ) {
                        viewModel.typeFilter = (viewModel.typeFilter == type) ? nil : type
                    }
                }
            }
        }
    }

    // MARK: Leerer Keller

    private var emptyCellar: some View {
        ContentUnavailableView {
            Label("Der Keller ist leer", systemImage: "wineglass")
        } description: {
            Text("Lege deine erste Flasche an, damit der Wein-Berater etwas empfehlen kann.")
        } actions: {
            VStack(spacing: 10) {
                Button {
                    viewModel.addMode = .scan
                } label: {
                    Label("Etikett scannen", systemImage: "text.viewfinder")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    viewModel.addMode = .manual
                } label: {
                    Label("Manuell eingeben", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Toggle(isOn: $viewModel.showArchived) {
                    Label("Archiv anzeigen", systemImage: "archivebox")
                }
                Toggle(isOn: $viewModel.showOnlyDrinkSoon) {
                    Label("Nur was dran ist", systemImage: "clock.badge.exclamationmark")
                }
                Divider()
                Button {
                    isShowingRack = true
                } label: {
                    Label("Regal", systemImage: "square.grid.3x3")
                }
                Button {
                    isShowingRatings = true
                } label: {
                    Label("Bewertungen", systemImage: "star")
                }
            } label: {
                Image(systemName: viewModel.isFiltering ? "line.3.horizontal.decrease.circle.fill" : "ellipsis.circle")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    viewModel.addMode = .scan
                } label: {
                    Label("Etikett scannen", systemImage: "text.viewfinder")
                }
                Button {
                    viewModel.addMode = .manual
                } label: {
                    Label("Manuell eingeben", systemImage: "square.and.pencil")
                }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Wein hinzufügen")
        }
    }
}

// MARK: - Filter-Chip

private struct FilterChip: View {
    let title: String
    var symbol: String? = nil
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.caption.weight(.semibold))
                }
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isSelected ? color : Color(.tertiarySystemFill))
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: isSelected)
    }
}

#Preview("Mit Weinen") {
    CellarView()
        .environment(\.managedObjectContext, PreviewData.context)
}

#Preview("Leer") {
    CellarView()
        .environment(\.managedObjectContext, PreviewData.emptyContext)
}
