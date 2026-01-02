import Foundation

/// Type-safe API client using actor isolation
actor NetworkingAPIClient {
    // MARK: - Singleton

    static let shared = NetworkingAPIClient()

    // MARK: - Properties

    /// URL session for requests
    private let session: URLSession

    /// Base URL for API
    private let baseURL: URL

    /// JSON decoder
    private let decoder: JSONDecoder

    /// JSON encoder
    private let encoder: JSONEncoder

    /// Device ID for authentication
    private var deviceId: String

    /// Current access token
    private var accessToken: String?

    /// Token expiry date
    private var tokenExpiry: Date?

    // MARK: - Initialization

    init(
        baseURL: URL = URL(string: Constants.API.baseURL)!,
        session: URLSession = .shared,
        deviceId: String = ""
    ) {
        self.baseURL = baseURL
        self.session = session
        self.deviceId = deviceId

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    /// Set device ID
    func setDeviceId(_ id: String) {
        deviceId = id
    }

    // MARK: - Generic Request Methods

    /// Make a request and decode the response
    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        let request = try buildRequest(for: endpoint)
        let (data, response) = try await session.data(for: request)

        try validateResponse(response)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingFailed(error.localizedDescription)
        }
    }

    /// Make a request without expecting a response body
    func requestVoid(_ endpoint: Endpoint) async throws {
        let request = try buildRequest(for: endpoint)
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }

    // MARK: - Token Management

    /// Fetch access token
    func fetchAccessToken(identity: String? = nil) async throws -> TokenResponse {
        let endpoint = Endpoint.token(identity: identity ?? deviceId)
        let response: TokenResponse = try await request(endpoint)

        accessToken = response.token
        tokenExpiry = response.expiresAt

        return response
    }

    /// Get current token or fetch new one
    func getValidToken() async throws -> String {
        if let token = accessToken, let expiry = tokenExpiry, expiry > Date() {
            return token
        }

        let response = try await fetchAccessToken()
        return response.token
    }

    // MARK: - Call Endpoints

    /// Initiate an outbound call
    func initiateCall(to: String, promptId: UUID?, config: RealtimeConfig) async throws -> CallResponse {
        let endpoint = Endpoint.initiateCall(to: to, promptId: promptId, config: config, deviceId: deviceId)
        return try await request(endpoint)
    }

    /// End a call
    func endCall(callSid: String) async throws {
        let endpoint = Endpoint.endCall(callSid: callSid)
        try await requestVoid(endpoint)
    }

    /// Get call history
    func getCallHistory(limit: Int = 50, offset: Int = 0) async throws -> CallHistoryResponse {
        let endpoint = Endpoint.callHistory(limit: limit, offset: offset, deviceId: deviceId)
        return try await request(endpoint)
    }

    /// Get call details
    func getCallDetails(callSid: String) async throws -> CallDetails {
        let endpoint = Endpoint.callDetails(callSid: callSid)
        return try await request(endpoint)
    }

    // MARK: - Recording Endpoints

    /// Get recordings list
    func getRecordings(limit: Int = 50, offset: Int = 0) async throws -> RecordingsResponse {
        let endpoint = Endpoint.recordings(limit: limit, offset: offset, deviceId: deviceId)
        return try await request(endpoint)
    }

    /// Get recording URL
    func getRecordingURL(id: UUID) -> URL {
        baseURL.appendingPathComponent(Constants.API.Endpoints.recordings)
            .appendingPathComponent(id.uuidString)
            .appendingPathComponent("audio")
    }

    /// Delete recording
    func deleteRecording(id: UUID) async throws {
        let endpoint = Endpoint.deleteRecording(id: id)
        try await requestVoid(endpoint)
    }

    // MARK: - Prompt Endpoints

    /// Get all prompts
    func getPrompts() async throws -> PromptsResponse {
        let endpoint = Endpoint.prompts(deviceId: deviceId)
        return try await request(endpoint)
    }

    /// Create a new prompt
    func createPrompt(_ prompt: Prompt) async throws -> PromptResponse {
        let endpoint = Endpoint.createPrompt(prompt, deviceId: deviceId)
        return try await request(endpoint)
    }

    /// Update an existing prompt
    func updatePrompt(_ prompt: Prompt) async throws -> PromptResponse {
        let endpoint = Endpoint.updatePrompt(prompt)
        return try await request(endpoint)
    }

    /// Delete a prompt
    func deletePrompt(id: UUID) async throws {
        let endpoint = Endpoint.deletePrompt(id: id)
        try await requestVoid(endpoint)
    }

    /// Set default prompt
    func setDefaultPrompt(id: UUID) async throws {
        let endpoint = Endpoint.setDefaultPrompt(id: id, deviceId: deviceId)
        try await requestVoid(endpoint)
    }

    // MARK: - Private Methods

    private func buildRequest(for endpoint: Endpoint) throws -> URLRequest {
        let url = baseURL.appendingPathComponent(endpoint.path)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)

        // Add query parameters
        if let queryItems = endpoint.queryItems, !queryItems.isEmpty {
            components?.queryItems = queryItems
        }

        guard let finalURL = components?.url else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = endpoint.method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Add auth token if available
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Add body
        if let body = endpoint.body {
            request.httpBody = try encoder.encode(body)
        } else if let rawBody = endpoint.rawBody {
            request.httpBody = try JSONSerialization.data(withJSONObject: rawBody)
        }

        return request
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw NetworkError.unauthorized
        case 404:
            throw NetworkError.notFound
        case 422:
            throw NetworkError.validationError
        case 500...599:
            throw NetworkError.serverError(httpResponse.statusCode)
        default:
            throw NetworkError.httpError(httpResponse.statusCode)
        }
    }
}

