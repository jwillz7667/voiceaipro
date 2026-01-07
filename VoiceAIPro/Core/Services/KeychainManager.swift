import Foundation
import Security

/// Manages secure storage of authentication tokens in the iOS Keychain
final class KeychainManager {
    // MARK: - Singleton

    static let shared = KeychainManager()

    // MARK: - Constants

    private enum Keys {
        static let accessToken = "com.voiceaipro.accessToken"
        static let refreshToken = "com.voiceaipro.refreshToken"
        static let tokenExpiry = "com.voiceaipro.tokenExpiry"
        static let userId = "com.voiceaipro.userId"
        static let userEmail = "com.voiceaipro.userEmail"
    }

    private let service = "com.voiceaipro.auth"

    // MARK: - Initialization

    private init() {}

    // MARK: - Token Management

    /// Store access token
    func setAccessToken(_ token: String) throws {
        try set(token, forKey: Keys.accessToken)
    }

    /// Get access token
    func getAccessToken() -> String? {
        return get(Keys.accessToken)
    }

    /// Store refresh token
    func setRefreshToken(_ token: String) throws {
        try set(token, forKey: Keys.refreshToken)
    }

    /// Get refresh token
    func getRefreshToken() -> String? {
        return get(Keys.refreshToken)
    }

    /// Store token expiry date
    func setTokenExpiry(_ date: Date) throws {
        let timestamp = date.timeIntervalSince1970
        try set(String(timestamp), forKey: Keys.tokenExpiry)
    }

    /// Get token expiry date
    func getTokenExpiry() -> Date? {
        guard let timestampStr = get(Keys.tokenExpiry),
              let timestamp = Double(timestampStr) else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    /// Check if access token is expired
    func isAccessTokenExpired() -> Bool {
        guard let expiry = getTokenExpiry() else {
            return true
        }
        // Consider token expired 30 seconds before actual expiry
        return expiry.addingTimeInterval(-30) <= Date()
    }

    /// Store user ID
    func setUserId(_ userId: String) throws {
        try set(userId, forKey: Keys.userId)
    }

    /// Get user ID
    func getUserId() -> String? {
        return get(Keys.userId)
    }

    /// Store user email
    func setUserEmail(_ email: String) throws {
        try set(email, forKey: Keys.userEmail)
    }

    /// Get user email
    func getUserEmail() -> String? {
        return get(Keys.userEmail)
    }

    /// Store all auth tokens at once
    func storeAuthTokens(accessToken: String, refreshToken: String, expiresAt: Date, userId: String, email: String) throws {
        try setAccessToken(accessToken)
        try setRefreshToken(refreshToken)
        try setTokenExpiry(expiresAt)
        try setUserId(userId)
        try setUserEmail(email)
    }

    /// Clear all stored tokens (logout)
    func clearAll() {
        delete(Keys.accessToken)
        delete(Keys.refreshToken)
        delete(Keys.tokenExpiry)
        delete(Keys.userId)
        delete(Keys.userEmail)
    }

    /// Check if user is authenticated (has valid tokens)
    var isAuthenticated: Bool {
        guard let _ = getAccessToken(),
              let _ = getRefreshToken() else {
            return false
        }
        return true
    }

    // MARK: - Private Keychain Operations

    private func set(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Delete existing item first
        delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    private func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    private func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

enum KeychainError: LocalizedError {
    case encodingFailed
    case saveFailed(OSStatus)
    case readFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode data for Keychain"
        case .saveFailed(let status):
            return "Failed to save to Keychain: \(status)"
        case .readFailed(let status):
            return "Failed to read from Keychain: \(status)"
        }
    }
}
