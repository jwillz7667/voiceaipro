import Foundation
import SwiftData
import Combine

/// Dependency Injection Container
/// Holds references to all services and provides factory methods
/// Supports testing with mock implementations
@MainActor
class DIContainer: ObservableObject {
    // MARK: - Singleton

    static let shared = DIContainer()

    // MARK: - Services

    /// API client for REST endpoints
    @Published private(set) var apiClient: APIClientProtocol!

    /// WebSocket client for real-time communication
    @Published private(set) var webSocketClient: WebSocketClientProtocol!

    /// Twilio Voice service
    @Published private(set) var twilioService: TwilioVoiceService!

    /// CallKit manager
    @Published private(set) var callKitManager: CallKitManager!

    /// Audio session manager
    var audioSessionManager: AudioSessionManager { AudioSessionManager.shared }

    /// WebSocket service
    @Published private(set) var webSocketService: WebSocketService!

    /// Data manager for SwiftData operations
    @Published private(set) var dataManager: DataManager?

    /// Call manager (high-level orchestrator)
    @Published private(set) var callManager: CallManager!

    // MARK: - SwiftData

    private var modelContainer: ModelContainer?

    // MARK: - Configuration

    /// Current environment configuration
    private(set) var environment: AppEnvironment = .production

    /// Device ID for user identification
    private(set) var deviceId: String = ""

    // MARK: - Initialization

    private init() {
        // Load device ID first (needed for API client)
        loadDeviceId()
        // Then initialize services with the device ID
        setupDefaultServices()
    }

    /// Initialize with model container and app state (called from App)
    func initialize(modelContainer: ModelContainer, appState: AppState) {
        self.modelContainer = modelContainer

        // Initialize data manager
        dataManager = DataManager(container: modelContainer)
        dataManager?.loadInitialData()

        // Connect AppState to DataManager for persistent settings
        appState.setDataManager(dataManager)

        // Initialize call-related services
        setupCallServices(appState: appState)
    }

    /// Set up call-related services (requires AppState)
    private func setupCallServices(appState: AppState) {
        // Create CallKit manager
        callKitManager = CallKitManager()

        // Create Twilio Voice service
        twilioService = TwilioVoiceService(
            apiClient: apiClient,
            deviceId: deviceId
        )

        // Link Twilio service to CallKit manager
        twilioService.setCallKitManager(callKitManager)

        // Create WebSocket service
        webSocketService = WebSocketService(
            baseURL: Constants.API.wsURL,
            deviceId: deviceId
        )

        // Create Call manager (orchestrator)
        callManager = CallManager(
            twilioService: twilioService,
            callKitManager: callKitManager,
            apiClient: apiClient,
            webSocketService: webSocketService,
            appState: appState,
            dataManager: dataManager
        )
    }

    /// Set up for testing with mock services
    static func forTesting() -> DIContainer {
        let container = DIContainer()
        container.environment = .testing
        container.setupMockServices()
        return container
    }

    // MARK: - Service Setup

    private func setupDefaultServices() {
        apiClient = APIClient(
            baseURL: Constants.API.baseURL,
            deviceId: deviceId
        )

        webSocketClient = DIWebSocketClient(
            baseURL: Constants.API.wsURL
        )
    }

    private func setupMockServices() {
        apiClient = MockAPIClient()
        webSocketClient = MockWebSocketClient()
    }

    // MARK: - Device ID

    private func loadDeviceId() {
        if let savedId = UserDefaults.standard.string(forKey: Constants.Persistence.deviceIdKey) {
            deviceId = savedId
        } else {
            deviceId = UUID().uuidString
            UserDefaults.standard.set(deviceId, forKey: Constants.Persistence.deviceIdKey)
        }
    }

    // MARK: - Environment

    func setEnvironment(_ env: AppEnvironment) {
        environment = env

        // Reconfigure services for new environment
        switch env {
        case .production:
            setupDefaultServices()
        case .staging:
            // Use staging URLs
            apiClient = APIClient(
                baseURL: "https://staging-server.railway.app",
                deviceId: deviceId
            )
            webSocketClient = DIWebSocketClient(
                baseURL: "wss://staging-server.railway.app"
            )
        case .testing:
            setupMockServices()
        }
    }

