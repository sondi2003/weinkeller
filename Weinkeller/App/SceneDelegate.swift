import CloudKit
import SwiftUI
import UIKit

/// Nimmt Freigabe-Einladungen entgegen.
///
/// Tippt die eingeladene Person auf den Link, öffnet iOS die App und ruft diese Methode
/// auf. Ohne Szenen-Delegate gäbe es keinen Ort dafür; die frühere Variante über den
/// App-Delegate ist seit iOS 26 abgekündigt.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
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
