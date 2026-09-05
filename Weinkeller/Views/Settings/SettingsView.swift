import SwiftUI

/// Tab 3: Standard-Anbieter, API-Keys (Keychain) und Modellnamen pro Anbieter.
struct SettingsView: View {

    @Environment(AISettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    Picker("Standard-Anbieter", selection: $settings.selectedProvider) {
                        ForEach(AIProvider.allCases) { provider in
                            Label(provider.displayName, systemImage: provider.symbolName)
                                .tag(provider)
                        }
                    }
                } footer: {
                    Text("Wird im Wein-Berater vorausgewählt und lässt sich dort jederzeit umschalten.")
                }

                ForEach(AIProvider.allCases) { provider in
                    ProviderSettingsSection(provider: provider)
                }

                Section {
                    Label {
                        Text("API-Keys werden ausschließlich in der Keychain dieses Geräts gespeichert und nur an den jeweiligen Anbieter gesendet.")
                    } icon: {
                        Image(systemName: "lock.shield")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Einstellungen")
        }
    }
}

// MARK: - Abschnitt pro Anbieter

private struct ProviderSettingsSection: View {

    let provider: AIProvider

    @Environment(AISettings.self) private var settings
    @State private var apiKey = ""
    @State private var model = ""
    @State private var isKeyVisible = false
    @State private var keychainError: String?

    var body: some View {
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

            LabeledContent("Modell") {
                TextField(provider.defaultModel, text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .font(.callout.monospaced())
            }

            if let keychainError {
                Text(keychainError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            HStack {
                Label(provider.displayName, systemImage: provider.symbolName)
                Spacer()
                if settings.hasAPIKey(for: provider) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Key hinterlegt")
                }
            }
        } footer: {
            Text(provider.apiKeyHint)
        }
        .onAppear {
            apiKey = settings.apiKey(for: provider)
            model = settings.customModel(for: provider)
        }
        .onChange(of: apiKey) { _, newValue in
            do {
                try settings.setAPIKey(newValue, for: provider)
                keychainError = nil
            } catch {
                keychainError = error.localizedDescription
            }
        }
        .onChange(of: model) { _, newValue in
            settings.setCustomModel(newValue, for: provider)
        }
    }
}

#Preview {
    SettingsView()
        .environment(AISettings(defaults: PreviewData.defaults))
}
