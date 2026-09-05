import SwiftUI
import PhotosUI

/// Sheet: Etikett vorne und hinten fotografieren, Text erkennen, Felder zuordnen.
/// Liefert das Ergebnis über `onResult` an das Formular zurück.
struct LabelScanView: View {

    let onResult: (LabelScanResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AISettings.self) private var settings
    @Environment(\.aiService) private var aiService
    @State private var viewModel = LabelScanViewModel()
    @State private var isShowingRecognizedText = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    intro

                    HStack(spacing: 12) {
                        LabelPhotoSlot(title: "Vorderseite", symbol: "tag", image: $viewModel.frontImage)
                        LabelPhotoSlot(title: "Rückseite", symbol: "text.alignleft", image: $viewModel.backImage)
                    }

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
            Text("Fotografiere das Etikett bei gutem Licht, möglichst gerade und formatfüllend. Die Rückseite ist optional, liefert aber oft Rebsorten und Terroir.")
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

/// Ein Platzhalter mit Vorschau und den Aktionen Kamera / Fotos / Entfernen.
private struct LabelPhotoSlot: View {

    let title: String
    let symbol: String
    @Binding var image: UIImage?

    @State private var isShowingCamera = false
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                if let image {
                    // Color.clear gibt die Größe vor, das Overlay füllt sie und wird beschnitten.
                    Color.clear
                        .overlay {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: symbol)
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text(title)
                            .font(.subheadline.weight(.medium))
                    }
                }
            }
            .frame(height: 200)
            .overlay(alignment: .topTrailing) {
                if image != nil {
                    Button {
                        image = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, .black.opacity(0.55))
                    }
                    .padding(8)
                    .accessibilityLabel("\(title) entfernen")
                }
            }

            HStack(spacing: 8) {
                if CameraPicker.isAvailable {
                    Button {
                        isShowingCamera = true
                    } label: {
                        Image(systemName: "camera")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("\(title) fotografieren")
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("\(title) aus Fotos wählen")
            }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { image = $0 }
                .ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let loaded = UIImage(data: data) {
                    image = loaded
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
