import SwiftUI
import SwiftData

/// Sheet zum Anlegen oder Bearbeiten eines Weins – manuell oder per Etikett-Scan.
struct WineFormView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: WineFormViewModel
    @State private var isShowingScanner: Bool
    @FocusState private var focusedField: Field?

    private enum Field { case name, producer, grape, region, country, notes }

    /// - Parameter startWithScanner: öffnet sofort den Etikett-Scanner (Plus-Menü „Etikett scannen“).
    init(mode: WineFormViewModel.Mode, startWithScanner: Bool = false) {
        _viewModel = State(initialValue: WineFormViewModel(mode: mode))
        _isShowingScanner = State(initialValue: startWithScanner)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        isShowingScanner = true
                    } label: {
                        Label("Etikett scannen", systemImage: "text.viewfinder")
                    }
                    if let data = viewModel.labelImageData, let image = UIImage(data: data) {
                        HStack(spacing: 12) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 70)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Text("Etikett-Foto wird mit dem Wein gespeichert.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(role: .destructive) {
                                viewModel.labelImageData = nil
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Etikett-Foto entfernen")
                        }
                    }
                    if let source = viewModel.lastScanSource {
                        Label {
                            Text("Felder aus Etikett übernommen – Zuordnung via \(source.displayName). Bitte kurz prüfen.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }

                Section("Wein") {
                    TextField("Name / Cuvée", text: $viewModel.name)
                        .focused($focusedField, equals: .name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .producer }

                    TextField("Produzent / Weingut", text: $viewModel.producer)
                        .focused($focusedField, equals: .producer)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .grape }

                    Picker("Jahrgang", selection: $viewModel.vintage) {
                        ForEach(WineFormViewModel.vintageRange.reversed(), id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                }

                Section {
                    TextField("Rebsorte(n)", text: $viewModel.grape)
                        .focused($focusedField, equals: .grape)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .region }

                    TextField("Region / Appellation", text: $viewModel.region)
                        .focused($focusedField, equals: .region)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .country }

                    TextField("Land", text: $viewModel.country)
                        .focused($focusedField, equals: .country)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                } header: {
                    Text("Herkunft")
                } footer: {
                    Text("Das Land macht die Karte auf der Detailseite eindeutig.")
                }

                Section("Typ") {
                    Picker("Typ", selection: $viewModel.type) {
                        ForEach(WineType.allCases) { type in
                            Label(type.displayName, systemImage: type.symbolName)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Bestand") {
                    Stepper(value: $viewModel.quantity, in: 0...999) {
                        HStack {
                            Text("Flaschen")
                            Spacer()
                            Text("\(viewModel.quantity)")
                                .font(.body.monospacedDigit().weight(.semibold))
                                .contentTransition(.numericText())
                        }
                    }
                    .animation(.snappy, value: viewModel.quantity)
                }

                Section("Notizen") {
                    TextField("Terroir, Ausbau, „Geschenk von Anna“, „bis 2030 trinken“ …", text: $viewModel.notes, axis: .vertical)
                        .lineLimit(2...6)
                        .focused($focusedField, equals: .notes)
                }
            }
            .navigationTitle(viewModel.mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        viewModel.save(in: context)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!viewModel.canSave)
                }
            }
            .sheet(isPresented: $isShowingScanner) {
                LabelScanView { result in
                    viewModel.apply(result)
                }
            }
            .onAppear {
                if case .add = viewModel.mode, !isShowingScanner {
                    focusedField = .name
                }
            }
        }
    }
}

#Preview("Neu") {
    WineFormView(mode: .add)
        .modelContainer(PreviewData.container)
        .environment(AISettings(defaults: PreviewData.defaults))
}

#Preview("Bearbeiten") {
    WineFormView(mode: .edit(PreviewData.sampleWines[0]))
        .modelContainer(PreviewData.container)
        .environment(AISettings(defaults: PreviewData.defaults))
}
