import CloudKit
import OSLog
import SwiftUI
import UIKit

/// Nimmt Freigabe-Einladungen entgegen.
///
/// Eine Einladung erreicht die App auf **zwei** Wegen, je nachdem, ob sie beim Tippen
/// auf den Link schon läuft:
///
/// - **App läuft bereits** (Vorder- oder Hintergrund): iOS ruft
///   `windowScene(_:userDidAcceptCloudKitShareWith:)` auf.
/// - **App wird durch den Link erst gestartet**: Es gibt noch keine Szene, die man rufen
///   könnte. Die Daten liegen stattdessen in `UIScene.ConnectionOptions.cloudKitShareMetadata`
///   und müssen in `scene(_:willConnectTo:options:)` abgeholt werden.
///
/// Der zweite Weg fehlte lange. Die Einladung ging dann spurlos verloren: kein Fehler,
/// keine Meldung, beim Gast erschien nur nie ein Keller. Ob es klappte, hing allein davon
/// ab, ob die App zufällig noch im Hintergrund lief – deshalb liess sich der Fehler mal
/// reproduzieren und mal nicht.
///
/// Die App-Delegate-Variante ist seit iOS 26 abgekündigt und wird nicht mehr genutzt.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {

    private static let logger = Logger(subsystem: "com.weinkeller.app", category: "Persistence")

    /// Kalter Start durch den Einladungslink.
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let metadata = connectionOptions.cloudKitShareMetadata else { return }
        Self.logger.info("Einladung beim Start empfangen.")
        PersistenceController.shared.acceptShare(metadata)
    }

    /// App lief bereits, als der Link getippt wurde.
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Self.logger.info("Einladung im Betrieb empfangen.")
        PersistenceController.shared.acceptShare(metadata)
    }
}

/// Verbindet den Szenen-Delegate mit der SwiftUI-App.
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}
