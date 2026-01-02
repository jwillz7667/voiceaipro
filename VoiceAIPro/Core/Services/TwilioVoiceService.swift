import Foundation
import Combine
import CallKit
import AVFoundation
import PushKit
import TwilioVoice

// MARK: - TwilioVoiceService

/// Service managing Twilio Voice SDK integration
/// Handles VoIP calling, push notifications, and call lifecycle
@MainActor
class TwilioVoiceService: NSObject, ObservableObject {
    // MARK: - Published Properties

    /// Whether the device is registered for incoming calls
    @Published private(set) var isRegistered: Bool = false

    /// Current active call
    @Published private(set) var activeCall: Call?

    /// Pending incoming call invite
    @Published private(set) var callInvite: CallInvite?

    /// Current call state
    @Published private(set) var callState: Call.State = .disconnected

    /// Whether call is muted
    @Published var isMuted: Bool = false {
        didSet {
            activeCall?.isMuted = isMuted
        }
    }

    /// Whether speaker is enabled
    @Published var isSpeakerEnabled: Bool = false {
        didSet {
            try? AudioSessionManager.shared.setSpeakerEnabled(isSpeakerEnabled)
        }
    }

    /// Call quality warnings
    @Published private(set) var qualityWarnings: Set<Call.QualityWarning> = []

    /// Last error
    @Published private(set) var lastError: Error?

    // MARK: - Private Properties

    /// Access token for Twilio
    private var accessToken: String?

    /// Token expiration time
    private var tokenExpiry: Date?

    /// Device token for push notifications
    private var deviceToken: Data?

    /// Weak reference to CallKit manager
    private weak var callKitManager: CallKitManager?

    /// API client for token fetching
    private let apiClient: APIClientProtocol

    /// Device ID for authentication
    private let deviceId: String

    /// Cancellables for Combine
    private var cancellables = Set<AnyCancellable>()

    /// Cancelled call invites
    private var cancelledCallInvites: [CancelledCallInvite] = []

    // MARK: - Callbacks

    /// Called when call connects
    var onCallConnected: ((Call) -> Void)?

    /// Called when call disconnects
    var onCallDisconnected: ((Call?, Error?) -> Void)?

    /// Called when incoming call received
    var onIncomingCall: ((CallInvite) -> Void)?

    /// Called on quality warning
    var onQualityWarning: ((Set<Call.QualityWarning>) -> Void)?

    // MARK: - Initialization

    init(apiClient: APIClientProtocol, deviceId: String) {
        self.apiClient = apiClient
        self.deviceId = deviceId
        super.init()
    }

    /// Set the CallKit manager reference
    func setCallKitManager(_ manager: CallKitManager) {
        self.callKitManager = manager
    }

    // MARK: - Initialization & Registration

    /// Initialize the Twilio Voice SDK
    func initialize() async throws {
        print("[TwilioVoiceService] Initializing, deviceId: \(deviceId)")

        // Fetch initial access token
        do {
            accessToken = try await fetchAccessToken()
            print("[TwilioVoiceService] Token fetched successfully")
        } catch {
            print("[TwilioVoiceService] Token fetch failed: \(error)")
            throw error
        }

        // Mark as registered once we have a valid token
        isRegistered = true
        print("[TwilioVoiceService] isRegistered set to true")

        // Configure logging in debug mode
        #if DEBUG
        TwilioVoiceSDK.setLogLevel(.debug, module: .core)
        #endif
    }