    // MARK: - Factory Methods

    /// Create a new model context for background operations
    func newModelContext() -> ModelContext? {
        modelContainer?.mainContext
    }

    // MARK: - Data Management

    /// Clear all local SwiftData on logout for privacy
    func clearAllLocalData() {
        guard let context = modelContainer?.mainContext else {
            print("[DIContainer] No model context available for clearing data")
            return
        }

        do {
            // Delete all records from each model type
            try context.delete(model: CallRecord.self)
            try context.delete(model: SavedPrompt.self)
            try context.delete(model: EventLogEntry.self)
            try context.delete(model: TranscriptEntry.self)
            try context.delete(model: RecordingMetadata.self)
            try context.delete(model: UserSettings.self)
            try context.delete(model: FavoriteContact.self)

            // Save the deletions
            try context.save()

            print("[DIContainer] Successfully cleared all local data")
        } catch {
            print("[DIContainer] Failed to clear local data: \(error)")
        }
    }
}

// MARK: - AppEnvironment

enum AppEnvironment {
    case production
    case staging
    case testing

    var displayName: String {
        switch self {
        case .production: return "Production"
        case .staging: return "Staging"
        case .testing: return "Testing"
        }
    }
}

// MARK: - Service Protocols

/// Protocol for API client
protocol APIClientProtocol {
    func fetchAccessToken() async throws -> String
    func initiateCall(to: String, config: RealtimeConfig) async throws -> [String: Any]
    func endCall(callSid: String) async throws
    func getCallHistory(limit: Int, offset: Int) async throws -> [[String: Any]]
    func getRecordings(limit: Int, offset: Int) async throws -> [[String: Any]]
    func downloadRecording(id: UUID) async throws -> URL
    func getPrompts() async throws -> [[String: Any]]
    func getPromptsTyped() async throws -> [PromptDTO]
    func createPrompt(name: String, instructions: String, voice: String, vadConfig: [String: Any]?) async throws -> PromptDTO
    func updatePrompt(id: UUID, name: String?, instructions: String?, voice: String?, vadConfig: [String: Any]?) async throws -> PromptDTO
    func savePrompt(_ prompt: Prompt) async throws -> Prompt
    func deletePrompt(id: UUID) async throws
    func getFullCallDetails(callSid: String) async throws -> FullCallDetailsResponse
    func optimizePrompt(instructions: String) async throws -> String
}

/// Protocol for WebSocket client
protocol WebSocketClientProtocol {
    var isConnected: Bool { get }
    var connectionState: ConnectionState { get }
    func connect() async throws
    func disconnect()
    func send(_ message: [String: Any]) async throws
    func onMessage(_ handler: @escaping ([String: Any]) -> Void)
    func onDisconnect(_ handler: @escaping (Error?) -> Void)
}

// MARK: - Default Implementations

/// Default API client implementation
class APIClient: APIClientProtocol {
    private let baseURL: String
    private let deviceId: String
    private var accessToken: String?
    private var tokenExpiry: Date?
    private let keychain = KeychainManager.shared

    init(baseURL: String, deviceId: String) {
        self.baseURL = baseURL
        self.deviceId = deviceId
    }

    // MARK: - Auth Header Helper

    /// Add authentication header to request if user is authenticated
    private func addAuthHeader(to request: inout URLRequest) async {
        // Try to get valid auth token
        if keychain.isAuthenticated {
            do {
                let token = try await AuthService.shared.getValidAccessToken()
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            } catch {
                // Fall back to no auth if token refresh fails
                print("Failed to get auth token: \(error)")
            }
        }
    }

