import Foundation
import Combine
import CallKit
import AVFoundation

/// High-level call manager that orchestrates all call-related services
/// Coordinates TwilioVoiceService, CallKitManager, AudioSessionManager, and AppState
@MainActor
class CallManager: ObservableObject {
    // MARK: - Published Properties

    /// Current call session
    @Published private(set) var currentSession: CallSession?

    /// Whether there's an active call
    @Published private(set) var hasActiveCall: Bool = false

    /// Call state for UI display
    @Published private(set) var callState: CallManagerState = .idle

    /// Current call duration timer
    @Published private(set) var callDuration: TimeInterval = 0

    /// Mute state
    @Published var isMuted: Bool = false {
        didSet {
            twilioService.toggleMute(isMuted)
        }
    }

    /// Speaker state
    @Published var isSpeakerEnabled: Bool = false {
        didSet {
            twilioService.toggleSpeaker(isSpeakerEnabled)
        }
    }

    /// Last error
    @Published private(set) var lastError: Error?

    /// Event processor for real-time events
    @Published private(set) var eventProcessor = EventProcessor()

    /// WebSocket connection state
    @Published private(set) var webSocketState: WebSocketService.ConnectionState = .disconnected

    /// Whether AI is speaking
    var isAISpeaking: Bool { eventProcessor.isAISpeaking }

    /// Whether user is speaking
    var isUserSpeaking: Bool { eventProcessor.isUserSpeaking }

    /// Current transcript
    var currentTranscript: String { eventProcessor.currentTranscript }

    // MARK: - Services

    private let twilioService: TwilioVoiceService
    private let callKitManager: CallKitManager
    private let audioSessionManager: AudioSessionManager
    private let apiClient: APIClientProtocol
    private let webSocketService: WebSocketService
    private weak var appState: AppState?

    // MARK: - Private Properties

    /// Duration timer
    private var durationTimer: Timer?

    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()

    /// Current call start time
    private var callStartTime: Date?

    // MARK: - Initialization

    init(
        twilioService: TwilioVoiceService,
        callKitManager: CallKitManager,
        audioSessionManager: AudioSessionManager = .shared,
        apiClient: APIClientProtocol,
        webSocketService: WebSocketService,
        appState: AppState
    ) {
        self.twilioService = twilioService
        self.callKitManager = callKitManager
        self.audioSessionManager = audioSessionManager
        self.apiClient = apiClient
        self.webSocketService = webSocketService
        self.appState = appState

        setupCallbacks()
        setupBindings()
        setupWebSocketHandlers()
    }

    // MARK: - Setup

    private func setupCallbacks() {
        // TwilioVoiceService callbacks
        twilioService.onCallConnected = { [weak self] call in
            Task { @MainActor in
                self?.handleCallConnected(call)
            }
        }

        twilioService.onCallDisconnected = { [weak self] call, error in
            Task { @MainActor in
                self?.handleCallDisconnected(call, error: error)
            }
        }

        twilioService.onIncomingCall = { [weak self] invite in
            Task { @MainActor in
                self?.handleIncomingCall(invite)
            }
        }

        twilioService.onQualityWarning = { [weak self] warnings in
            Task { @MainActor in
                self?.handleQualityWarning(warnings)
            }
        }

        // CallKitManager callbacks
        callKitManager.onStartCall = { [weak self] uuid, handle in
            try await self?.handleCallKitStartCall(uuid: uuid, handle: handle)
        }

        callKitManager.onAnswerCall = { [weak self] uuid in
            try await self?.handleCallKitAnswerCall(uuid: uuid)
        }

        callKitManager.onEndCall = { [weak self] uuid in
            try await self?.handleCallKitEndCall(uuid: uuid)
        }

        callKitManager.onSetMuted = { [weak self] uuid, muted in
            try await self?.handleCallKitSetMuted(uuid: uuid, muted: muted)
        }

        callKitManager.onSetHeld = { [weak self] uuid, onHold in
            try await self?.handleCallKitSetHeld(uuid: uuid, onHold: onHold)
        }

        callKitManager.onAudioSessionActivated = { [weak self] in
            Task { @MainActor in
                self?.handleAudioSessionActivated()
            }
        }

        callKitManager.onAudioSessionDeactivated = { [weak self] in
            Task { @MainActor in
                self?.handleAudioSessionDeactivated()
            }
        }

        // Audio session callbacks
        audioSessionManager.onInterruption = { [weak self] began in
            Task { @MainActor in
                self?.handleAudioInterruption(began: began)
            }
        }

        audioSessionManager.onRouteChange = { [weak self] reason in
            Task { @MainActor in
                self?.handleAudioRouteChange(reason: reason)
            }
        }
    }

