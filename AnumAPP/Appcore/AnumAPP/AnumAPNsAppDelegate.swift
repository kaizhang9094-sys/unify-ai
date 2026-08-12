import UIKit
import UserNotifications
import CryptoKit

/// Bridges APNs + `UserNotifications` into `AppServices` without wiring push from SwiftUI `@main` directly.
///
/// Xcode capabilities still required manually:
/// - **Signing & Capabilities** → Push Notifications.
/// - **Background Modes** → Remote notifications.
/// Upload environment follows the signed `aps-environment` entitlement (see `APNsSignedEntitlementEnvironment`).
final class AnumAPNsAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    weak var services: AppServices?

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard let services else {
            print("[APNs] warning: AppServices not bound — token dropped until app attaches delegate")
            return
        }

        Task { @MainActor in
            services.handleAPNsDeviceToken(deviceToken)
        }
    }

    func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        guard let services else {
            print("[APNs][RegisterFailure] error=\(error.localizedDescription) servicesUnbound=true")
            return
        }

        Task { @MainActor in
            services.handleAPNsRegistrationFailure(error)
        }
    }

    func application(
        _: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            guard let services else {
                completionHandler(.failed)
                return
            }

            let result = await services.handleSilentSecretaryPush(userInfo: userInfo)
            completionHandler(result)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        let appState = UIApplication.shared.applicationState == .active ? "foreground" : "background"
        print(
            "[RemotePushReceived] appState=\(appState) " +
            "secretaryKind=\(Self.secretaryKind(from: userInfo) ?? "nil") " +
            "threadID=\(Self.secretaryThreadID(from: userInfo) ?? "nil")"
        )
        if let services {
            services.handleForegroundSecretaryPushDelivery(userInfo: userInfo)
        }
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        guard let services else {
            completionHandler()
            return
        }

        Task { @MainActor in
            print(
                "[APNS][didReceive] action=notificationTap willAwaitRemoteSecretaryNotification=true " +
                "secretaryKind=\(Self.secretaryKind(from: userInfo) ?? "nil") " +
                "threadID=\(Self.secretaryThreadID(from: userInfo) ?? "nil")"
            )
            await services.handleRemoteSecretaryNotification(userInfo: userInfo)
            print("[BackgroundNotificationTapSync][completion] completionHandlerCalled=true")
            completionHandler()
        }
    }
}

private extension AnumAPNsAppDelegate {
    static func secretaryKind(from userInfo: [AnyHashable: Any]) -> String? {
        guard let unify = userInfo["unify"] as? [String: Any],
              let sec = unify["secretary"] as? [String: Any],
              let kind = sec["kind"] as? String
        else { return nil }
        let trimmed = kind.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func secretaryThreadID(from userInfo: [AnyHashable: Any]) -> String? {
        guard let unify = userInfo["unify"] as? [String: Any],
              let sec = unify["secretary"] as? [String: Any]
        else { return nil }
        let raw = (sec["threadID"] as? String) ?? (sec["threadId"] as? String)
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
