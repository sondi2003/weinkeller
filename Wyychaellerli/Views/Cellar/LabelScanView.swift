import PhotosUI
import SwiftUI

/// Sheet: Etikett vorne und hinten erfassen, Text erkennen, Felder zuordnen.
/// Liefert das Ergebnis über `onResult` an das Formular zurück.
struct LabelScanView: View {

    let onResult: (LabelScanResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AISettings.self) private var settings
    @Environment(\.aiService) private var aiService
    @State private var viewModel = LabelScanViewModel()
    /// Welche Seite gerade mit der Kamera erfasst wird.
    @State private var scanningSide: LabelScanViewModel.Side?
    @State private var isShowingRecognizedText = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        LabelPhotoSlot(
                            side: .front,
                            symbol: "tag",
                            photo: $viewModel.front,
                            onScan: { scanningSide = .front }
                        )
                        LabelPhotoSlot(
                            side: .back,
                            symbol: "text.alignleft",
                            photo: $viewModel.back,
                            onScan: { scanningSide = .back }
                        )
                    }

                    intro
                    scanButton

                    if viewModel.isProcessing {
                        processingCard
                    } else if let errorMessage = viewModel.errorMessage {
                        CalloutBox(kind: .error, text: errorMessage)
                        recognizedTextDisclosure
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Etikett scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .fullScreenCover(item: $scanningSide) { side in
                CameraCaptureView { image in
                    viewModel.applyPhoto(image, to: side)
                    scanningSide = nil
                }
                .ignoresSafeArea()
            }
            .onChange(of: viewModel.result) { _, result in
                if let result {
                    onResult(result)
                    dismiss()
                }
            }
        }
    }

    // MARK: Bausteine

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tippe auf eine Seite, um sie mit der Kamera zu erfassen. Fotografiere die Flasche einfach ganz – die App sucht die Etikettenkante selbst, schneidet zu und begradigt. Kein Ausrichten nötig.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(structuringHint)
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Sagt vorab, womit die Zuordnung voraussichtlich gemacht wird.
    private var structuringHint: String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), OnDeviceLabelParser.isAvailable {
            return "Texterkennung und Zuordnung laufen komplett auf dem Gerät (Apple Intelligence)."
        }
        #endif
        if let provider = settings.activeProvider {
            return "Texterkennung auf dem Gerät, Zuordnung der Felder über \(provider.shortName). Es wird nur der erkannte Text gesendet, nicht das Foto."
        }
        return "Texterkennung auf dem Gerät. Ohne API-Key werden die Felder regelbasiert zugeordnet – Jahrgang, Typ und bekannte Rebsorten klappen gut, Name und Produzent bitte prüfen."
    }

    private var scanButton: some View {
        Button {
            Task { await viewModel.scan(service: LabelScanService(aiService: aiService), settings: settings) }
        } label: {
            Label("Etikett auslesen", systemImage: "text.viewfinder")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!viewModel.hasImages || viewModel.isProcessing)
    }

    private var processingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Text wird erkannt und zugeordnet …")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    @ViewBuilder
    private var recognizedTextDisclosure: some View {
        if !viewModel.recognizedText.isEmpty {
            DisclosureGroup("Erkannter Text anzeigen", isExpanded: $isShowingRecognizedText) {
                Text(viewModel.recognizedText)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                    .textSelection(.enabled)
            }
            .cardStyle()
        }
    }
}

// MARK: - Foto-Slot

/// Eine Etikettseite: grosse Fläche zum Scannen, darunter die Fotoauswahl als Alternative.
private struct LabelPhotoSlot: View {

    let side: LabelScanViewModel.Side
    let symbol: String
    @Binding var photo: LabelScanViewModel.Photo?
    let onScan: () -> Void

    @State private var pickerItem: PhotosPickerItem?

    private var canScan: Bool { CameraCaptureView.isSupported }

    var body: some View {
        VStack(spacing: 10) {
            Button(action: onScan) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                    if let photo {
                        // Color.clear gibt die Größe vor, das Overlay füllt sie und wird beschnitten.
                        Color.clear
                            .overlay {
                                Image(uiImage: photo.image)
                                    .resizable()
                                    .scaledToFill()
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: canScan ? "camera.viewfinder" : symbol)
                                .font(.title)
                                .foregroundStyle(canScan ? Color.accentColor : Color.secondary)
                            Text(side.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            if canScan {
                                Text("Tippen zum Scannen")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 200)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            photo == nil ? Color.accentColor.opacity(0.35) : Color.clear,
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(!canScan)
            .accessibilityLabel(photo == nil ? "\(side.title) scannen" : "\(side.title) erneut scannen")
            .overlay(alignment: .topTrailing) {
                if photo != nil {
                    Button {
                        photo = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, .black.opacity(0.55))
                    }
                    .padding(8)
                    .accessibilityLabel("\(side.title) entfernen")
                }
            }
            .overlay(alignment: .bottomLeading) {
                if photo != nil {
                    Label("Etikett wird beim Auslesen zugeschnitten", systemImage: "crop")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(8)
                }
            }

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Aus Fotos", systemImage: "photo.on.rectangle")
                    .font(.footnote)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("\(side.title) aus Fotos wählen")
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { @MainActor in
                if let data = try? await item.loadTransferable(type: Data.self),
                   let loaded = UIImage(data: data) {
                    photo = LabelScanViewModel.Photo(image: loaded)
                }
                pickerItem = nil
            }
        }
    }
}

#Preview {
    LabelScanView { _ in }
        .environment(AISettings(defaults: PreviewData.defaults))
}
