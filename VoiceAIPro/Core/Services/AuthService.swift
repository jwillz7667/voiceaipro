import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

/// Authentication service for managing user sessions
@MainActor
final class AuthService: ObservableObject {
    // MARK: - Singleton

    static let shared = AuthService()

    // MARK: - Published State

    @Published private(set) var isAuthenticated = false
    @Published private(set) var currentUser: AuthUser?
    @Published private(set) var isLoading = false
    @Published private(set) var error: AuthServiceError?

    // MARK: - Properties

    private let keychain = KeychainManager.shared
    private let baseURL: String
    private var refreshTask: Task<AuthTokens, Error>?

    // MARK: - Initialization

    private init() {
        self.baseURL = Constants.API.baseURL

        // Check for existing session on init
        Task {
            await checkExistingSession()
        }
    }

    // MARK: - Session Management

    /// Check if user has existing valid session
    private func checkExistingSession() async {
        guard keychain.isAuthenticated else {
            isAuthenticated = false
            currentUser = nil
            return
        }

        // Try to get current user with existing token
        do {
            let user = try await fetchCurrentUser()
            self.currentUser = user
            self.isAuthenticated = true
        } catch {
            // Token might be expired, try to refresh
            if let _ = keychain.getRefreshToken() {
                do {
                    let _ = try await refreshTokens()
                    let user = try await fetchCurrentUser()
                    self.currentUser = user
                    self.isAuthenticated = true
                } catch {
                    // Refresh failed, clear session
                    logout()
                }
            } else {
                logout()
            }
        }
    }

    // MARK: - Registration

    /// Register a new user
    func register(email: String, password: String, name: String? = nil) async throws -> AuthUser {
        isLoading = true
        error = nil

        defer { isLoading = false }

        let url = URL(string: "\(baseURL)/api/auth/register")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "email": email,
            "password": password,
        ]
        if let name = name {
            body["name"] = name
        }