    /// Create a request with optional auth
    private func createRequest(url: URL, method: String = "GET") async -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")
        await addAuthHeader(to: &request)
        return request
    }

    func fetchAccessToken() async throws -> String {
        guard let url = URL(string: "\(baseURL)\(Constants.API.Endpoints.token)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["device_id": deviceId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? String else {
            throw APIError.invalidResponse
        }

        accessToken = token
        tokenExpiry = Date().addingTimeInterval(Constants.Twilio.tokenTTL)

        return token
    }

    func initiateCall(to: String, config: RealtimeConfig) async throws -> [String: Any] {
        guard let url = URL(string: "\(baseURL)\(Constants.API.Endpoints.callsOutgoing)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "to": to,
            "device_id": deviceId,
            "config": config.toAPIParams()
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }

        return json
    }

    func endCall(callSid: String) async throws {
        let endpoint = Constants.API.Endpoints.callsEnd.replacingOccurrences(of: ":id", with: callSid)
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }
    }

    func getCallHistory(limit: Int, offset: Int) async throws -> [[String: Any]] {
        guard let url = URL(string: "\(baseURL)\(Constants.API.Endpoints.callsHistory)?limit=\(limit)&offset=\(offset)&device_id=\(deviceId)") else {
            throw APIError.invalidURL
        }

        let request = await createRequest(url: url, method: "GET")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let calls = json["calls"] as? [[String: Any]] else {
            throw APIError.invalidResponse
        }

        return calls
    }

    func getRecordings(limit: Int, offset: Int) async throws -> [[String: Any]] {
        guard let url = URL(string: "\(baseURL)\(Constants.API.Endpoints.recordings)?limit=\(limit)&offset=\(offset)&device_id=\(deviceId)") else {
            throw APIError.invalidURL
        }

        let request = await createRequest(url: url, method: "GET")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let recordings = json["recordings"] as? [[String: Any]] else {
            throw APIError.invalidResponse
        }

        return recordings
    }

    func downloadRecording(id: UUID) async throws -> URL {
        guard let url = URL(string: "\(baseURL)\(Constants.API.Endpoints.recordings)/\(id.uuidString)/download") else {
            throw APIError.invalidURL
        }

        let request = await createRequest(url: url, method: "GET")

        // Download the file
        let (tempURL, response) = try await URLSession.shared.download(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }

        // Move to permanent location in Documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsDir = documentsPath.appendingPathComponent("Recordings", isDirectory: true)

        // Create recordings directory if needed
        try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)

        let localURL = recordingsDir.appendingPathComponent("\(id.uuidString).wav")

        // Remove existing file if present
        if FileManager.default.fileExists(atPath: localURL.path) {
            try FileManager.default.removeItem(at: localURL)
        }

        // Move downloaded file to permanent location
        try FileManager.default.moveItem(at: tempURL, to: localURL)

        return localURL
    }

    func getPrompts() async throws -> [[String: Any]] {
        guard let url = URL(string: "\(baseURL)\(Constants.API.Endpoints.prompts)?device_id=\(deviceId)") else {
            throw APIError.invalidURL
        }

        let request = await createRequest(url: url, method: "GET")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let prompts = json["prompts"] as? [[String: Any]] else {
            throw APIError.invalidResponse
        }

        return prompts
    }

    func getPromptsTyped() async throws -> [PromptDTO] {
        guard let url = URL(string: "\(baseURL)\(Constants.API.Endpoints.prompts)?device_id=\(deviceId)") else {
            throw APIError.invalidURL
        }

        var request = await createRequest(url: url, method: "GET")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let promptsResponse = try decoder.decode(PromptsResponse.self, from: data)
        return promptsResponse.prompts
    }

    func createPrompt(name: String, instructions: String, voice: String, vadConfig: [String: Any]?) async throws -> PromptDTO {
        guard let url = URL(string: "\(baseURL)\(Constants.API.Endpoints.prompts)") else {
            throw APIError.invalidURL
        }

        var request = await createRequest(url: url, method: "POST")

        var body: [String: Any] = [
            "name": name,
            "instructions": instructions,
            "voice": voice,
            "device_id": deviceId
        ]

        if let vadConfig = vadConfig {
            body["vad_config"] = vadConfig
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw APIError.serverError
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let promptResponse = try decoder.decode(PromptResponse.self, from: data)
        return promptResponse.prompt
    }

    func updatePrompt(id: UUID, name: String?, instructions: String?, voice: String?, vadConfig: [String: Any]?) async throws -> PromptDTO {
        guard let url = URL(string: "\(baseURL)\(Constants.API.Endpoints.prompts)/\(id.uuidString)") else {
            throw APIError.invalidURL
        }

        var request = await createRequest(url: url, method: "PUT")

        var body: [String: Any] = [:]
        if let name = name { body["name"] = name }
        if let instructions = instructions { body["instructions"] = instructions }
        if let voice = voice { body["voice"] = voice }
        if let vadConfig = vadConfig { body["vad_config"] = vadConfig }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let promptResponse = try decoder.decode(PromptResponse.self, from: data)
        return promptResponse.prompt
    }

    func savePrompt(_ prompt: Prompt) async throws -> Prompt {
        guard let url = URL(string: "\(baseURL)\(Constants.API.Endpoints.prompts)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "name": prompt.name,
            "instructions": prompt.instructions,
            "voice": prompt.voice.rawValue,
            "is_default": prompt.isDefault,
            "user_id": deviceId
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw APIError.serverError
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let promptResponse = try decoder.decode(PromptResponse.self, from: data)
        return promptResponse.prompt.toPrompt()
    }

    func deletePrompt(id: UUID) async throws {
        guard let url = URL(string: "\(baseURL)\(Constants.API.Endpoints.prompts)/\(id.uuidString)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }
    }

    func getFullCallDetails(callSid: String) async throws -> FullCallDetailsResponse {
        guard let url = URL(string: "\(baseURL)\(Constants.API.Endpoints.calls)/\(callSid)/full") else {
            throw APIError.invalidURL
        }

        let request = await createRequest(url: url, method: "GET")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        return try decoder.decode(FullCallDetailsResponse.self, from: data)
    }

    func optimizePrompt(instructions: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)\(Constants.API.Endpoints.promptsOptimize)") else {
            throw APIError.invalidURL
        }

        var request = await createRequest(url: url, method: "POST")

        let body: [String: Any] = [
            "instructions": instructions
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // Parse response JSON
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }

        // Handle error responses
        if httpResponse.statusCode != 200 {
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw APIError.serverErrorWithMessage(message)
            }
            throw APIError.serverError
        }

        // Extract optimized instructions
        guard let optimizedInstructions = json["optimized_instructions"] as? String else {
            throw APIError.invalidResponse
        }

        return optimizedInstructions
    }
}