    private func setupBindings() {
        // Bind Twilio service mute state
        twilioService.$isMuted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] muted in
                if self?.isMuted != muted {
                    self?.isMuted = muted
                }
            }
            .store(in: &cancellables)

        // Bind Twilio service speaker state
        twilioService.$isSpeakerEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if self?.isSpeakerEnabled != enabled {
                    self?.isSpeakerEnabled = enabled
                }
            }
            .store(in: &cancellables)

        // Bind WebSocket connection state
        webSocketService.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.webSocketState = state
            }
            .store(in: &cancellables)
    }

    private func setupWebSocketHandlers() {
        // Handle call status updates
        webSocketService.onCallStatus = { [weak self] status in
            Task { @MainActor in
                self?.handleCallStatusUpdate(status)
            }
        }

        // Handle real-time events
        webSocketService.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.eventProcessor.processEvent(event)
                self?.appState?.addEvent(event)
            }
        }

        // Handle errors
        webSocketService.onError = { [weak self] error in
            Task { @MainActor in
                self?.lastError = error
            }
        }
    }

    // MARK: - Initialization

    /// Initialize the call manager and its services
    func initialize() async throws {
        callState = .initializing

        do {
            // Initialize Twilio
            try await twilioService.initialize()

            // Connect WebSocket control channel
            try await webSocketService.connect()

            callState = .idle
        } catch {
            callState = .error(error)
            throw error
        }
    }

    /// Register for push notifications with device token
    func registerForPushNotifications(deviceToken: Data) {
        twilioService.registerForPushNotifications(deviceToken: deviceToken)
    }

    // MARK: - Outbound Calls

    /// Start an outbound call
    /// - Parameters:
    ///   - phoneNumber: The phone number to call
    ///   - config: Realtime configuration for the AI
    ///   - promptId: Optional prompt ID to use
    func startCall(
        to phoneNumber: String,
        config: RealtimeConfig = .default,
        promptId: UUID? = nil
    ) async throws {
        guard !hasActiveCall else {
            throw CallManagerError.callAlreadyActive
        }

        callState = .connecting

        // Create session
        let session = CallSession.outbound(
            to: phoneNumber,
            config: config,
            promptId: promptId
        )
        currentSession = session

        do {
            // Configure audio session
            try audioSessionManager.configureForVoIP()

            // Initiate call via API first (if needed for server-side setup)
            // This notifies the server to prepare the bridge
            _ = try await apiClient.initiateCall(to: phoneNumber, config: config)

            // Make the call via Twilio
            let call = try await twilioService.makeCall(
                to: phoneNumber,
                params: [
                    "PromptId": promptId?.uuidString ?? "",
                    "Config": config.toJSON() ?? ""
                ]
            )

            // Update session with call SID
            var updatedSession = session
            updatedSession.callSid = call.sid
            currentSession = updatedSession

            hasActiveCall = true
            appState?.setActiveCall(session)

            // Start event processor
            eventProcessor.startCall(callId: call.sid ?? session.id.uuidString)

            // Connect event stream for real-time updates
            if let callSid = call.sid {
                try? await webSocketService.connectEventStream(callId: callSid)
            }

            // Send session config via WebSocket
            try? await webSocketService.sendSessionConfig(config)

        } catch {
            callState = .error(error)
            currentSession = nil
            lastError = error
            throw error
        }
    }

    /// End the current call
    func endCall() async throws {
        guard hasActiveCall else { return }

        callState = .disconnecting

        // End via Twilio
        twilioService.endCall()

        // End via API if needed
        if let callSid = currentSession?.callSid {
            try? await apiClient.endCall(callSid: callSid)
        }

        // Disconnect event stream
        webSocketService.disconnectEventStream()

        // End event processing
        eventProcessor.endCall()
    }

    // MARK: - WebSocket Actions

    /// Update session configuration mid-call
    func updateConfig(_ config: RealtimeConfig) async throws {
        guard hasActiveCall else { return }
        try await webSocketService.sendCallAction(.updateConfig(config))
    }

    /// Cancel current AI response
    func cancelAIResponse() async throws {
        guard hasActiveCall else { return }
        try await webSocketService.sendCallAction(.cancelResponse)
    }

    /// Interrupt AI (same as cancel)
    func interruptAI() async throws {
        try await cancelAIResponse()
    }

    /// Clear audio buffer
    func clearAudioBuffer() async throws {
        guard hasActiveCall else { return }
        try await webSocketService.sendCallAction(.clearAudioBuffer)
    }

    // MARK: - Inbound Calls

    /// Handle incoming VoIP push notification
    func handleIncomingPush(payload: [AnyHashable: Any]) async {
        twilioService.handlePushNotification(payload) {
            // Completion called after CallKit reports call
        }
    }

    /// Accept the current incoming call
    func acceptCall() async throws {
        guard let invite = twilioService.callInvite else {
            throw CallManagerError.noIncomingCall
        }

        callState = .connecting

        do {
            // Accept the call
            let call = try twilioService.acceptIncomingCall()

            // Create session
            let session = CallSession.inbound(
                from: invite.from,
                callSid: call.sid
            )
            currentSession = session
            hasActiveCall = true
            appState?.setActiveCall(session)

        } catch {
            callState = .error(error)
            lastError = error
            throw error
        }
    }

    /// Decline the current incoming call
    func declineCall() {
        twilioService.rejectIncomingCall()
        callState = .idle
    }

    // MARK: - Call Controls

    /// Toggle mute
    func toggleMute() {
        isMuted.toggle()
    }

    /// Toggle speaker
    func toggleSpeaker() {
        isSpeakerEnabled.toggle()
    }

    /// Send DTMF digits
    func sendDigits(_ digits: String) {
        twilioService.sendDigits(digits)
    }

    // MARK: - Private Handlers

    private func handleCallConnected(_ call: TVOCallProtocol) {
        callState = .connected
        callStartTime = Date()
        startDurationTimer()

        // Update session
        if var session = currentSession {
            session.status = .inProgress
            session.callSid = call.sid
            currentSession = session
            appState?.setActiveCall(session)
        }
    }

    private func handleCallDisconnected(_ call: TVOCallProtocol?, error: Error?) {
        stopDurationTimer()

        if let error = error {
            callState = .error(error)
            lastError = error
        } else {
            callState = .idle
        }

        // Update session
        if var session = currentSession {
            session.status = .ended
            session.endedAt = Date()
            if let startTime = callStartTime {
                session.durationSeconds = Int(Date().timeIntervalSince(startTime))
            }
            currentSession = session
            appState?.endCall()
        }

        // Cleanup WebSocket
        webSocketService.disconnectEventStream()
        eventProcessor.endCall()

        // Reset state
        hasActiveCall = false
        currentSession = nil
        callDuration = 0
        callStartTime = nil
        isMuted = false
        isSpeakerEnabled = false
    }

    private func handleIncomingCall(_ invite: TVOCallInviteProtocol) {
        callState = .ringing

        // Create session for incoming call
        let session = CallSession.inbound(
            from: invite.from,
            callSid: invite.callSid
        )
        currentSession = session
    }

    private func handleQualityWarning(_ warnings: TVOCallQualityWarning) {
        // Log quality warnings
        if warnings.contains(.highRtt) {
            print("[CallManager] Quality warning: High RTT")
        }
        if warnings.contains(.highJitter) {
            print("[CallManager] Quality warning: High jitter")
        }
        if warnings.contains(.highPacketLoss) {
            print("[CallManager] Quality warning: High packet loss")
        }
        if warnings.contains(.lowMos) {
            print("[CallManager] Quality warning: Low MOS")
        }
    }

    private func handleCallStatusUpdate(_ status: CallStatusMessage) {
        // Update session status from server
        guard var session = currentSession,
              session.callSid == status.callSid else { return }

        if let newStatus = status.callStatus {
            session.status = newStatus
            currentSession = session

            switch newStatus {
            case .inProgress:
                callState = .connected
            case .ended, .completed:
                callState = .idle
                handleCallDisconnected(nil, error: nil)
            case .failed:
                let error = CallManagerError.connectionFailed("Call failed on server")
                handleCallDisconnected(nil, error: error)
            default:
                break
            }
        }

        // Update duration if provided
        if let duration = status.duration {
            session.durationSeconds = duration
            currentSession = session
        }
    }

    // MARK: - CallKit Handlers

    private func handleCallKitStartCall(uuid: UUID, handle: String) async throws {
        // This is called when user starts call from CallKit UI
        // Usually not used in our flow since we initiate calls ourselves
    }

    private func handleCallKitAnswerCall(uuid: UUID) async throws {
        try await acceptCall()
    }

    private func handleCallKitEndCall(uuid: UUID) async throws {
        try await endCall()
    }

    private func handleCallKitSetMuted(uuid: UUID, muted: Bool) async throws {
        isMuted = muted
    }

    private func handleCallKitSetHeld(uuid: UUID, onHold: Bool) async throws {
        // Hold is not fully supported in this implementation
        // Would need to mute and pause AI processing
        if onHold {
            isMuted = true
        } else {
            isMuted = false
        }
    }

    // MARK: - Audio Session Handlers

    private func handleAudioSessionActivated() {
        // Audio is ready for call
        print("[CallManager] Audio session activated")
    }

    private func handleAudioSessionDeactivated() {
        // Audio session deactivated
        print("[CallManager] Audio session deactivated")
    }

    private func handleAudioInterruption(began: Bool) {
        if began {
            // Audio interrupted (e.g., another app took audio)
            print("[CallManager] Audio interrupted")
        } else {
            // Interruption ended
            print("[CallManager] Audio interruption ended")
            try? audioSessionManager.activateSession()
        }
    }

    private func handleAudioRouteChange(reason: AVAudioSession.RouteChangeReason) {
        // Update speaker state based on route
        isSpeakerEnabled = audioSessionManager.isSpeakerEnabled
    }

    // MARK: - Duration Timer

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startTime = self.callStartTime else { return }
                self.callDuration = Date().timeIntervalSince(startTime)

                // Update session duration
                if var session = self.currentSession {
                    session.durationSeconds = Int(self.callDuration)
                    self.currentSession = session
                }
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
}