        // Include device_id for data migration
        body["device_id"] = getDeviceId()

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthServiceError.invalidResponse
        }

        if httpResponse.statusCode == 201 {
            let result = try JSONDecoder().decode(RegisterResponse.self, from: data)
            return result.user
        } else {
            let errorResponse = try? JSONDecoder().decode(AuthErrorResponse.self, from: data)
            throw AuthServiceError.serverError(
                code: errorResponse?.error.code ?? "UNKNOWN",
                message: errorResponse?.error.message ?? "Registration failed"
            )
        }
    }

    // MARK: - Login

    /// Login with email and password
    func login(email: String, password: String) async throws {
        isLoading = true
        error = nil

        defer { isLoading = false }

        let url = URL(string: "\(baseURL)/api/auth/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "email": email,
            "password": password,
            "device_id": getDeviceId(),
            "device_name": getDeviceName(),
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthServiceError.invalidResponse
        }

        if httpResponse.statusCode == 200 {
            let result = try JSONDecoder().decode(LoginResponse.self, from: data)

            // Store tokens in keychain
            try keychain.storeAuthTokens(
                accessToken: result.accessToken,
                refreshToken: result.refreshToken,
                expiresAt: result.expiresAt ?? Date().addingTimeInterval(15 * 60),
                userId: result.user.id,
                email: result.user.email
            )

            self.currentUser = result.user
            self.isAuthenticated = true
        } else {
            let errorResponse = try? JSONDecoder().decode(AuthErrorResponse.self, from: data)
            throw AuthServiceError.serverError(
                code: errorResponse?.error.code ?? "UNKNOWN",
                message: errorResponse?.error.message ?? "Login failed"
            )
        }
    }

    // MARK: - Logout

    /// Logout current user
    func logout() {
        // Clear tokens from keychain
        keychain.clearAll()

        // Reset state
        isAuthenticated = false
        currentUser = nil
        error = nil

        // Notify server (fire and forget)
        Task {
            try? await notifyServerLogout()
        }
    }

    private func notifyServerLogout() async throws {
        guard let refreshToken = keychain.getRefreshToken() else { return }

        let url = URL(string: "\(baseURL)/api/auth/logout")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["refresh_token": refreshToken]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - Token Refresh

    /// Refresh access token
    func refreshTokens() async throws -> AuthTokens {
        // Deduplicate concurrent refresh requests
        if let existingTask = refreshTask {
            return try await existingTask.value
        }

        let task = Task<AuthTokens, Error> {
            defer { refreshTask = nil }

            guard let refreshToken = keychain.getRefreshToken() else {
                throw AuthServiceError.noRefreshToken
            }

            let url = URL(string: "\(baseURL)/api/auth/refresh")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body = ["refresh_token": refreshToken]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthServiceError.invalidResponse
            }

            if httpResponse.statusCode == 200 {
                let result = try JSONDecoder().decode(RefreshResponse.self, from: data)

                // Update access token in keychain
                try keychain.setAccessToken(result.accessToken)

                // Update expiry (assume 15 minutes from now)
                try keychain.setTokenExpiry(Date().addingTimeInterval(15 * 60))

                return AuthTokens(
                    accessToken: result.accessToken,
                    refreshToken: refreshToken
                )
            } else {
                // Refresh failed - token likely revoked
                await MainActor.run {
                    self.logout()
                }
                throw AuthServiceError.sessionExpired
            }
        }

        refreshTask = task
        return try await task.value
    }

    // MARK: - Get Valid Token

    /// Get a valid access token, refreshing if necessary
    func getValidAccessToken() async throws -> String {
        guard let accessToken = keychain.getAccessToken() else {
            throw AuthServiceError.notAuthenticated
        }

        // Check if token is expired
        if keychain.isAccessTokenExpired() {
            let tokens = try await refreshTokens()
            return tokens.accessToken
        }

        return accessToken
    }

    // MARK: - Password Reset

    /// Request password reset email
    func requestPasswordReset(email: String) async throws {
        isLoading = true
        error = nil

        defer { isLoading = false }

        let url = URL(string: "\(baseURL)/api/auth/forgot-password")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["email": email]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorResponse = try? JSONDecoder().decode(AuthErrorResponse.self, from: data)
            throw AuthServiceError.serverError(
                code: errorResponse?.error.code ?? "UNKNOWN",
                message: errorResponse?.error.message ?? "Failed to request password reset"
            )
        }
    }

    // MARK: - Fetch Current User

    private func fetchCurrentUser() async throws -> AuthUser {
        guard let accessToken = keychain.getAccessToken() else {
            throw AuthServiceError.notAuthenticated
        }

        let url = URL(string: "\(baseURL)/api/auth/me")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthServiceError.invalidResponse
        }

        if httpResponse.statusCode == 200 {
            let result = try JSONDecoder().decode(MeResponse.self, from: data)
            return result.user
        } else if httpResponse.statusCode == 401 {
            throw AuthServiceError.sessionExpired
        } else {
            let errorResponse = try? JSONDecoder().decode(AuthErrorResponse.self, from: data)
            throw AuthServiceError.serverError(
                code: errorResponse?.error.code ?? "UNKNOWN",
                message: errorResponse?.error.message ?? "Failed to get user"
            )
        }
    }

    // MARK: - Device Info

    private func getDeviceId() -> String {
        // Use existing device ID from DIContainer/UserDefaults
        if let savedId = UserDefaults.standard.string(forKey: "VoiceAIPro.deviceId") {
            return savedId
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: "VoiceAIPro.deviceId")
        return newId
    }

    private func getDeviceName() -> String {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return "Unknown Device"
        #endif
    }
}

// MARK: - Response Models

struct RegisterResponse: Codable {
    let success: Bool
    let message: String
    let user: AuthUser
    let verificationToken: String?
}

struct LoginResponse: Codable {
    let success: Bool
    let user: AuthUser
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case success, user
        case accessToken = "accessToken"
        case refreshToken = "refreshToken"
        case expiresAt = "expiresAt"
    }
}

struct RefreshResponse: Codable {
    let success: Bool
    let accessToken: String
    let user: AuthUser?
}

struct MeResponse: Codable {
    let user: AuthUser
}

/// Auth-specific error response (server returns nested error object)
private struct AuthErrorResponse: Codable {
    let error: AuthAPIError

    struct AuthAPIError: Codable {
        let code: String
        let message: String
    }
}

// MARK: - Models

struct AuthUser: Codable, Identifiable, Equatable {
    let id: String
    let email: String
    let name: String?
    let emailVerified: Bool

    enum CodingKeys: String, CodingKey {
        case id, email, name
        case emailVerified = "emailVerified"
    }
}

struct AuthTokens {
    let accessToken: String
    let refreshToken: String
}

// MARK: - Errors

enum AuthServiceError: LocalizedError {
    case invalidResponse
    case notAuthenticated
    case noRefreshToken
    case sessionExpired
    case serverError(code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .notAuthenticated:
            return "Not authenticated"
        case .noRefreshToken:
            return "No refresh token available"
        case .sessionExpired:
            return "Session expired. Please login again."
        case .serverError(_, let message):
            return message
        }
    }

    var isSessionExpired: Bool {
        if case .sessionExpired = self {
            return true
        }
        return false
    }
}
