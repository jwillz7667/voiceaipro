import Foundation
import Combine
import CallKit
import AVFoundation
import PushKit

// MARK: - TwilioVoice Protocol Abstractions
// These protocols mirror the TwilioVoice SDK types for compilation without the SDK

/// Protocol representing a Twilio Voice call
protocol TVOCallProtocol: AnyObject {
    var uuid: UUID { get }
    var sid: String? { get }
    var state: TVOCallState { get }
    var isMuted: Bool { get set }
    var isOnHold: Bool { get set }

    func disconnect()
    func sendDigits(_ digits: String)
}

/// Protocol representing a call invite
protocol TVOCallInviteProtocol: AnyObject {
    var uuid: UUID { get }
    var callSid: String { get }
    var from: String { get }
    var to: String { get }

    func accept(with delegate: Any) -> TVOCallProtocol
    func reject()
}

/// Protocol representing a cancelled call invite
protocol TVOCancelledCallInviteProtocol: AnyObject {
    var callSid: String { get }
}

/// Call states matching Twilio SDK
enum TVOCallState: Int {
    case connecting = 0
    case ringing = 1
    case connected = 2
    case reconnecting = 3
    case disconnected = 4
}

/// Call quality warnings
struct TVOCallQualityWarning: OptionSet {
    let rawValue: Int

    static let highRtt = TVOCallQualityWarning(rawValue: 1 << 0)
    static let highJitter = TVOCallQualityWarning(rawValue: 1 << 1)
    static let highPacketLoss = TVOCallQualityWarning(rawValue: 1 << 2)
    static let lowMos = TVOCallQualityWarning(rawValue: 1 << 3)
    static let constantAudioInputLevel = TVOCallQualityWarning(rawValue: 1 << 4)
}

// MARK: - TwilioVoiceService

/// Service managing Twilio Voice SDK integration
/// Handles VoIP calling, push notifications, and call lifecycle
@MainActor
class TwilioVoiceService: NSObject, ObservableObject {
    // MARK: - Published Properties

    /// Whether the device is registered for incoming calls
    @Published private(set) var isRegistered: Bool = false

    /// Current active call
    @Published private(set) var activeCall: TVOCallProtocol?

    /// Pending incoming call invite
    @Published private(set) var callInvite: TVOCallInviteProtocol?

    /// Current call state
    @Published private(set) var callState: TVOCallState = .disconnected

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
    @Published private(set) var qualityWarnings: TVOCallQualityWarning = []

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

    // MARK: - Callbacks

    /// Called when call connects
    var onCallConnected: ((TVOCallProtocol) -> Void)?

    /// Called when call disconnects
    var onCallDisconnected: ((TVOCallProtocol?, Error?) -> Void)?

    /// Called when incoming call received
    var onIncomingCall: ((TVOCallInviteProtocol) -> Void)?

    /// Called on quality warning
    var onQualityWarning: ((TVOCallQualityWarning) -> Void)?

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
        // Fetch initial access token
        accessToken = try await fetchAccessToken()

        // Configure logging in debug mode
        #if DEBUG
        // TwilioVoiceSDK.setLogLevel(.debug, module: .core)
        #endif
    }

    /// Register for push notifications
    func registerForPushNotifications(deviceToken: Data) {
        self.deviceToken = deviceToken

        guard let token = accessToken else {
            lastError = TwilioError.notInitialized
            return
        }

        // In real implementation:
        // TwilioVoiceSDK.register(accessToken: token, deviceToken: deviceToken) { error in
        //     if let error = error {
        //         self.lastError = error
        //         self.isRegistered = false
        //     } else {
        //         self.isRegistered = true
        //     }
        // }

        // Simulated registration
        isRegistered = true
    }

    /// Unregister from push notifications
    func unregister() {
        guard let token = accessToken, let deviceToken = deviceToken else { return }

        // In real implementation:
        // TwilioVoiceSDK.unregister(accessToken: token, deviceToken: deviceToken) { error in
        //     self.isRegistered = false
        // }

        isRegistered = false
    }

    // MARK: - Call Management

    /// Make an outbound call
    /// - Parameters:
    ///   - phoneNumber: The phone number to call
    ///   - params: Additional parameters for the call
    /// - Returns: The created call object
    func makeCall(to phoneNumber: String, params: [String: String] = [:]) async throws -> TVOCallProtocol {
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

        // Report to CallKit
        try await callKitManager?.startCall(uuid: callUUID, handle: phoneNumber)

        // In real implementation:
        // let connectOptions = ConnectOptions(accessToken: token) { builder in
        //     builder.params = connectParams
        //     builder.uuid = callUUID
        // }
        // let call = TwilioVoiceSDK.connect(options: connectOptions, delegate: self)

        // Create simulated call for now
        let call = SimulatedTVOCall(uuid: callUUID, phoneNumber: phoneNumber)
        activeCall = call
        callState = .connecting

        return call
    }

    /// Accept an incoming call
    /// - Returns: The accepted call object
    func acceptIncomingCall() throws -> TVOCallProtocol {
        guard let invite = callInvite else {
            throw TwilioError.noIncomingCall
        }

        // In real implementation:
        // let acceptOptions = AcceptOptions(callInvite: invite) { builder in
        //     // Configure accept options
        // }
        // let call = invite.accept(with: acceptOptions, delegate: self)

        // Simulated acceptance
        let call = invite.accept(with: self)
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
        // In real implementation:
        // TwilioVoiceSDK.handleNotification(payload, delegate: self, delegateQueue: nil)

        // Parse the payload and create call invite
        if let callSid = payload["twi_call_sid"] as? String,
           let from = payload["twi_from"] as? String,
           let to = payload["twi_to"] as? String {

            let invite = SimulatedCallInvite(
                callSid: callSid,
                from: from,
                to: to
            )

            Task { @MainActor in
                self.callInvite = invite
                self.onIncomingCall?(invite)

                // Report to CallKit
                do {
                    try await self.callKitManager?.reportIncomingCall(
                        uuid: invite.uuid,
                        handle: from
                    )
                } catch {
                    self.lastError = error
                }

                completion()
            }
        } else {
            completion()
        }
    }

    /// Handle cancelled push notification
    func handleCancelledPushNotification(_ payload: [AnyHashable: Any]) {
        if let callSid = payload["twi_call_sid"] as? String {
            // Find and cancel matching invite
            if callInvite?.callSid == callSid {
                if let uuid = callInvite?.uuid {
                    callKitManager?.reportCallEnded(uuid: uuid, reason: .remoteEnded)
                }
                callInvite = nil
            }
        }
    }
}