// MARK: - Call Manager State

enum CallManagerState: Equatable {
    case idle
    case initializing
    case ringing
    case connecting
    case connected
    case disconnecting
    case error(Error)

    static func == (lhs: CallManagerState, rhs: CallManagerState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.initializing, .initializing),
             (.ringing, .ringing),
             (.connecting, .connecting),
             (.connected, .connected),
             (.disconnecting, .disconnecting):
            return true
        case (.error, .error):
            return true
        default:
            return false
        }
    }

    var displayText: String {
        switch self {
        case .idle: return "Ready"
        case .initializing: return "Initializing..."
        case .ringing: return "Ringing..."
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .disconnecting: return "Ending..."
        case .error(let error): return "Error: \(error.localizedDescription)"
        }
    }

    var isActive: Bool {
        switch self {
        case .ringing, .connecting, .connected:
            return true
        default:
            return false
        }
    }
}

// MARK: - Call Manager Errors

enum CallManagerError: LocalizedError {
    case callAlreadyActive
    case noIncomingCall
    case notInitialized
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .callAlreadyActive:
            return "A call is already active"
        case .noIncomingCall:
            return "No incoming call to accept"
        case .notInitialized:
            return "Call manager not initialized"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        }
    }
}

// MARK: - CallSession Extensions

extension CallSession {
    /// Create outbound call session
    static func outbound(
        to phoneNumber: String,
        config: RealtimeConfig,
        promptId: UUID? = nil
    ) -> CallSession {
        CallSession(
            id: UUID(),
            callSid: nil,
            direction: .outbound,
            phoneNumber: phoneNumber,
            status: .initiating,
            startedAt: Date(),
            config: config,
            promptId: promptId
        )
    }

    /// Create inbound call session
    static func inbound(
        from phoneNumber: String,
        callSid: String?
    ) -> CallSession {
        CallSession(
            id: UUID(),
            callSid: callSid,
            direction: .inbound,
            phoneNumber: phoneNumber,
            status: .ringing,
            startedAt: Date(),
            config: .default
        )
    }
}

// MARK: - RealtimeConfig Extension

extension RealtimeConfig {
    /// Convert to JSON string for passing to Twilio
    func toJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }
}
