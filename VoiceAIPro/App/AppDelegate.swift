import UIKit
import PushKit
import UserNotifications

/// App delegate handling system-level events, push notifications, and VoIP registration
class AppDelegate: NSObject, UIApplicationDelegate {
    /// Push registry for VoIP push notifications
    private var pushRegistry: PKPushRegistry?

    /// VoIP device token for Twilio registration
    private(set) var voipDeviceToken: Data?

    /// Standard push device token
    private(set) var pushDeviceToken: Data?

    // MARK: - Application Lifecycle

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register for push notifications
        registerForPushNotifications()

        // Register for VoIP push notifications
        registerForVoIPPushNotifications()

        // Initialize Twilio Voice SDK (deferred until service initialization)
        // TwilioVoiceService initialization happens in DIContainer

        print("[AppDelegate] Application launched")
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        pushDeviceToken = deviceToken
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("[AppDelegate] Push device token: \(tokenString)")

        // Forward to Twilio service
        NotificationCenter.default.post(
            name: .pushTokenReceived,
            object: nil,
            userInfo: ["token": deviceToken]
        )
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[AppDelegate] Failed to register for push notifications: \(error)")
    }

    // MARK: - Push Notifications

    private func registerForPushNotifications() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[AppDelegate] Notification authorization error: \(error)")
                return
            }

            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    private func registerForVoIPPushNotifications() {
        pushRegistry = PKPushRegistry(queue: .main)
        pushRegistry?.delegate = self
        pushRegistry?.desiredPushTypes = [.voIP]
    }
}

// MARK: - PKPushRegistryDelegate

extension AppDelegate: PKPushRegistryDelegate {
    func pushRegistry(
        _ registry: PKPushRegistry,
        didUpdate pushCredentials: PKPushCredentials,
        for type: PKPushType
    ) {
        guard type == .voIP else { return }

        voipDeviceToken = pushCredentials.token
        let tokenString = pushCredentials.token.map { String(format: "%02.2hhx", $0) }.joined()
        print("[AppDelegate] VoIP device token: \(tokenString)")

        // Forward to Twilio service for registration
        NotificationCenter.default.post(
            name: .voipTokenReceived,
            object: nil,
            userInfo: ["token": pushCredentials.token]
        )
    }

    func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping () -> Void
    ) {
        guard type == .voIP else {
            completion()
            return
        }

        print("[AppDelegate] Received VoIP push: \(payload.dictionaryPayload)")

        // CRITICAL: Must report to CallKit within this callback
        // Otherwise iOS will terminate the app for not handling VoIP push correctly
        NotificationCenter.default.post(
            name: .incomingVoIPPush,
            object: nil,
            userInfo: ["payload": payload.dictionaryPayload]
        )

        // Completion will be called after CallKit reports the call
        // This is handled by TwilioVoiceService
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            completion()
        }
    }

    func pushRegistry(
        _ registry: PKPushRegistry,
        didInvalidatePushTokenFor type: PKPushType
    ) {
        guard type == .voIP else { return }

        voipDeviceToken = nil
        print("[AppDelegate] VoIP push token invalidated")

        // Notify service to unregister from Twilio
        NotificationCenter.default.post(
            name: .voipTokenInvalidated,
            object: nil
        )
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Handle notification tap
        let userInfo = response.notification.request.content.userInfo
        print("[AppDelegate] Notification tapped: \(userInfo)")

        NotificationCenter.default.post(
            name: .notificationTapped,
            object: nil,
            userInfo: userInfo
        )

        completionHandler()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let pushTokenReceived = Notification.Name("pushTokenReceived")
    static let voipTokenReceived = Notification.Name("voipTokenReceived")
    static let voipTokenInvalidated = Notification.Name("voipTokenInvalidated")
    static let incomingVoIPPush = Notification.Name("incomingVoIPPush")
    static let notificationTapped = Notification.Name("notificationTapped")
}
