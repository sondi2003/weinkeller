import SwiftUI

/// Code für den Party-Modus festlegen und ändern.
///
/// Ändern geht nur, wer den bisherigen Code kennt – sonst könnte ein Gast mit dem Gerät
/// in der Hand einfach einen neuen setzen.
struct PartySettingsView: View {

    @State private var isConfigured = PartyLock.isConfigured
    @State private var currentCode = ""
    @State private var newCode = ""
    @State private var repeatCode = ""
    @State private var message: String?
    @State private var isError = false
    @State private var isConfirmingRemoval = false

    var body: some View {
        Form {
            if isConfigured {
                Section {
                    SecureField("Bisheriger Code", text: $currentCode)
                        .keyboardType(.numberPad)
                } footer: {
                    Text("Zum Ändern zuerst den bisherigen Code eingeben.")
                }
            }

            Section {
                SecureField(isConfigured ? "Neuer Code" : "Code", text: $newCode)
                    .keyboardType(.numberPad)
                SecureField("Wiederholen", text: $repeatCode)
                    .keyboardType(.numberPad)
            } header: {
                Text(isConfigured ? "Neuer Code" : "Code festlegen")
            } footer: {
                Text("\(PartyLock.minimumLength) bis \(PartyLock.maximumLength) Ziffern. Damit wird der Party-Modus gestartet und wieder verlassen – Gäste kommen ohne ihn nicht heraus.")
            }

            Section {
                Button {
                    save()
                } label: {
                    Text(isConfigured ? "Code ändern" : "Code festlegen")
                }
                .disabled(!canSave)

                if isConfigured {
                    Button(role: .destructive) {
                        isConfirmingRemoval = true
                    } label: {
                        Text("Code entfernen")
                    }
                }
            } footer: {
                if let message {
                    Text(message)
                        .foregroundStyle(isError ? .red : .green)
                }
            }

            if let biometry = PartyLock.biometryName {
                Section {
                    Label {
                        Text("Vergisst du den Code, kommst du mit \(biometry) aus dem Party-Modus heraus. Deine Gäste nicht.")
                    } icon: {
                        Image(systemName: biometry == "Face ID" ? "faceid" : "touchid")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                } header: {
                    Text("Notausgang")
                }
            }

            Section {
                Label {
                    Text("Damit während der Party niemand versehentlich in andere Apps wechselt, hilft der geführte Zugriff von iOS: dreimal die Seitentaste drücken. Er nagelt das Gerät auf diese App fest.")
                } icon: {
                    Image(systemName: "hand.raised")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            } header: {
                Text("Tipp für die Party")
            }
        }
        .navigationTitle("Party-Modus")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Code entfernen?", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
            Button("Entfernen", role: .destructive) { remove() }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Ohne Code lässt sich der Party-Modus nicht starten.")
        }
    }

    private var canSave: Bool {
        PartyLock.isValidFormat(newCode)
            && newCode == repeatCode
            && (!isConfigured || currentCode.count >= PartyLock.minimumLength)
    }

    private func save() {
        if isConfigured, !PartyLock.matches(currentCode) {
            show("Der bisherige Code stimmt nicht.", error: true)
            return
        }
        guard PartyLock.isValidFormat(newCode) else {
            show("Der Code muss aus \(PartyLock.minimumLength) bis \(PartyLock.maximumLength) Ziffern bestehen.", error: true)
            return
        }
        guard newCode == repeatCode else {
            show("Die beiden Eingaben sind nicht gleich.", error: true)
            return
        }
        do {
            try PartyLock.set(newCode)
            isConfigured = true
            currentCode = ""; newCode = ""; repeatCode = ""
            show("Code gespeichert.", error: false)
        } catch {
            show("Der Code konnte nicht gespeichert werden: \(error.localizedDescription)", error: true)
        }
    }

    private func remove() {
        guard !isConfigured || PartyLock.matches(currentCode) else {
            show("Zum Entfernen zuerst den bisherigen Code eingeben.", error: true)
            return
        }
        try? PartyLock.remove()
        isConfigured = false
        currentCode = ""; newCode = ""; repeatCode = ""
        show("Code entfernt.", error: false)
    }

    private func show(_ text: String, error: Bool) {
        message = text
        isError = error
    }
}
