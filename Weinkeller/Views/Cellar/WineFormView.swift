import SwiftUI
import SwiftData

/// Sheet zum Anlegen oder Bearbeiten eines Weins.
struct WineFormView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: WineFormViewModel
    @FocusState private var focusedField: Field?

    private enum Field { case name, grape, notes }

    init(mode: WineFormViewModel.Mode) {
        _viewModel = State(initialValue: WineFormViewModel(mode: mode))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Wein") {
                    TextField("Name / Weingut", text: $viewModel.name)
                        .focused($focusedField, equals: .name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .grape }

                    TextField("Rebsorte / Region", text: $viewModel.grapeOrRegion)
                        .focused($focusedField, equals: .grape)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)

                    Picker("Jahrgang", selection: $viewModel.vintage) {
                        ForEach(WineFormViewModel.vintageRange.reversed(), id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
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
                    TextField("z. B. Geschenk von Anna, bis 2030 trinken", text: $viewModel.notes, axis: .vertical)
                        .lineLimit(2...5)
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
            .onAppear {
                if case .add = viewModel.mode {
                    focusedField = .name
                }
            }
        }
    }
}

#Preview("Neu") {
    WineFormView(mode: .add)
        .modelContainer(PreviewData.container)
}

#Preview("Bearbeiten") {
    WineFormView(mode: .edit(PreviewData.sampleWines[0]))
        .modelContainer(PreviewData.container)
}
