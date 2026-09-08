import SwiftUI

/// Der Key für wineapi.io. Eigene Seite wie bei den KI-Anbietern, damit die
/// Einstellungen übersichtlich bleiben.
struct WineAPISettingsView: View {

    @State private var apiKey = ""
    @State private var isKeyVisible = false
    @State private var keychainError: String?
    @State private var hasStoredKey = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Group {
                        if isKeyVisible {
                            TextField("API-Key", text: $apiKey)
                        } else {
                            SecureField("API-Key", text: $apiKey)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.callout.monospaced())

                    Button {
                        isKeyVisible.toggle()
                    } label: {
                        Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(isKeyVisible ? "Key verbergen" : "Key anzeigen")
                }

                if hasStoredKey {
                    Button(role: .destructive) {
                        apiKey = ""
                        isKeyVisible = false
                    } label: {
                        Label("API-Key entfernen", systemImage: "trash")
                    }
                }

                if let keychainError {
                    Text(keychainError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Zugang")
            } footer: {
                Text("Den Key gibt es kostenlos auf wineapi.io (Tarif „Free“, 100 Anfragen am Tag, für den privaten Gebrauch). Er liegt ausschliesslich in der Keychain dieses Geräts.")
            }

            Section {
                Label {
                    Text("Bewertungen und Kritikerpunkte, eine Beschreibung, die Preisspanne und Speiseempfehlungen – pro Wein einmal nachgeschlagen, dann gespeichert.")
                } icon: {
                    Image(systemName: "text.magnifyingglass")
                }
                Label {
                    Text("Die Speiseempfehlungen nutzt der Wein-Berater wie die vom Etikett: ohne KI-Anfrage, ohne Kosten.")
                } icon: {
                    Image(systemName: "fork.knife")
                }
                Label {
                    Text("Beschreibung und Empfehlungen werden auf dem Gerät ins Deutsche übersetzt, sofern das Sprachpaket installiert ist.")
                } icon: {
                    Image(systemName: "character.book.closed")
                }
            } header: {
                Text("Was es bringt")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .navigationTitle("WineAPI")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            apiKey = WineAPIClient.storedKey ?? ""
            hasStoredKey = !apiKey.isEmpty
        }
        // Speichern beim Verlassen – wie bei den KI-Anbietern, ohne eigenen Knopf.
        .onDisappear { save() }
    }

    private func save() {
        do {
            try KeychainStore.set(apiKey, for: WineAPIClient.keychainAccount)
            hasStoredKey = !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            keychainError = nil
        } catch {
            keychainError = "Der Key konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }
}