    /// Register for push notifications
    func registerForPushNotifications(deviceToken: Data) {
        self.deviceToken = deviceToken

        guard let token = accessToken else {
            lastError = TwilioError.notInitialized
            return
        }

        TwilioVoiceSDK.register(accessToken: token, deviceToken: deviceToken) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("[TwilioVoiceService] Push registration failed: \(error)")
                    self?.lastError = error
                    self?.isRegistered = false
                } else {
                    print("[TwilioVoiceService] Push registration successful")
                    self?.isRegistered = true
                }
            }
        }
    }

    /// Unregister from push notifications
    func unregister() {
        guard let token = accessToken, let deviceToken = deviceToken else { return }

        TwilioVoiceSDK.unregister(accessToken: token, deviceToken: deviceToken) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("[TwilioVoiceService] Unregister failed: \(error)")
                }
                self?.isRegistered = false
            }
        }
    }

    // MARK: - Call Management

    /// Make an outbound call
    /// - Parameters:
    ///   - phoneNumber: The phone number to call
    ///   - params: Additional parameters for the call
    /// - Returns: The created call object
    func makeCall(to phoneNumber: String, params: [String: String] = [:]) async throws -> Call {
        // Ensure we have a valid token
        try await refreshTokenIfNeeded()

        guard let token = accessToken else {
            throw TwilioError.notInitialized
        }

        // Build connect options
        var connectParams = params
        connectParams["To"] = phoneNumber
        connectParams["DeviceId"] = deviceId

        // Generate UUID for CallKit
        let callUUID = UUID()

        // Report to CallKit (non-blocking - may fail without issue)
        do {
            try await callKitManager?.startCall(uuid: callUUID, handle: phoneNumber)
        } catch {
            // Log but don't fail - CallKit errors are not fatal
            print("[TwilioVoiceService] CallKit startCall failed: \(error.localizedDescription)")
            // Still report the call as outgoing for CallKit UI
            callKitManager?.reportOutgoingCall(uuid: callUUID, handle: phoneNumber)
        }

        // Create connect options
        let connectOptions = ConnectOptions(accessToken: token) { builder in
            builder.params = connectParams
            builder.uuid = callUUID
        }

        // Connect the call
        let call = TwilioVoiceSDK.connect(options: connectOptions, delegate: self)
        activeCall = call
        callState = .connecting

        return call
    }

    /// Accept an incoming call
    /// - Returns: The accepted call object
    func acceptIncomingCall() throws -> Call {
        guard let invite = callInvite else {
            throw TwilioError.noIncomingCall
        }

        // Create accept options
        let acceptOptions = AcceptOptions(callInvite: invite) { builder in
            // Configure accept options if needed
        }

        // Accept the call
        let call = invite.accept(options: acceptOptions, delegate: self)
        activeCall = call
        callInvite = nil
        callState = .connected

        return call
    }

    /// Reject an incoming call
    func rejectIncomingCall() {
        callInvite?.reject()
        callInvite = nil
    }

    /// End the current call
    func endCall() {
        activeCall?.disconnect()

        // Report to CallKit
        if let uuid = activeCall?.uuid {
            Task {
                try? await callKitManager?.endCall(uuid: uuid)
            }
        }
    }

    /// Toggle mute on the current call
    func toggleMute(_ muted: Bool) {
        isMuted = muted
    }

    /// Toggle speaker on the current call
    func toggleSpeaker(_ speaker: Bool) {
        isSpeakerEnabled = speaker
    }

    /// Send DTMF digits
    func sendDigits(_ digits: String) {
        activeCall?.sendDigits(digits)
    }

    // MARK: - Token Management

    /// Fetch a new access token from the server
    func fetchAccessToken() async throws -> String {
        let token = try await apiClient.fetchAccessToken()
        accessToken = token
        tokenExpiry = Date().addingTimeInterval(Constants.Twilio.tokenTTL)
        return token
    }

    /// Refresh token if needed
    func refreshTokenIfNeeded() async throws {
        // Check if token is expired or will expire soon
        if let expiry = tokenExpiry, expiry.timeIntervalSinceNow < 60 {
            _ = try await fetchAccessToken()
        } else if accessToken == nil {
            _ = try await fetchAccessToken()
        }
    }

    // MARK: - Push Notification Handling

    /// Handle incoming VoIP push notification
    /// - Parameters:
    ///   - payload: The push payload
    ///   - completion: Completion handler
    func handlePushNotification(_ payload: [AnyHashable: Any], completion: @escaping () -> Void) {
        TwilioVoiceSDK.handleNotification(payload, delegate: self, delegateQueue: nil)
        completion()
    }

    /// Handle cancelled push notification
    func handleCancelledPushNotification(_ payload: [AnyHashable: Any]) {
        // Cancelled invites are handled by the delegate methods
    }
}