// MARK: - Endpoint

/// API endpoints with type-safe configuration
enum Endpoint {
    case token(identity: String)
    case initiateCall(to: String, promptId: UUID?, config: RealtimeConfig, deviceId: String)
    case endCall(callSid: String)
    case callHistory(limit: Int, offset: Int, deviceId: String)
    case callDetails(callSid: String)
    case recordings(limit: Int, offset: Int, deviceId: String)
    case deleteRecording(id: UUID)
    case prompts(deviceId: String)
    case createPrompt(Prompt, deviceId: String)
    case updatePrompt(Prompt)
    case deletePrompt(id: UUID)
    case setDefaultPrompt(id: UUID, deviceId: String)

    var path: String {
        switch self {
        case .token:
            return Constants.API.Endpoints.token
        case .initiateCall:
            return Constants.API.Endpoints.callsOutgoing
        case .endCall(let callSid):
            return Constants.API.Endpoints.callsEnd.replacingOccurrences(of: ":id", with: callSid)
        case .callHistory:
            return Constants.API.Endpoints.callsHistory
        case .callDetails(let callSid):
            return "\(Constants.API.Endpoints.calls)/\(callSid)"
        case .recordings:
            return Constants.API.Endpoints.recordings
        case .deleteRecording(let id):
            return "\(Constants.API.Endpoints.recordings)/\(id.uuidString)"
        case .prompts:
            return Constants.API.Endpoints.prompts
        case .createPrompt:
            return Constants.API.Endpoints.prompts
        case .updatePrompt(let prompt):
            return "\(Constants.API.Endpoints.prompts)/\(prompt.id.uuidString)"
        case .deletePrompt(let id):
            return "\(Constants.API.Endpoints.prompts)/\(id.uuidString)"
        case .setDefaultPrompt(let id, _):
            return "\(Constants.API.Endpoints.prompts)/\(id.uuidString)/default"
        }
    }

    var method: String {
        switch self {
        case .token, .initiateCall, .endCall, .createPrompt, .setDefaultPrompt:
            return "POST"
        case .callHistory, .callDetails, .recordings, .prompts:
            return "GET"
        case .updatePrompt:
            return "PUT"
        case .deleteRecording, .deletePrompt:
            return "DELETE"
        }
    }

    var queryItems: [URLQueryItem]? {
        switch self {
        case .callHistory(let limit, let offset, let deviceId):
            return [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "device_id", value: deviceId)
            ]
        case .recordings(let limit, let offset, let deviceId):
            return [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "device_id", value: deviceId)
            ]
        case .prompts(let deviceId):
            return [URLQueryItem(name: "device_id", value: deviceId)]
        default:
            return nil
        }
    }

    var body: Encodable? {
        switch self {
        case .updatePrompt(let prompt):
            return prompt
        default:
            return nil
        }
    }

    var rawBody: [String: Any]? {
        switch self {
        case .token(let identity):
            return ["device_id": identity]
        case .initiateCall(let to, let promptId, let config, let deviceId):
            var body: [String: Any] = [
                "to": to,
                "device_id": deviceId,
                "config": config.toAPIParams()
            ]
            if let promptId = promptId {
                body["prompt_id"] = promptId.uuidString
            }
            return body
        case .createPrompt(let prompt, let deviceId):
            // Include user_id (device_id) in the request for server-side storage
            return [
                "id": prompt.id.uuidString,
                "user_id": deviceId,
                "name": prompt.name,
                "instructions": prompt.instructions,
                "voice": prompt.voice.rawValue,
                "vad_config": prompt.vadConfig.toAPIParams(),
                "is_default": prompt.isDefault
            ]
        case .setDefaultPrompt(_, let deviceId):
            return ["device_id": deviceId]
        default:
            return nil
        }
    }
}

// MARK: - Network Errors

enum NetworkError: LocalizedError {
    case invalidURL
    case invalidResponse
    case decodingFailed(String)
    case unauthorized
    case notFound
    case validationError
    case serverError(Int)
    case httpError(Int)
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .decodingFailed(let message):
            return "Failed to decode response: \(message)"
        case .unauthorized:
            return "Unauthorized - please re-authenticate"
        case .notFound:
            return "Resource not found"
        case .validationError:
            return "Validation error"
        case .serverError(let code):
            return "Server error (\(code))"
        case .httpError(let code):
            return "HTTP error (\(code))"
        case .noData:
            return "No data received"
        }
    }
}
