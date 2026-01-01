import UIKit
import PushKit
import UserNotifications
import CallKit

/// App delegate handling system-level events, push notifications, and VoIP registration
class AppDelegate: NSObject, UIApplicationDelegate {
    /// Push registry for VoIP push notifications
    private var pushRegistry: PKPushRegistry?

    /// VoIP device token for Twilio registration
    private(set) var voipDeviceToken: Data?

    /// Standard push device token
    private(set) var pushDeviceToken: Data?

    /// Reference to call manager for handling VoIP pushes
    weak var callManager: CallManager?

    /// Pending VoIP push that needs to be handled once services are ready
    private var pendingVoIPPush: (payload: [AnyHashable: Any], completion: () -> Void)?

    // MARK: - Application Lifecycle

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Configure user notifications delegate
        UNUserNotificationCenter.current().delegate = self

        // Register for push notifications
        registerForPushNotifications()

        // Register for VoIP push notifications
        registerForVoIPPushNotifications()

        // Configure default audio session
        do {
            try AudioSessionManager.shared.configureForVoIP()
        } catch {
            print("[AppDelegate] Failed to configure audio session: \(error)")
        }

        print("[AppDelegate] Application launched")
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Clear badge count
        application.applicationIconBadgeNumber = 0

        // Handle any pending VoIP push
        if let pending = pendingVoIPPush {
            handleVoIPPush(payload: pending.payload, completion: pending.completion)
            pendingVoIPPush = nil
        }
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // App is going to background
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Ensure we keep audio session active for active calls
        if callManager?.hasActiveCall == true {
            // Request background task to keep call alive
            var backgroundTask: UIBackgroundTaskIdentifier = .invalid
            backgroundTask = application.beginBackgroundTask {
                application.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
        }
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

        // CRITICAL: Must report to CallKit IMMEDIATELY within this callback
        // iOS will terminate the app if we don't report to CallKit quickly
        handleVoIPPush(payload: payload.dictionaryPayload, completion: completion)
    }

    /// Handle VoIP push notification - MUST report to CallKit immediately
    private func handleVoIPPush(payload: [AnyHashable: Any], completion: @escaping () -> Void) {
        // Check if call manager is ready
        guard let callManager = callManager else {
            // Store for later handling and still report to CallKit
            pendingVoIPPush = (payload, completion)

            // We MUST still report to CallKit even if services aren't ready
            // Create a temporary incoming call report
            reportEmergencyIncomingCall(payload: payload, completion: completion)
            return
        }

        // Notify observers
        NotificationCenter.default.post(
            name: .incomingVoIPPush,
            object: nil,
            userInfo: ["payload": payload]
        )

        // Handle through call manager
        Task { @MainActor in
            await callManager.handleIncomingPush(payload: payload)
            completion()
        }
    }

    /// Emergency fallback to report incoming call to CallKit when services aren't ready
    private func reportEmergencyIncomingCall(payload: [AnyHashable: Any], completion: @escaping () -> Void) {
        // Extract caller info from payload
        let from = payload["twi_from"] as? String ?? "Unknown"
        let callUUID = UUID()

        // Create provider configuration
        let configuration = CXProviderConfiguration(localizedName: Constants.App.name)
        configuration.supportsVideo = false
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.phoneNumber]

        let provider = CXProvider(configuration: configuration)

        // Create call update
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .phoneNumber, value: from)
        update.localizedCallerName = from.formattedPhoneNumber
        update.hasVideo = false

        // Report the incoming call
        provider.reportNewIncomingCall(with: callUUID, update: update) { error in
            if let error = error {
                print("[AppDelegate] Failed to report emergency incoming call: \(error)")
            }
            completion()
        }

        // Store reference to handle call actions
        // This will be replaced by proper handling once CallManager is ready
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
