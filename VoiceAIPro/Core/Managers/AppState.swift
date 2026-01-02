import Foundation
import Combine
import SwiftUI
import SwiftData

/// Global application state accessible throughout the app
/// Tracks current call, connection status, and configuration
@MainActor
class AppState: ObservableObject {
    // MARK: - Dependencies

    /// Data manager for SwiftData operations
    private weak var dataManager: DataManager?

    /// Combine subscriptions
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Call State

    /// Currently active call session
    @Published var currentCall: CallSession?

    /// Whether a call is currently active
    @Published var isCallActive: Bool = false

    /// Current call status
    @Published var callStatus: CallStatus = .ended

    // MARK: - Configuration

    /// Current realtime configuration for calls
    @Published var realtimeConfig: RealtimeConfig = .default

    /// Selected prompt for next call
    @Published var selectedPrompt: Prompt?

    // MARK: - Connection State

    /// WebSocket connection state
    @Published var connectionState: ConnectionState = .disconnected

    /// Server connection health
    @Published var isServerConnected: Bool = false

    /// Twilio registration state
    @Published var isTwilioRegistered: Bool = false

    // MARK: - Events

    /// Recent call events (for real-time display)
    @Published var events: [CallEvent] = []

    /// Maximum events to keep in memory
    private let maxEvents = Constants.UI.maxEventLogItems

    // MARK: - UI State

    /// Whether to show event log overlay
    @Published var showEventLog: Bool = false

    /// Whether to show settings
    @Published var showSettings: Bool = false

    /// Active alert to display
    @Published var activeAlert: AlertInfo?

    // MARK: - Audio State

    /// Whether microphone is muted
    @Published var isMuted: Bool = false

    /// Whether speaker is enabled
    @Published var isSpeakerEnabled: Bool = false

    /// Whether AI is currently speaking
    @Published var isAISpeaking: Bool = false

    /// Whether user is currently speaking
    @Published var isUserSpeaking: Bool = false

    // MARK: - Initialization