/// WebSocket client implementation for DI
class DIWebSocketClient: WebSocketClientProtocol {
    private let baseURL: String
    private var webSocket: URLSessionWebSocketTask?
    private var messageHandler: (([String: Any]) -> Void)?
    private var disconnectHandler: ((Error?) -> Void)?

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var connectionState: ConnectionState = .disconnected

    init(baseURL: String) {
        self.baseURL = baseURL
    }

    func connect() async throws {
        guard let url = URL(string: "\(baseURL)\(Constants.API.WebSocket.iosClient)") else {
            throw APIError.invalidURL
        }

        connectionState = .connecting

        let session = URLSession(configuration: .default)
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()

        isConnected = true
        connectionState = .connected

        // Start receiving messages
        receiveMessages()
    }

    func disconnect() {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        isConnected = false
        connectionState = .disconnected
    }

    func send(_ message: [String: Any]) async throws {
        guard let webSocket = webSocket else {
            throw APIError.notConnected
        }

        let data = try JSONSerialization.data(withJSONObject: message)
        let string = String(data: data, encoding: .utf8) ?? ""

        try await webSocket.send(.string(string))
    }

    func onMessage(_ handler: @escaping ([String: Any]) -> Void) {
        messageHandler = handler
    }

    func onDisconnect(_ handler: @escaping (Error?) -> Void) {
        disconnectHandler = handler
    }

