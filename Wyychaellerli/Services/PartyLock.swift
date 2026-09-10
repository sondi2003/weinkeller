import CryptoKit
import Foundation
import LocalAuthentication

/// Der Code, mit dem der Party-Modus gestartet und wieder verlassen wird.
///
/// Gespeichert wird nur der Hash – der Code selbst muss nirgends nachlesbar sein.
/// Das ist kein Schutz gegen Angreifer, sondern gegen neugierige Gäste mit dem Gerät
/// in der Hand; entsprechend genügen vier Ziffern.
///
/// **Face ID ist der zweite Weg hinaus.** Wer den Code vergisst, wäre sonst in der
/// eigenen App gefangen – ein Neustart hilft ja bewusst nicht.
enum PartyLock {

    private static let account = "party.passcode"

    static let minimumLength = 4
    static let maximumLength = 8

    /// `true`, sobald ein Code hinterlegt ist. Ohne Code kein Party-Modus.
    static var isConfigured: Bool { KeychainStore.string(for: account)?.isEmpty == false }

    static func set(_ code: String) throws {
        try KeychainStore.set(hash(code), for: account)
    }

    static func remove() throws {
        try KeychainStore.set("", for: account)
    }

    static func matches(_ code: String) -> Bool {
        guard let stored = KeychainStore.string(for: account), !stored.isEmpty else { return false }
        return stored == hash(code)
    }

    static func isValidFormat(_ code: String) -> Bool {
        let digits = code.filter(\.isNumber)
        return digits.count == code.count && (minimumLength...maximumLength).contains(digits.count)
    }

    private static func hash(_ code: String) -> String {
        let data = Data(code.utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Face ID / Touch ID

    /// Name des vorhandenen Verfahrens („Face ID“, „Touch ID“) oder `nil`.
    static var biometryName: String? {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return nil }
        switch context.biometryType {
        case .faceID:  return "Face ID"
        case .touchID: return "Touch ID"
        default:       return nil
        }
    }

    /// Fragt Face ID bzw. Touch ID. Liefert `false`, wenn es nicht klappt oder
    /// nicht verfügbar ist – der Code bleibt dann der Weg.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = ""
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)) ?? false
    }
}
