import CoreData
import SwiftUI

/// Zeilen, Spalten und Name des Regals.
///
/// Verkleinern kann Fächer ausserhalb des Rasters lassen. Statt sie stillschweigend zu
/// löschen, nennt die Ansicht die Zahl der betroffenen Flaschen; sie werden nur aus dem
/// Regal genommen, der Bestand bleibt.
struct RackEditorView: View {

    @ObservedObject var rack: Rack

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var rows = 1
    @State private var columns = 12

    private var losingSlots: [Slot] {
        rack.slotsOutsideGrid(rows: rows, columns: columns)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Regal", text: $name)
                }

                Section {
                    Stepper(value: $rows, in: Rack.rowRange) {
                        LabeledContent("Ebenen", value: "\(rows)")
                    }
                    Stepper(value: $columns, in: Rack.columnRange) {
                        LabeledContent("Fächer je Ebene", value: "\(columns)")
                    }
                } header: {
                    Text("Grösse")
                } footer: {
                    Text("Ergibt \(rows * columns) Fächer. Ein Fach nimmt eine Flasche auf.")
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        RackGridView(
                            rows: rows,
                            columns: columns,
                            occupancy: rack.occupancy(),
                            tile: columns > 10 ? 26 : 34
                        )
                        .padding(.vertical, 6)
                    }
                } header: {
                    Text("Vorschau")
                }

                if !losingSlots.isEmpty {
                    Section {
                        Label {
                            Text(losingSlots.count == 1
                                 ? "1 Flasche liegt ausserhalb des neuen Rasters und wird aus dem Regal genommen. Der Bestand bleibt unverändert."
                                 : "\(losingSlots.count) Flaschen liegen ausserhalb des neuen Rasters und werden aus dem Regal genommen. Der Bestand bleibt unverändert.")
                                .font(.footnote)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle("Regal bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                name = rack.name
                rows = rack.rowCount
                columns = rack.columnCount
            }
        }
    }

    private func save() {
        for slot in losingSlots {
            context.delete(slot)
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        rack.name = trimmed.isEmpty ? "Regal" : trimmed
        rack.rows = Int64(rows)
        rack.columns = Int64(columns)
        context.saveChanges()
        dismiss()
    }
}
