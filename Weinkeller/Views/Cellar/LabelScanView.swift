import SwiftUI
import PhotosUI

/// Sheet: Etikett vorne und hinten erfassen, Text erkennen, Felder zuordnen.
/// Liefert das Ergebnis über `onResult` an das Formular zurück.
struct LabelScanView: View {

    let onResult: (LabelScanResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AISettings.self) private var settings
    @Environment(\.aiService) private var aiService
    @State private var viewModel = LabelScanViewModel()
    @State private var isShowingDocumentScanner = false
    @State private var isShowingRecognizedText = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if DocumentScannerView.isSupported {
                        scannerButton
                    }

                    HStack(spacing: 12) {
                        LabelPhotoSlot(title: "Vorderseite", symbol: "tag", photo: $viewModel.front)
                        LabelPhotoSlot(title: "Rückseite", symbol: "text.alignleft", photo: $viewModel.back)
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
            .fullScreenCover(isPresented: $isShowingDocumentScanner) {
                DocumentScannerView { pages in
                    viewModel.applyScannedPages(pages)
                    isShowingDocumentScanner = false
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

    /// Der Hauptweg: Apples Dokumentenscanner erkennt das Etikett live, schneidet zu und begradigt.
    private var scannerButton: some View {
        Button {
            isShowingDocumentScanner = true
        } label: {
            VStack(spacing: 6) {
                Label("Etikett mit Kamera erfassen", systemImage: "doc.viewfinder")
                    .font(.headline)
                Text("Erkennt das Etikett automatisch, schneidet zu und begradigt. Erst die Vorderseite, dann optional die Rückseite aufnehmen und mit „Sichern“ abschließen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tipp: Etikett bei gutem Licht möglichst formatfüllend aufnehmen, die Flasche ruhig halten, bis der Rahmen einrastet. Die Rückseite liefert oft Rebsorten und Terroir.")
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

    /// Mit Dokumentenscanner ist das der zweite Schritt (dezent), ohne der einzige (prominent).
    @ViewBuilder
    private var scanButton: some View {
        let button = Button {
            Task { await viewModel.scan(service: LabelScanService(aiService: aiService), settings: settings) }
        } label: {
            Label("Etikett auslesen", systemImage: "text.viewfinder")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .disabled(!viewModel.hasImages || viewModel.isProcessing)

        if DocumentScannerView.isSupported {
            button.buttonStyle(.bordered)
        } else {
            button.buttonStyle(.borderedProminent)
        }
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

/// Ein Platzhalter mit Vorschau, Fotoauswahl aus der Mediathek und Entfernen.
private struct LabelPhotoSlot: View {

    let title: String
    let symbol: String
    @Binding var photo: LabelScanViewModel.Photo?

    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 10) {
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
                if photo != nil {
                    Button {
                        photo = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, .black.opacity(0.55))
                    }
                    .padding(8)
                    .accessibilityLabel("\(title) entfernen")
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let photo, photo.isPreCropped {
                    Label("Zugeschnitten", systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(8)
                }
            }

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(photo == nil ? "Aus Fotos" : "Anderes Foto", systemImage: "photo.on.rectangle")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("\(title) aus Fotos wählen")
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { @MainActor in
                if let data = try? await item.loadTransferable(type: Data.self),
                   let loaded = UIImage(data: data) {
                    photo = LabelScanViewModel.Photo(image: loaded, isPreCropped: false)
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
