import Foundation
import Combine

/// Actor-based WebSocket client with automatic reconnection and ping/pong
actor WebSocketClient {
    // MARK: - Types

    /// Connection state
    enum State: Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting
        case error(String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected),
                 (.connecting, .connecting),
                 (.connected, .connected),
                 (.reconnecting, .reconnecting):
                return true
            case (.error(let l), .error(let r)):
                return l == r
            default:
                return false
            }
        }
    }

    // MARK: - Properties

    /// Current connection state
    private(set) var state: State = .disconnected

    /// The WebSocket URL
    private let url: URL

    /// URL session for WebSocket
    private let session: URLSession

    /// Active WebSocket task
    private var task: URLSessionWebSocketTask?

    /// Ping task for keep-alive
    private var pingTask: Task<Void, Never>?

    /// Receive task
    private var receiveTask: Task<Void, Never>?

    /// Message continuation for async stream
    private var messageContinuation: AsyncThrowingStream<WebSocketMessage, Error>.Continuation?

    /// Reconnection attempts
    private var reconnectAttempts = 0

    /// Maximum reconnection attempts
    private let maxReconnectAttempts = 5

    /// Reconnection delay base (exponential backoff)
    private let reconnectDelayBase: TimeInterval = 1.0

    /// Whether auto-reconnect is enabled
    private var autoReconnect = true

    /// Ping interval in seconds
    private let pingInterval: TimeInterval = 30.0

    // MARK: - Callbacks (set from MainActor)

    /// Called when state changes
    var onStateChange: ((State) -> Void)?

    /// Called when message is received
    var onMessage: ((WebSocketMessage) -> Void)?

    /// Called when disconnected
    var onDisconnect: ((Error?) -> Void)?

    // MARK: - Initialization

    init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    // MARK: - Connection Management

    /// Connect to the WebSocket server
    func connect() async throws {
        guard state != .connected && state != .connecting else { return }

        state = .connecting
        notifyStateChange()

        task = session.webSocketTask(with: url)
        task?.resume()

        // Wait for connection (first receive confirms connection)
        state = .connected
        reconnectAttempts = 0
        notifyStateChange()

        // Start ping loop
        startPingLoop()

        // Start receiving
        startReceiving()
    }

    /// Disconnect from the WebSocket server
    func disconnect() {
        autoReconnect = false
        cleanupConnection(error: nil)
        state = .disconnected
        notifyStateChange()
    }

    /// Send a message
    func send(_ message: WebSocketMessage) async throws {
        guard let task = task, state == .connected else {
            throw WebSocketError.notConnected
        }

        let urlMessage: URLSessionWebSocketTask.Message
        switch message {
        case .string(let text):
            urlMessage = .string(text)
        case .data(let data):
            urlMessage = .data(data)
        case .json(let json):
            let data = try JSONSerialization.data(withJSONObject: json)
            urlMessage = .data(data)
        }

        try await task.send(urlMessage)
    }

    /// Send JSON message
    func sendJSON(_ json: [String: Any]) async throws {
        try await send(.json(json))
    }

    /// Get async stream of messages
    func receive() -> AsyncThrowingStream<WebSocketMessage, Error> {
        AsyncThrowingStream { continuation in
            self.messageContinuation = continuation

            continuation.onTermination = { @Sendable _ in
                Task { await self.handleStreamTermination() }
            }
        }
    }

    // MARK: - Private Methods

    private func startPingLoop() {
        pingTask?.cancel()
        pingTask = Task {
            while !Task.isCancelled && state == .connected {
                do {
                    try await Task.sleep(nanoseconds: UInt64(pingInterval * 1_000_000_000))
                    try await sendPing()
                } catch {
                    if !Task.isCancelled {
                        await handleDisconnect(error: error)
                    }
                    break
                }
            }
        }
    }

    private func sendPing() async throws {
        guard let task = task else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func startReceiving() {
        receiveTask?.cancel()
        receiveTask = Task {
            while !Task.isCancelled && state == .connected {
                do {
                    guard let task = task else { break }
                    let message = try await task.receive()

                    let wsMessage: WebSocketMessage
                    switch message {
                    case .string(let text):
                        wsMessage = .string(text)
                    case .data(let data):
                        wsMessage = .data(data)
                    @unknown default:
                        continue
                    }

                    // Notify via continuation
                    messageContinuation?.yield(wsMessage)

                    // Notify via callback
                    onMessage?(wsMessage)

                } catch {
                    if !Task.isCancelled {
                        await handleDisconnect(error: error)
                    }
                    break
                }
            }
        }
    }

    private func handleDisconnect(error: Error?) {
        cleanupConnection(error: error)

        if autoReconnect && reconnectAttempts < maxReconnectAttempts {
            state = .reconnecting
            notifyStateChange()

            Task {
                await reconnect()
            }
        } else {
            state = error != nil ? .error(error!.localizedDescription) : .disconnected
            notifyStateChange()
            messageContinuation?.finish(throwing: error)
        }

        onDisconnect?(error)
    }

    private func cleanupConnection(error: Error?) {
        pingTask?.cancel()
        pingTask = nil

        receiveTask?.cancel()
        receiveTask = nil

        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func reconnect() async {
        reconnectAttempts += 1

        // Exponential backoff
        let delay = reconnectDelayBase * pow(2.0, Double(reconnectAttempts - 1))
        let cappedDelay = min(delay, 30.0) // Cap at 30 seconds

        do {
            try await Task.sleep(nanoseconds: UInt64(cappedDelay * 1_000_000_000))

            if autoReconnect {
                try await connect()
            }
        } catch {
            if autoReconnect && reconnectAttempts < maxReconnectAttempts {
                await reconnect()
            } else {
                state = .error(error.localizedDescription)
                notifyStateChange()
                messageContinuation?.finish(throwing: error)
            }
        }
    }

    private func handleStreamTermination() {
        // Stream was terminated externally
    }

    private func notifyStateChange() {
        let currentState = state
        onStateChange?(currentState)
    }

    // MARK: - Configuration

    /// Enable or disable auto-reconnect
    func setAutoReconnect(_ enabled: Bool) {
        autoReconnect = enabled
    }

    /// Reset reconnection attempts (call after successful operations)
    func resetReconnectAttempts() {
        reconnectAttempts = 0
    }
}

// MARK: - WebSocketMessage

/// WebSocket message types
enum WebSocketMessage {
    case string(String)
    case data(Data)
    case json([String: Any])

    /// Parse as JSON dictionary
    var jsonValue: [String: Any]? {
        switch self {
        case .string(let text):
            guard let data = text.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        case .data(let data):
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        case .json(let json):
            return json
        }
    }

    /// Parse as Decodable type
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let data: Data
        switch self {
        case .string(let text):
            guard let d = text.data(using: .utf8) else {
                throw WebSocketError.invalidData
            }
            data = d
        case .data(let d):
            data = d
        case .json(let json):
            data = try JSONSerialization.data(withJSONObject: json)
        }

        return try JSONDecoder().decode(type, from: data)
    }

    /// Get raw string
    var stringValue: String? {
        switch self {
        case .string(let text):
            return text
        case .data(let data):
            return String(data: data, encoding: .utf8)
        case .json(let json):
            guard let data = try? JSONSerialization.data(withJSONObject: json),
                  let text = String(data: data, encoding: .utf8) else { return nil }
            return text
        }
    }
}

// MARK: - WebSocketError

enum WebSocketError: LocalizedError {
    case notConnected
    case invalidURL
    case invalidData
    case connectionFailed(String)
    case sendFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "WebSocket not connected"
        case .invalidURL:
            return "Invalid WebSocket URL"
        case .invalidData:
            return "Invalid message data"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .sendFailed(let reason):
            return "Send failed: \(reason)"
        }
    }
}
