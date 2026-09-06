import SwiftUI
import CoreData

/// Detailansicht eines Weins mit Bestandsverwaltung, Notizen, Archiv und Löschen.
struct WineDetailView: View {

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var wine: Wine

    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var consumeCount = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                stockCard
                if !wine.foodPairings.isEmpty {
                    pairingCard
                }
                WineOriginMapView(wine: wine)
                if !wine.notes.isEmpty {
                    notesCard
                }
                archiveCard
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(wine.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Bearbeiten") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            WineFormView(mode: .edit(wine))
        }
        .confirmationDialog("Wein löschen?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                context.delete(wine)
                context.saveChanges()
                dismiss()
            }
        } message: {
            Text("„\(wine.name) \(String(wine.vintage))“ wird dauerhaft entfernt.")
        }
        .sensoryFeedback(.decrease, trigger: consumeCount)
    }

    // MARK: Kopf

    /// Vorhandene Etikettseiten in fester Reihenfolge.
    private var labelPages: [LabelPage] {
        var pages: [LabelPage] = []
        if let image = wine.labelImage { pages.append(LabelPage(title: "Vorderseite", image: image)) }
        if let image = wine.backLabelImage { pages.append(LabelPage(title: "Rückseite", image: image)) }
        return pages
    }

    private var header: some View {
        VStack(spacing: 12) {
            if labelPages.isEmpty {
                WineTypeIcon(type: wine.type, size: 84)
            } else {
                LabelPager(pages: labelPages, wineName: wine.name)
                    .padding(.bottom, 8)
            }
            if !wine.producer.isEmpty {
                Text(wine.producer)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1)
            }
            Text(wine.name)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text(wine.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(wine.type.displayName)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(wine.type.color.opacity(0.15), in: Capsule())
                .foregroundStyle(wine.type.color)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: Bestand

    private var stockCard: some View {
        VStack(spacing: 16) {
            Text("Bestand")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 28) {
                Button {
                    wine.consumeBottle()
                    consumeCount += 1
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 44))
                }
                .disabled(wine.isOutOfStock)
                .accessibilityLabel("Eine Flasche trinken")

                VStack(spacing: 2) {
                    Text("\(wine.quantity)")
                        .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                    Text(wine.quantity == 1 ? "Flasche" : "Flaschen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 90)

                Button {
                    wine.addBottle()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 44))
                }
                .accessibilityLabel("Eine Flasche hinzufügen")
            }
            .animation(.snappy, value: wine.quantity)

            if wine.isOutOfStock {
                CalloutBox(kind: .warning, text: "Keine Flasche mehr übrig. Du kannst den Wein archivieren oder löschen.")
            }
        }
        .cardStyle()
    }

    // MARK: Speiseempfehlung vom Etikett

    /// Nur sichtbar, wenn auf dem Etikett tatsächlich etwas dazu steht.
    private var pairingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Passt laut Etikett zu", systemImage: "fork.knife")
                .font(.headline)
            FlowLayout(spacing: 8) {
                ForEach(wine.foodPairings, id: \.self) { pairing in
                    Text(pairing)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(wine.type.color.opacity(0.12), in: Capsule())
                        .foregroundStyle(wine.type.color)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: Notizen

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notizen")
                .font(.headline)
            Text(wine.notes)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardStyle()
    }

    // MARK: Archiv / Löschen

    private var archiveCard: some View {
        VStack(spacing: 12) {
            Button {
                wine.isArchived.toggle()
                wine.managedObjectContext?.saveChanges()
            } label: {
                Label(
                    wine.isArchived ? "Zurück in den Keller" : "Archivieren",
                    systemImage: wine.isArchived ? "tray.and.arrow.up" : "archivebox"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Löschen", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .cardStyle()
    }
}

#Preview {
    NavigationStack {
        WineDetailView(wine: PreviewData.sampleWines[0])
    }
    .environment(\.managedObjectContext, PreviewData.context)
}