    init() {
        // Load saved configuration from UserDefaults initially
        loadSavedConfig()

        // Auto-save when realtimeConfig changes
        $realtimeConfig
            .dropFirst()  // Skip initial value
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                print("[AppState] Config changed, saving...")
                self?.saveConfig()
            }
            .store(in: &cancellables)
    }

    /// Set data manager for SwiftData operations
    func setDataManager(_ manager: DataManager?) {
        self.dataManager = manager
        // Reload config from SwiftData if available
        if let settings = manager?.getSettings() {
            realtimeConfig = settings.defaultConfig
        }
    }

    // MARK: - Call Management

    /// Set the active call session
    func setActiveCall(_ session: CallSession?) {
        currentCall = session
        isCallActive = session != nil
        if let session = session {
            callStatus = session.status
        }
    }

    /// Add a CallEvent directly
    func addCallEvent(_ event: CallEvent) {
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
        updateSpeakingState(for: event.eventType)
    }

    /// Start a new outbound call
    func startCall(to phoneNumber: String) {
        let session = CallSession.outbound(
            to: phoneNumber,
            promptId: selectedPrompt?.id,
            config: realtimeConfig
        )

        currentCall = session
        isCallActive = true
        callStatus = .initiating
        events.removeAll()

        addEvent(.callConnected, direction: .outgoing, payload: [
            "phoneNumber": phoneNumber,
            "direction": "outbound"
        ])
    }

    /// Handle incoming call
    func handleIncomingCall(callSid: String, from phoneNumber: String) {
        let session = CallSession.inbound(
            from: phoneNumber,
            callSid: callSid,
            config: realtimeConfig
        )

        currentCall = session
        isCallActive = true
        callStatus = .ringing
        events.removeAll()

        addEvent(.callConnected, direction: .incoming, payload: [
            "phoneNumber": phoneNumber,
            "direction": "inbound",
            "callSid": callSid
        ])
    }

    /// Update call status
    func updateCallStatus(_ status: CallStatus) {
        callStatus = status
        currentCall?.status = status

        if status == .ended || status == .failed {
            endCall(reason: status == .failed ? "failed" : "completed")
        }
    }

    /// End the current call
    func endCall(reason: String = "user_ended") {
        currentCall?.status = .ended
        currentCall?.endedAt = Date()

        if let startTime = currentCall?.startedAt {
            currentCall?.durationSeconds = Int(Date().timeIntervalSince(startTime))
        }

        addEvent(.callDisconnected, direction: .outgoing, payload: [
            "reason": reason,
            "duration": currentCall?.durationSeconds ?? 0
        ])

        // Delay clearing to allow UI to update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isCallActive = false
            self?.callStatus = .ended
            self?.isAISpeaking = false
            self?.isUserSpeaking = false
        }
    }

    // MARK: - Event Management

    /// Add a new event
    func addEvent(
        _ eventType: EventType,
        direction: EventDirection,
        payload: [String: Any]? = nil
    ) {
        let payloadString: String?
        if let payload = payload,
           let data = try? JSONSerialization.data(withJSONObject: payload),
           let string = String(data: data, encoding: .utf8) {
            payloadString = string
        } else {
            payloadString = nil
        }

        let event = CallEvent(
            callId: currentCall?.callSid ?? "unknown",
            eventType: eventType,
            direction: direction,
            payload: payloadString
        )

        events.append(event)

        // Trim if over limit
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }

        // Update speaking state based on events
        updateSpeakingState(for: eventType)
    }

    /// Add event from server
    func addServerEvent(_ json: [String: Any]) {
        guard let callId = currentCall?.callSid else { return }
        guard let event = CallEvent(from: json, callId: callId) else { return }

        events.append(event)

        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }

        updateSpeakingState(for: event.eventType)
    }

    private func updateSpeakingState(for eventType: EventType) {
        switch eventType {
        case .speechStarted:
            isUserSpeaking = true
        case .speechStopped:
            isUserSpeaking = false
        case .responseCreated, .responseAudioDelta:
            isAISpeaking = true
        case .responseAudioDone, .responseDone, .responseCancelled:
            isAISpeaking = false
        default:
            break
        }
    }

    /// Clear all events
    func clearEvents() {
        events.removeAll()
    }

    // MARK: - Configuration

    /// Update realtime configuration
    func updateConfig(_ config: RealtimeConfig) {
        realtimeConfig = config
        saveConfig()

        addEvent(.configUpdated, direction: .outgoing, payload: config.toAPIParams())
    }

    /// Apply prompt configuration
    func applyPrompt(_ prompt: Prompt) {
        selectedPrompt = prompt
        realtimeConfig = prompt.toConfig()
        saveConfig()
    }

    private func saveConfig() {
        // Save to UserDefaults as fallback
        if let data = try? JSONEncoder().encode(realtimeConfig) {
            UserDefaults.standard.set(data, forKey: Constants.Persistence.lastConfigKey)
        }

        // Save to SwiftData for persistent storage
        if let dataManager = dataManager {
            let settings = dataManager.getSettings()
            settings.setDefaultConfig(realtimeConfig)
            settings.setDefaultVoice(realtimeConfig.voice)

            // Determine VAD type from config enum
            switch realtimeConfig.vadConfig {
            case .serverVAD:
                settings.defaultVADType = "server_vad"
            case .semanticVAD:
                settings.defaultVADType = "semantic_vad"
            case .disabled:
                settings.defaultVADType = "disabled"
            }

            try? dataManager.context.save()
        }
    }

    private func loadSavedConfig() {
        if let data = UserDefaults.standard.data(forKey: Constants.Persistence.lastConfigKey),
           let config = try? JSONDecoder().decode(RealtimeConfig.self, from: data) {
            realtimeConfig = config
        }
    }

    // MARK: - Connection State

    /// Update connection state
    func updateConnectionState(_ state: ConnectionState) {
        connectionState = state
        isServerConnected = state == .connected

        if state == .disconnected || state.isError {
            isTwilioRegistered = false
        }
    }

    /// Update Twilio registration state
    func updateTwilioRegistration(_ registered: Bool) {
        isTwilioRegistered = registered
    }

    // MARK: - Alerts

    /// Show an error alert
    func showError(_ message: String, title: String = "Error") {
        activeAlert = AlertInfo(
            title: title,
            message: message,
            type: .error
        )
    }

    /// Show a success alert
    func showSuccess(_ message: String, title: String = "Success") {
        activeAlert = AlertInfo(
            title: title,
            message: message,
            type: .success
        )
    }

    /// Dismiss active alert
    func dismissAlert() {
        activeAlert = nil
    }
}

// MARK: - ConnectionState

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case error(String)

    var displayName: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .reconnecting: return "Reconnecting..."
        case .error(let message): return "Error: \(message)"
        }
    }

    var icon: String {
        switch self {
        case .disconnected: return "wifi.slash"
        case .connecting, .reconnecting: return "wifi.exclamationmark"
        case .connected: return "wifi"
        case .error: return "exclamationmark.triangle"
        }
    }

    var color: Color {
        switch self {
        case .disconnected: return .gray
        case .connecting, .reconnecting: return .orange
        case .connected: return .green
        case .error: return .red
        }
    }

    var isError: Bool {
        if case .error = self {
            return true
        }
        return false
    }
}

// MARK: - AlertInfo

struct AlertInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let type: AlertType

    enum AlertType {
        case success
        case error
        case warning
        case info

        var color: Color {
            switch self {
            case .success: return .voiceAISuccess
            case .error: return .voiceAIError
            case .warning: return .voiceAIWarning
            case .info: return .voiceAIPrimary
            }
        }

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }
}