// MARK: - CallDelegate

extension TwilioVoiceService: CallDelegate {
    nonisolated func callDidStartRinging(call: Call) {
        Task { @MainActor in
            callState = .ringing
        }
    }

    nonisolated func callDidConnect(call: Call) {
        Task { @MainActor in
            callState = .connected
            if let uuid = call.uuid {
                callKitManager?.reportCallConnected(uuid: uuid)
            }
            onCallConnected?(call)
        }
    }

    nonisolated func callDidFailToConnect(call: Call, error: any Error) {
        Task { @MainActor in
            lastError = error
            callState = .disconnected
            activeCall = nil

            if let uuid = call.uuid {
                callKitManager?.reportCallEnded(uuid: uuid, reason: .failed)
            }
            onCallDisconnected?(call, error)
        }
    }

    nonisolated func callDidDisconnect(call: Call, error: (any Error)?) {
        Task { @MainActor in
            if let error = error {
                lastError = error
            }

            callState = .disconnected
            activeCall = nil
            isMuted = false
            qualityWarnings = []

            let reason: CXCallEndedReason = error != nil ? .failed : .remoteEnded
            if let uuid = call.uuid {
                callKitManager?.reportCallEnded(uuid: uuid, reason: reason)
            }
            onCallDisconnected?(call, error)
        }
    }

    nonisolated func callIsReconnecting(call: Call, error: any Error) {
        Task { @MainActor in
            callState = .reconnecting
            lastError = error
        }
    }

    nonisolated func callDidReconnect(call: Call) {
        Task { @MainActor in
            callState = .connected
            lastError = nil
        }
    }

    nonisolated func callDidReceiveQualityWarnings(call: Call, currentWarnings: Set<Call.QualityWarning>, previousWarnings: Set<Call.QualityWarning>) {
        Task { @MainActor in
            qualityWarnings = currentWarnings
            onQualityWarning?(currentWarnings)
        }
    }
}

// MARK: - NotificationDelegate

extension TwilioVoiceService: NotificationDelegate {
    nonisolated func callInviteReceived(callInvite: CallInvite) {
        Task { @MainActor in
            self.callInvite = callInvite
            onIncomingCall?(callInvite)

            // Report to CallKit
            do {
                try await callKitManager?.reportIncomingCall(
                    uuid: callInvite.uuid,
                    handle: callInvite.from ?? "Unknown"
                )
            } catch {
                lastError = error
                print("[TwilioVoiceService] Failed to report incoming call: \(error)")
            }
        }
    }

    nonisolated func cancelledCallInviteReceived(cancelledCallInvite: CancelledCallInvite, error: any Error) {
        Task { @MainActor in
            cancelledCallInvites.append(cancelledCallInvite)

            // Find and cancel matching invite
            if callInvite?.callSid == cancelledCallInvite.callSid {
                if let uuid = callInvite?.uuid {
                    callKitManager?.reportCallEnded(uuid: uuid, reason: .remoteEnded)
                }
                callInvite = nil
            }
        }
    }
}

// MARK: - Errors

enum TwilioError: LocalizedError {
    case notInitialized
    case noIncomingCall
    case callFailed(String)
    case registrationFailed(String)
    case tokenError

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Twilio Voice SDK not initialized"
        case .noIncomingCall:
            return "No incoming call to accept"
        case .callFailed(let reason):
            return "Call failed: \(reason)"
        case .registrationFailed(let reason):
            return "Registration failed: \(reason)"
        case .tokenError:
            return "Failed to get access token"
        }
    }
}
