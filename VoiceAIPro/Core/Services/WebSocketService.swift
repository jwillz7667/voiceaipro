import Foundation
import Combine

/// High-level WebSocket service managing control and event channels
@MainActor
class WebSocketService: ObservableObject {
    // MARK: - Published Properties

    /// Current connection state
    @Published private(set) var connectionState: ConnectionState = .disconnected

    /// Last error
    @Published private(set) var lastError: Error?

    /// Whether control channel is connected
    @Published private(set) var isControlConnected: Bool = false

    /// Whether event stream is connected
    @Published private(set) var isEventConnected: Bool = false

    // MARK: - Connection State

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting
        case error(String)

        var displayText: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting..."
            case .connected: return "Connected"
            case .reconnecting: return "Reconnecting..."
            case .error(let msg): return "Error: \(msg)"
            }
        }

        var isConnected: Bool {
            self == .connected
        }
    }

    // MARK: - Private Properties

    /// Control channel client
    private var controlClient: WebSocketClient?

    /// Event stream client
    private var eventClient: WebSocketClient?

    /// Message handlers by type
    private var messageHandlers: [String: (Any) -> Void] = [:]

    /// Control channel receive task
    private var controlReceiveTask: Task<Void, Never>?

    /// Event channel receive task
    private var eventReceiveTask: Task<Void, Never>?

    /// Base URL for WebSocket
    private let baseURL: String

    /// Device ID for authentication
    private let deviceId: String

    /// Cancellables
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Callbacks

    /// Called when call status changes
    var onCallStatus: ((CallStatusMessage) -> Void)?

    /// Called when event is received
    var onEvent: ((CallEvent) -> Void)?

    /// Called when error occurs
    var onError: ((Error) -> Void)?

    // MARK: - Initialization

    init(baseURL: String = Constants.API.wsURL, deviceId: String = "") {
        self.baseURL = baseURL
        self.deviceId = deviceId
    }

    // MARK: - Connection Management

    /// Connect to control channel
    func connect() async throws {
        try await connectControlChannel()
    }

    /// Disconnect all channels
    func disconnect() {
        disconnectControlChannel()
        disconnectEventStream()
        connectionState = .disconnected
    }

    // MARK: - Control Channel

    /// Connect to control channel for sending config and receiving call status
    func connectControlChannel() async throws {
        guard let url = URL(string: "\(baseURL)\(Constants.API.WebSocket.iosClient)?device_id=\(deviceId)") else {
            throw WebSocketError.invalidURL
        }

        connectionState = .connecting

        controlClient = WebSocketClient(url: url)

        // Set up state change handler
        await controlClient?.setAutoReconnect(true)

        do {
            try await controlClient?.connect()
            isControlConnected = true
            connectionState = .connected

            // Start receiving messages
            startControlReceiving()

            // Send initial handshake
            try await sendHandshake()

        } catch {
            connectionState = .error(error.localizedDescription)
            lastError = error
            throw error
        }
    }

    /// Disconnect control channel
    func disconnectControlChannel() {
        controlReceiveTask?.cancel()
        controlReceiveTask = nil

        Task {
            await controlClient?.disconnect()
        }
        controlClient = nil
        isControlConnected = false

        if !isEventConnected {
            connectionState = .disconnected
        }
    }

    /// Send session configuration
    func sendSessionConfig(_ config: RealtimeConfig) async throws {
        let message: [String: Any] = [
            "type": "session.config",
            "config": config.toAPIParams()
        ]
        try await controlClient?.sendJSON(message)
    }

    /// Send call action
    func sendCallAction(_ action: CallAction) async throws {
        let message = try action.toMessage()
        try await controlClient?.sendJSON(message)
    }

    // MARK: - Event Stream

    /// Connect to event stream for a specific call
    func connectEventStream(callId: String) async throws {
        guard let url = URL(string: "\(baseURL)\(Constants.API.WebSocket.events)/\(callId)") else {
            throw WebSocketError.invalidURL
        }

        eventClient = WebSocketClient(url: url)

        do {
            try await eventClient?.connect()
            isEventConnected = true

            // Start receiving events
            startEventReceiving()

        } catch {
            lastError = error
            throw error
        }
    }

    /// Disconnect event stream
    func disconnectEventStream() {
        eventReceiveTask?.cancel()
        eventReceiveTask = nil

        Task {
            await eventClient?.disconnect()
        }
        eventClient = nil
        isEventConnected = false
    }

    // MARK: - Message Handling

    /// Register handler for message type
    func onMessage(_ type: String, handler: @escaping (Any) -> Void) {
        messageHandlers[type] = handler
    }

    /// Remove handler for message type
    func removeHandler(for type: String) {
        messageHandlers.removeValue(forKey: type)
    }

    // MARK: - Private Methods

    private func sendHandshake() async throws {
        let message: [String: Any] = [
            "type": "handshake",
            "device_id": deviceId,
            "client_type": "ios",
            "version": Constants.App.version
        ]
        try await controlClient?.sendJSON(message)
    }

    private func startControlReceiving() {
        controlReceiveTask?.cancel()
        controlReceiveTask = Task {
            guard let client = controlClient else { return }

            do {
                for try await message in await client.receive() {
                    if Task.isCancelled { break }
                    handleControlMessage(message)
                }
            } catch {
                print("[WebSocketService] Control receive error: \(error)")
            }

            // Connection ended
            await MainActor.run {
                isControlConnected = false
                if !isEventConnected {
                    connectionState = .disconnected
                }
            }
        }
    }

    private func startEventReceiving() {
        eventReceiveTask?.cancel()
        eventReceiveTask = Task {
            guard let client = eventClient else { return }

            do {
                for try await message in await client.receive() {
                    if Task.isCancelled { break }
                    handleEventMessage(message)
                }
            } catch {
                print("[WebSocketService] Event receive error: \(error)")
            }

            // Connection ended
            await MainActor.run {
                isEventConnected = false
            }
        }
    }

    private func handleControlMessage(_ message: WebSocketMessage) {
        guard let json = message.jsonValue else { return }

        // Extract message type
        guard let type = json["type"] as? String else { return }

        // Call registered handler
        if let handler = messageHandlers[type] {
            handler(json)
        }

        // Handle known message types
        switch type {
        case "call.status":
            if let status = parseCallStatus(json) {
                onCallStatus?(status)
            }

        case "error":
            if let errorMsg = json["message"] as? String {
                let error = WebSocketError.connectionFailed(errorMsg)
                lastError = error
                onError?(error)
            }

        case "pong", "handshake.ack":
            // Acknowledgment messages
            break

        default:
            // Unknown message type
            break
        }
    }

    private func handleEventMessage(_ message: WebSocketMessage) {
        guard let json = message.jsonValue else { return }

        // Extract event type
        guard let typeString = json["type"] as? String,
              let eventType = EventType(rawValue: typeString) else { return }

        // Parse event
        let event = CallEvent(
            id: UUID(),
            timestamp: Date(),
            callId: json["call_id"] as? String ?? "",
            eventType: eventType,
            direction: .incoming,
            payload: message.stringValue
        )

        // Notify
        onEvent?(event)

        // Call registered handler
        if let handler = messageHandlers[typeString] {
            handler(json)
        }
    }

    private func parseCallStatus(_ json: [String: Any]) -> CallStatusMessage? {
        guard let callSid = json["call_sid"] as? String,
              let statusString = json["status"] as? String else { return nil }

        return CallStatusMessage(
            callSid: callSid,
            status: statusString,
            direction: json["direction"] as? String,
            from: json["from"] as? String,
            to: json["to"] as? String,
            duration: json["duration"] as? Int
        )
    }
}

// MARK: - Call Action

/// Actions that can be sent to the server during a call
enum CallAction: Codable {
    case updateConfig(RealtimeConfig)
    case cancelResponse
    case commitAudio
    case clearAudioBuffer
    case interruptAI

    func toMessage() throws -> [String: Any] {
        switch self {
        case .updateConfig(let config):
            return [
                "type": "call.config.update",
                "config": config.toAPIParams()
            ]
        case .cancelResponse:
            return ["type": "response.cancel"]
        case .commitAudio:
            return ["type": "input_audio_buffer.commit"]
        case .clearAudioBuffer:
            return ["type": "input_audio_buffer.clear"]
        case .interruptAI:
            return ["type": "response.cancel"]
        }
    }
}

// MARK: - Call Status Message

/// Status message received from server
struct CallStatusMessage {
    let callSid: String
    let status: String
    let direction: String?
    let from: String?
    let to: String?
    let duration: Int?

    var callStatus: CallStatus? {
        CallStatus(rawValue: status)
    }
}
