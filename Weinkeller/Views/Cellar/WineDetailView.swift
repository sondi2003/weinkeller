import SwiftUI
import SwiftData

/// Detailansicht eines Weins mit Bestandsverwaltung, Notizen, Archiv und Löschen.
struct WineDetailView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var wine: Wine

    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var consumeCount = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                stockCard
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
                dismiss()
            }
        } message: {
            Text("„\(wine.name) \(String(wine.vintage))“ wird dauerhaft entfernt.")
        }
        .sensoryFeedback(.decrease, trigger: consumeCount)
    }

    // MARK: Kopf

    private var header: some View {
        VStack(spacing: 12) {
            if let image = wine.labelImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
                    .padding(.bottom, 8)
                    .accessibilityLabel("Etikett von \(wine.name)")
            } else {
                WineTypeIcon(type: wine.type, size: 84)
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
    .modelContainer(PreviewData.container)
}
