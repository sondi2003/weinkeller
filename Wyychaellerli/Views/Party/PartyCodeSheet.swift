import SwiftUI

/// Code-Abfrage – zum Starten des Party-Modus und zum Verlassen.
///
/// Face ID steht daneben, damit der Gastgeber nicht ausgesperrt ist, wenn er den Code
/// vergisst. Gäste kommen mit beidem nicht weiter.
struct PartyCodeSheet: View {

    let title: String
    let message: String
    let onSuccess: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isWrong = false
    @FocusState private var isFocused: Bool

    private var biometry: String? { PartyLock.biometryName }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 24)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                SecureField("Code", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .multilineTextAlignment(.center)
                    .font(.title2.monospacedDigit())
                    .padding(.vertical, 12)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .focused($isFocused)
                    .onChange(of: code) { _, _ in isWrong = false }

                if isWrong {
                    Label("Der Code stimmt nicht.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button {
                    check()
                } label: {
                    Text("Weiter")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(code.count < PartyLock.minimumLength)

                if let biometry {
                    Button {
                        Task {
                            if await PartyLock.authenticate(reason: message) {
                                succeed()
                            }
                        }
                    } label: {
                        Label("Mit \(biometry) entsperren", systemImage: biometry == "Face ID" ? "faceid" : "touchid")
                            .font(.subheadline)
                    }
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium])
    }

    private func check() {
        if PartyLock.matches(code) {
            succeed()
        } else {
            isWrong = true
            code = ""
        }
    }

    private func succeed() {
        dismiss()
        onSuccess()
    }
}