    private func receiveMessages() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        DispatchQueue.main.async {
                            self?.messageHandler?(json)
                        }
                    }
                case .data(let data):
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        DispatchQueue.main.async {
                            self?.messageHandler?(json)
                        }
                    }
                @unknown default:
                    break
                }

                // Continue receiving
                self?.receiveMessages()

            case .failure(let error):
                DispatchQueue.main.async {
                    self?.isConnected = false
                    self?.connectionState = .error(error.localizedDescription)
                    self?.disconnectHandler?(error)
                }
            }
        }
    }
}

// MARK: - Mock Implementations

class MockAPIClient: APIClientProtocol {
    func fetchAccessToken() async throws -> String {
        return "mock-token-\(UUID().uuidString)"
    }

    func initiateCall(to: String, config: RealtimeConfig) async throws -> [String: Any] {
        return ["call_sid": "CA\(UUID().uuidString)", "status": "initiating"]
    }

    func endCall(callSid: String) async throws {}

    func getCallHistory(limit: Int, offset: Int) async throws -> [[String: Any]] {
        return []
    }

    func getRecordings(limit: Int, offset: Int) async throws -> [[String: Any]] {
        return []
    }

    func downloadRecording(id: UUID) async throws -> URL {
        // Return a dummy URL for mock
        return URL(fileURLWithPath: "/tmp/mock-recording-\(id.uuidString).wav")
    }

    func getPrompts() async throws -> [[String: Any]] {
        return []
    }

    func getPromptsTyped() async throws -> [PromptDTO] {
        return []
    }

    func createPrompt(name: String, instructions: String, voice: String, vadConfig: [String: Any]?) async throws -> PromptDTO {
        return PromptDTO(
            id: UUID(),
            userId: nil,
            name: name,
            instructions: instructions,
            voice: voice,
            vadConfig: nil,
            isDefault: false,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func updatePrompt(id: UUID, name: String?, instructions: String?, voice: String?, vadConfig: [String: Any]?) async throws -> PromptDTO {
        return PromptDTO(
            id: id,
            userId: nil,
            name: name ?? "Updated Prompt",
            instructions: instructions ?? "Updated instructions",
            voice: voice ?? "marin",
            vadConfig: nil,
            isDefault: false,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func savePrompt(_ prompt: Prompt) async throws -> Prompt {
        return prompt
    }

    func deletePrompt(id: UUID) async throws {}

    func getFullCallDetails(callSid: String) async throws -> FullCallDetailsResponse {
        return FullCallDetailsResponse(
            source: "mock",
            call: FullCallInfo(
                id: UUID(),
                callSid: callSid,
                direction: "outbound",
                phoneNumber: "+1234567890",
                status: "ended",
                startedAt: Date(),
                endedAt: Date(),
                durationSeconds: 60,
                config: nil,
                userId: nil,
                prompt: nil
            ),
            events: [],
            transcripts: [],
            recordings: [],
            statistics: nil
        )
    }

    func optimizePrompt(instructions: String) async throws -> String {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 500_000_000)
        return "OPTIMIZED: \(instructions)"
    }
}

class MockWebSocketClient: WebSocketClientProtocol {
    var isConnected: Bool = false
    var connectionState: ConnectionState = .disconnected

    func connect() async throws {
        isConnected = true
        connectionState = .connected
    }

    func disconnect() {
        isConnected = false
        connectionState = .disconnected
    }

    func send(_ message: [String: Any]) async throws {}

    func onMessage(_ handler: @escaping ([String: Any]) -> Void) {}

    func onDisconnect(_ handler: @escaping (Error?) -> Void) {}
}

// MARK: - API Errors

enum APIError: LocalizedError {
    case invalidURL
    case serverError
    case serverErrorWithMessage(String)
    case invalidResponse
    case notConnected
    case tokenExpired

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .serverError: return "Server error"
        case .serverErrorWithMessage(let message): return message
        case .invalidResponse: return "Invalid response"
        case .notConnected: return "Not connected"
        case .tokenExpired: return "Token expired"
        }
    }
}

