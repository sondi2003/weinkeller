import SwiftUI

/// Tab 3: API-Keys (Keychain) und Modellnamen pro Anbieter.
///
/// Der Anbieter mit hinterlegtem Key ist automatisch aktiv. Nur wenn mehrere
/// Keys hinterlegt sind, erscheint eine Auswahl, welcher bevorzugt wird.
struct SettingsView: View {

    @Environment(AISettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    activeProviderRow

                    if settings.hasMultipleProviders {
                        Picker("Bevorzugter Anbieter", selection: $settings.preferredProvider) {
                            ForEach(settings.configuredProviders) { provider in
                                Label(provider.displayName, systemImage: provider.symbolName)
                                    .tag(provider)
                            }
                        }
                    }
                } header: {
                    Text("Aktiv")
                } footer: {
                    if settings.hasMultipleProviders {
                        Text("Du hast mehrere Keys hinterlegt. Der bevorzugte Anbieter wird für Empfehlungen verwendet.")
                    } else if settings.activeProvider == nil {
                        Text("Trage unten den API-Key eines Anbieters ein – er wird dann automatisch verwendet.")
                    } else {
                        Text("Der Anbieter mit hinterlegtem Key wird automatisch verwendet. Für einen Wechsel einfach den Key beim anderen Anbieter eintragen.")
                    }
                }

                CellarSharingSection()

                ForEach(AIProvider.allCases) { provider in
                    ProviderSettingsSection(provider: provider)
                }

                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("„Hey Siri, Wein-Berater in Weinkeller“")
                                .font(.footnote.weight(.semibold))
                            Text("Siri fragt danach, was es zu essen gibt, und liest die Empfehlung vor. Der App-Name muss im Satz vorkommen, das verlangt Apple. Für Siri wird das schnellere Modell verwendet.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "mic")
                    }
                } header: {
                    Text("Siri")
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

    /// Visuelle Bestätigung: welcher Anbieter und welches Modell gerade aktiv sind.
    @ViewBuilder
    private var activeProviderRow: some View {
        if let provider = settings.activeProvider {
            HStack(spacing: 12) {
                Image(systemName: provider.symbolName)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .font(.body.weight(.semibold))
                    Text(settings.model(for: provider))
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Aktiv")
            }
            .padding(.vertical, 4)
        } else {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kein Anbieter eingerichtet")
                        .font(.body.weight(.semibold))
                    Text("Der Wein-Berater braucht einen API-Key.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Abschnitt pro Anbieter

private struct ProviderSettingsSection: View {

    let provider: AIProvider

    @Environment(AISettings.self) private var settings
    @State private var apiKey = ""
    @State private var model = ""
    @State private var fastModel = ""
    @State private var isKeyVisible = false
    @State private var keychainError: String?

    private var isActive: Bool { settings.activeProvider == provider }

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

            LabeledContent("Modell für Siri") {
                TextField(provider.defaultFastModel, text: $fastModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .font(.callout.monospaced())
            }

            if settings.hasAPIKey(for: provider) {
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
            HStack {
                Label(provider.displayName, systemImage: provider.symbolName)
                Spacer()
                if isActive {
                    Text("Aktiv")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else if settings.hasAPIKey(for: provider) {
                    Text("Key hinterlegt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text(provider.apiKeyHint)
        }
        .onAppear {
            apiKey = settings.apiKey(for: provider)
            model = settings.customModel(for: provider)
            fastModel = settings.customFastModel(for: provider)
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
        .onChange(of: fastModel) { _, newValue in
            settings.setCustomFastModel(newValue, for: provider)
        }
    }
}

#Preview {
    SettingsView()
        .environment(AISettings(defaults: PreviewData.defaults))
}
