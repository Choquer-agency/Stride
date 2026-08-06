import UIKit
import SwiftUI

/// Minimal UIKit AppDelegate adapter required to receive APNs callbacks.
/// SwiftUI's `App` lifecycle doesn't expose `application:didRegisterForRemoteNotifications:`
/// so we plug in a UIApplicationDelegateAdaptor in StrideApp.swift.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Set the UNUserNotificationCenter delegate as early as possible so taps
        // received before SwiftUI scenes initialize aren't dropped.
        _ = PushNotificationManager.shared
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationManager.shared.didRegister(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushNotificationManager.shared.didFailToRegister(error: error)
        }
    }
}
