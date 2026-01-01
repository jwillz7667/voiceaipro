import Foundation
import CallKit
import AVFoundation

/// Manages CallKit integration for native iOS call UI
/// Handles reporting calls to the system and processing user actions
class CallKitManager: NSObject, ObservableObject {
    // MARK: - Published Properties

    /// Whether there's an active call
    @Published private(set) var hasActiveCall: Bool = false

    /// Current call UUID
    @Published private(set) var currentCallUUID: UUID?

    /// Whether current call is muted
    @Published private(set) var isMuted: Bool = false

    /// Whether current call is on hold
    @Published private(set) var isOnHold: Bool = false

    // MARK: - Private Properties

    /// CallKit call controller for requesting actions
    private let callController: CXCallController

    /// CallKit provider for reporting events
    private let provider: CXProvider

    /// Active calls tracked by UUID
    private var activeCalls: [UUID: CallInfo] = [:]

    // MARK: - Callbacks

    /// Called when user requests to start a call
    var onStartCall: ((UUID, String) async throws -> Void)?

    /// Called when user answers an incoming call
    var onAnswerCall: ((UUID) async throws -> Void)?

    /// Called when user ends a call
    var onEndCall: ((UUID) async throws -> Void)?

    /// Called when user toggles mute
    var onSetMuted: ((UUID, Bool) async throws -> Void)?

    /// Called when user toggles hold
    var onSetHeld: ((UUID, Bool) async throws -> Void)?

    /// Called when audio session is activated
    var onAudioSessionActivated: (() -> Void)?

    /// Called when audio session is deactivated
    var onAudioSessionDeactivated: (() -> Void)?

    // MARK: - Provider Configuration

    /// CallKit provider configuration
    static var providerConfiguration: CXProviderConfiguration {
        let config = CXProviderConfiguration()
        config.localizedName = Constants.App.name
        config.supportsVideo = false
        config.maximumCallsPerCallGroup = 1
        config.maximumCallGroups = 1
        config.supportedHandleTypes = [.phoneNumber, .generic]
        config.includesCallsInRecents = true

        // Set app icon for CallKit UI
        if let iconImage = UIImage(named: "AppIcon") {
            config.iconTemplateImageData = iconImage.pngData()
        }

        // Custom ringtone (optional)
        // config.ringtoneSound = "ringtone.caf"

        return config
    }

    // MARK: - Initialization

    override init() {
        self.callController = CXCallController()
        self.provider = CXProvider(configuration: Self.providerConfiguration)

        super.init()

        self.provider.setDelegate(self, queue: nil)
    }

    deinit {
        provider.invalidate()
    }

    // MARK: - Reporting Events to CallKit

    /// Report an incoming call to CallKit
    /// - Parameters:
    ///   - uuid: Unique identifier for the call
    ///   - handle: Phone number or caller ID
    func reportIncomingCall(uuid: UUID, handle: String) async throws {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .phoneNumber, value: handle)
        update.localizedCallerName = handle.formattedPhoneNumber
        update.hasVideo = false
        update.supportsHolding = true
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = true

        try await provider.reportNewIncomingCall(with: uuid, update: update)

        // Track the call
        activeCalls[uuid] = CallInfo(
            uuid: uuid,
            handle: handle,
            isOutgoing: false,
            startTime: Date()
        )
        currentCallUUID = uuid
        hasActiveCall = true
    }

    /// Report that an outgoing call is starting
    /// - Parameters:
    ///   - uuid: Unique identifier for the call
    ///   - handle: Phone number being called
    func reportOutgoingCall(uuid: UUID, handle: String) {
        provider.reportOutgoingCall(with: uuid, startedConnectingAt: Date())

        // Track the call
        activeCalls[uuid] = CallInfo(
            uuid: uuid,
            handle: handle,
            isOutgoing: true,
            startTime: Date()
        )
        currentCallUUID = uuid
        hasActiveCall = true
    }

    /// Report that a call has connected
    /// - Parameter uuid: Unique identifier for the call
    func reportCallConnected(uuid: UUID) {
        provider.reportOutgoingCall(with: uuid, connectedAt: Date())
        activeCalls[uuid]?.connectedTime = Date()
    }

    /// Report that a call has ended
    /// - Parameters:
    ///   - uuid: Unique identifier for the call
    ///   - reason: Reason the call ended
    func reportCallEnded(uuid: UUID, reason: CXCallEndedReason) {
        provider.reportCall(with: uuid, endedAt: Date(), reason: reason)
        activeCalls.removeValue(forKey: uuid)

        if currentCallUUID == uuid {
            currentCallUUID = nil
            hasActiveCall = false
            isMuted = false
            isOnHold = false
        }
    }

    /// Update call info (e.g., caller ID resolved)
    /// - Parameters:
    ///   - uuid: Unique identifier for the call
    ///   - update: The update to apply
    func updateCall(uuid: UUID, update: CXCallUpdate) {
        provider.reportCall(with: uuid, updated: update)
    }

    // MARK: - Requesting Actions

    /// Request to start an outgoing call
    /// - Parameters:
    ///   - uuid: Unique identifier for the call
    ///   - handle: Phone number to call
    func startCall(uuid: UUID, handle: String) async throws {
        let callHandle = CXHandle(type: .phoneNumber, value: handle)
        let startCallAction = CXStartCallAction(call: uuid, handle: callHandle)
        startCallAction.isVideo = false

        let transaction = CXTransaction(action: startCallAction)
        try await callController.request(transaction)
    }

    /// Request to end a call
    /// - Parameter uuid: Unique identifier for the call
    func endCall(uuid: UUID) async throws {
        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endCallAction)
        try await callController.request(transaction)
    }

    /// Request to set muted state
    /// - Parameters:
    ///   - uuid: Unique identifier for the call
    ///   - muted: Whether to mute
    func setMuted(uuid: UUID, muted: Bool) async throws {
        let muteAction = CXSetMutedCallAction(call: uuid, muted: muted)
        let transaction = CXTransaction(action: muteAction)
        try await callController.request(transaction)
    }

    /// Request to set held state
    /// - Parameters:
    ///   - uuid: Unique identifier for the call
    ///   - onHold: Whether to hold
    func setHeld(uuid: UUID, onHold: Bool) async throws {
        let holdAction = CXSetHeldCallAction(call: uuid, onHold: onHold)
        let transaction = CXTransaction(action: holdAction)
        try await callController.request(transaction)
    }

    /// Request to send DTMF tones
    /// - Parameters:
    ///   - uuid: Unique identifier for the call
    ///   - digits: DTMF digits to send
    func sendDTMF(uuid: UUID, digits: String) async throws {
        let dtmfAction = CXPlayDTMFCallAction(call: uuid, digits: digits, type: .singleTone)
        let transaction = CXTransaction(action: dtmfAction)
        try await callController.request(transaction)
    }

    // MARK: - Call Info

    /// Get info for a specific call
    func callInfo(for uuid: UUID) -> CallInfo? {
        return activeCalls[uuid]
    }

    /// Get all active calls
    func allActiveCalls() -> [CallInfo] {
        return Array(activeCalls.values)
    }
}

