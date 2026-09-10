import CoreData
import CryptoKit
import Foundation
import LocalAuthentication

/// Der Code, mit dem der Party-Modus gestartet und wieder verlassen wird.
///
/// **Er hängt am Keller, nicht am Gerät.** Wird der Keller geteilt, kann die Partnerin
/// den Party-Modus mit demselben Code starten, und auf dem iPad gilt er auch. Alles
/// andere wäre inkonsequent: Wer den Keller hat, darf auch eine Party machen.
///
/// Gespeichert wird nur ein **gesalzener Hash** – der Code selbst steht nirgends, weder
/// auf dem Gerät noch in iCloud. Das Salz ist die Kennung des Kellers, damit derselbe
/// Code in zwei Kellern nicht denselben Hash ergibt. Das ist kein Schutz gegen Angreifer
/// (wer die Datenbank hat, hat ohnehin alle Weine), sondern gegen neugierige Gäste mit
/// dem Gerät in der Hand; dafür genügen vier Ziffern.
enum PartyLock {

    static let minimumLength = 4
    static let maximumLength = 8

    /// Alter, gerätelokaler Speicherort. Wird nur noch aufgeräumt.
    private static let legacyAccount = "party.passcode"

    // MARK: Zustand

    /// `true`, sobald für den aktiven Keller ein Code hinterlegt ist.
    static func isConfigured(in context: NSManagedObjectContext) -> Bool {
        guard let cellar = Cellar.current(in: context) else { return false }
        return !cellar.partyCodeHash.isEmpty
    }

    static func set(_ code: String, in context: NSManagedObjectContext) {
        let cellar = Cellar.active(in: context)
        cellar.partyCodeHash = hash(code, for: cellar)
        context.saveChanges()
        clearLegacy()
    }

    static func remove(in context: NSManagedObjectContext) {
        guard let cellar = Cellar.current(in: context) else { return }
        cellar.partyCodeHash = ""
        context.saveChanges()
        clearLegacy()
    }

    static func matches(_ code: String, in context: NSManagedObjectContext) -> Bool {
        guard let cellar = Cellar.current(in: context), !cellar.partyCodeHash.isEmpty else { return false }
        return cellar.partyCodeHash == hash(code, for: cellar)
    }

    static func isValidFormat(_ code: String) -> Bool {
        let digits = code.filter(\.isNumber)
        return digits.count == code.count && (minimumLength...maximumLength).contains(digits.count)
    }

    // MARK: Hash

    private static func hash(_ code: String, for cellar: Cellar) -> String {
        let salt = cellar.uuid?.uuidString ?? cellar.objectID.uriRepresentation().absoluteString
        let data = Data((salt + "|" + code).utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Aus der Zeit, als der Code gerätelokal lag. Einmal wegräumen genügt.
    private static func clearLegacy() {
        try? KeychainStore.set("", for: legacyAccount)
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

    /// Fragt Face ID bzw. Touch ID. Liefert `false`, wenn es nicht klappt oder nicht
    /// verfügbar ist – der Code bleibt dann der Weg.
    ///
    /// Das ist der Notausgang: Wer den Code vergisst, wäre sonst in der eigenen App
    /// gefangen, denn ein Neustart hilft bewusst nicht.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = ""
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)) ?? false
    }
}