// MARK: - TVOCallDelegate Simulation

extension TwilioVoiceService {
    /// Called when call fails to connect
    func call(_ call: TVOCallProtocol, didFailToConnectWithError error: Error) {
        lastError = error
        callState = .disconnected
        activeCall = nil

        callKitManager?.reportCallEnded(uuid: call.uuid, reason: .failed)
        onCallDisconnected?(call, error)
    }

    /// Called when call starts ringing
    func callDidStartRinging(_ call: TVOCallProtocol) {
        callState = .ringing
    }

    /// Called when call connects
    func callDidConnect(_ call: TVOCallProtocol) {
        callState = .connected
        callKitManager?.reportCallConnected(uuid: call.uuid)
        onCallConnected?(call)
    }

    /// Called when call disconnects
    func call(_ call: TVOCallProtocol, didDisconnectWithError error: Error?) {
        if let error = error {
            lastError = error
        }

        callState = .disconnected
        activeCall = nil
        isMuted = false
        qualityWarnings = []

        let reason: CXCallEndedReason = error != nil ? .failed : .remoteEnded
        callKitManager?.reportCallEnded(uuid: call.uuid, reason: reason)
        onCallDisconnected?(call, error)
    }

    /// Called when call is reconnecting
    func call(_ call: TVOCallProtocol, isReconnectingWithError error: Error) {
        callState = .reconnecting
        lastError = error
    }

    /// Called when call reconnects
    func callDidReconnect(_ call: TVOCallProtocol) {
        callState = .connected
        lastError = nil
    }

    /// Called when quality warnings change
    func call(_ call: TVOCallProtocol, didReceiveQualityWarnings currentWarnings: TVOCallQualityWarning, previousWarnings: TVOCallQualityWarning) {
        qualityWarnings = currentWarnings
        onQualityWarning?(currentWarnings)
    }
}

// MARK: - TVONotificationDelegate Simulation

extension TwilioVoiceService {
    /// Called when call invite is received
    func callInviteReceived(_ callInvite: TVOCallInviteProtocol) {
        self.callInvite = callInvite
        onIncomingCall?(callInvite)
    }

    /// Called when call invite is cancelled
    func cancelledCallInviteReceived(_ cancelledCallInvite: TVOCancelledCallInviteProtocol, error: Error?) {
        if callInvite?.callSid == cancelledCallInvite.callSid {
            if let uuid = callInvite?.uuid {
                callKitManager?.reportCallEnded(uuid: uuid, reason: .remoteEnded)
            }
            callInvite = nil
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

// MARK: - Simulated Call Types (Remove when using real SDK)

/// Simulated call for development without TwilioVoice SDK
class SimulatedTVOCall: TVOCallProtocol {
    let uuid: UUID
    var sid: String?
    var state: TVOCallState = .connecting
    var isMuted: Bool = false
    var isOnHold: Bool = false

    private let phoneNumber: String

    init(uuid: UUID, phoneNumber: String) {
        self.uuid = uuid
        self.phoneNumber = phoneNumber
        self.sid = "CA\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(32))"
    }

    func disconnect() {
        state = .disconnected
    }

    func sendDigits(_ digits: String) {
        // Simulated DTMF
    }
}

/// Simulated call invite for development without TwilioVoice SDK
class SimulatedCallInvite: TVOCallInviteProtocol {
    let uuid: UUID
    let callSid: String
    let from: String
    let to: String

    init(callSid: String, from: String, to: String) {
        self.uuid = UUID()
        self.callSid = callSid
        self.from = from
        self.to = to
    }

    func accept(with delegate: Any) -> TVOCallProtocol {
        let call = SimulatedTVOCall(uuid: uuid, phoneNumber: from)
        call.state = .connected
        return call
    }

    func reject() {
        // Simulated rejection
    }
}