// MARK: - CXProviderDelegate

extension CallKitManager: CXProviderDelegate {
    /// Called when provider is reset
    func providerDidReset(_ provider: CXProvider) {
        // Clean up all calls
        activeCalls.removeAll()
        currentCallUUID = nil
        hasActiveCall = false
        isMuted = false
        isOnHold = false

        // Deactivate audio session
        try? AudioSessionManager.shared.deactivateSession()
    }

    /// Called when provider begins
    func providerDidBegin(_ provider: CXProvider) {
        // Provider is ready
    }

    /// Handle start call action (outgoing call)
    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        // Configure audio session for outgoing call
        do {
            try AudioSessionManager.shared.configureForVoIP()
        } catch {
            action.fail()
            return
        }

        // Report connecting
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())

        // Perform the call
        Task {
            do {
                try await onStartCall?(action.callUUID, action.handle.value)
                action.fulfill()
            } catch {
                action.fail()
            }
        }
    }

    /// Handle answer call action (incoming call)
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        // Configure audio session
        do {
            try AudioSessionManager.shared.configureForVoIP()
        } catch {
            action.fail()
            return
        }

        // Answer the call
        Task {
            do {
                try await onAnswerCall?(action.callUUID)
                action.fulfill()
            } catch {
                action.fail()
            }
        }
    }

    /// Handle end call action
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        Task {
            do {
                try await onEndCall?(action.callUUID)
            } catch {
                // Still fulfill even if end fails
            }

            // Clean up
            activeCalls.removeValue(forKey: action.callUUID)
            if currentCallUUID == action.callUUID {
                currentCallUUID = nil
                hasActiveCall = false
                isMuted = false
                isOnHold = false
            }

            action.fulfill()

            // Deactivate audio session
            try? AudioSessionManager.shared.deactivateSession()
        }
    }

    /// Handle set muted action
    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        Task {
            do {
                try await onSetMuted?(action.callUUID, action.isMuted)
                isMuted = action.isMuted
                action.fulfill()
            } catch {
                action.fail()
            }
        }
    }

    /// Handle set held action
    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        Task {
            do {
                try await onSetHeld?(action.callUUID, action.isOnHold)
                isOnHold = action.isOnHold

                // Update audio for hold state
                if action.isOnHold {
                    try? AudioSessionManager.shared.deactivateSession()
                } else {
                    try? AudioSessionManager.shared.activateSession()
                }

                action.fulfill()
            } catch {
                action.fail()
            }
        }
    }

    /// Handle DTMF action
    func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
        // DTMF is handled by TwilioVoiceService
        action.fulfill()
    }

    /// Called when audio session is activated by CallKit
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        // Audio session is now active and ready for voice
        onAudioSessionActivated?()
    }

    /// Called when audio session is deactivated by CallKit
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        // Audio session is deactivated
        onAudioSessionDeactivated?()
    }

    /// Handle timed out perform action
    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        // Action timed out
        action.fail()
    }
}

// MARK: - Call Info

/// Information about an active call
struct CallInfo {
    let uuid: UUID
    let handle: String
    let isOutgoing: Bool
    let startTime: Date
    var connectedTime: Date?

    /// Duration since call started
    var duration: TimeInterval {
        guard let connected = connectedTime else { return 0 }
        return Date().timeIntervalSince(connected)
    }

    /// Formatted duration string
    var formattedDuration: String {
        Date.formatSeconds(Int(duration))
    }
}
