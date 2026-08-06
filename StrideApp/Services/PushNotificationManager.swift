import Foundation
import UIKit
import UserNotifications
import os.log

private let pushLog = Logger(subsystem: "com.stride.app", category: "Push")

/// Manages APNs registration + notification taps.
///
/// Flow:
/// 1. After auth, call `requestAuthorization()` once. If granted, iOS calls
///    `application:didRegisterForRemoteNotificationsWithDeviceToken:` on the
///    AppDelegate, which forwards here.
/// 2. We convert the token to hex and POST to `/api/devices/register`.
/// 3. When a push arrives and the user taps, iOS calls `userNotificationCenter:didReceive:`.
///    We parse `deep_link` from the userInfo payload and hand it to `DeepLinkRouter`.
///
/// Per-loop `coaching_modes` and rate limits live entirely server-side
/// (see `app/services/push_service.py`). The iOS layer is just plumbing.
@MainActor
final class PushNotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = PushNotificationManager()

    @Published private(set) var permissionStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var deviceToken: String?

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        Task { await refreshPermissionStatus() }
    }

    // MARK: - Permission + registration

    /// Ask iOS for notification permission. Idempotent — safe to call multiple times.
    /// On grant, iOS will fire `didRegisterForRemoteNotifications` on the AppDelegate.
    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            await refreshPermissionStatus()
            if granted {
                await registerForRemoteNotifications()
            } else {
                pushLog.info("Notification permission denied by user")
            }
        } catch {
            pushLog.error("Notification permission request failed: \(error.localizedDescription)")
        }
    }

    /// If permission was previously granted, re-register for remote notifications
    /// (token can rotate after restore/reinstall). Safe to call on every app launch.
    func reregisterIfAuthorized() async {
        await refreshPermissionStatus()
        if permissionStatus == .authorized || permissionStatus == .provisional {
            await registerForRemoteNotifications()
        }
    }

    private func refreshPermissionStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        permissionStatus = settings.authorizationStatus
    }

    @MainActor
    private func registerForRemoteNotifications() async {
        UIApplication.shared.registerForRemoteNotifications()
    }

    // MARK: - Token handoff (called from AppDelegate)

    /// Called from `application:didRegisterForRemoteNotificationsWithDeviceToken:`.
    /// Converts to hex, stashes locally, posts to backend.
    func didRegister(deviceToken raw: Data) {
        let hex = raw.map { String(format: "%02x", $0) }.joined()
        deviceToken = hex
        pushLog.info("APNs token: \(hex.prefix(12))…\(hex.suffix(8))")
        Task { await postTokenToBackend(hex: hex) }
    }

    func didFailToRegister(error: Error) {
        pushLog.error("APNs registration failed: \(error.localizedDescription)")
    }

    private func postTokenToBackend(hex: String) async {
        do {
            try await APIService.shared.registerDeviceToken(hex: hex)
            pushLog.info("Device token registered with backend")
        } catch {
            pushLog.error("registerDeviceToken failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Notification taps

    /// User tapped a notification (or interacted with an action).
    /// Parses the `deep_link` field from the payload and routes it.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        if let linkString = userInfo["deep_link"] as? String, let url = URL(string: linkString) {
            await MainActor.run { DeepLinkRouter.shared.handle(url: url) }
        }
    }

    /// Show notifications even when the app is in foreground (instead of swallowing them).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge]
    }
}
