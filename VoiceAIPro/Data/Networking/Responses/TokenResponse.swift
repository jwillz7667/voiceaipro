import Foundation

/// Response from token endpoint
struct TokenResponse: Codable {
    /// Access token
    let token: String

    /// Token type (usually "Bearer")
    let tokenType: String?

    /// Expiration timestamp
    let expiresAt: Date?

    /// Token TTL in seconds
    let expiresIn: Int?

    /// Identity the token was issued for
    let identity: String?

    enum CodingKeys: String, CodingKey {
        case token
        case tokenType = "token_type"
        case expiresAt = "expires_at"
        case expiresIn = "expires_in"
        case identity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = try container.decode(String.self, forKey: .token)
        tokenType = try container.decodeIfPresent(String.self, forKey: .tokenType)
        identity = try container.decodeIfPresent(String.self, forKey: .identity)

        // Handle expiration - could be date or seconds
        if let expiresAtString = try? container.decode(String.self, forKey: .expiresAt) {
            let formatter = ISO8601DateFormatter()
            expiresAt = formatter.date(from: expiresAtString)
            expiresIn = nil
        } else if let seconds = try? container.decode(Int.self, forKey: .expiresIn) {
            expiresIn = seconds
            expiresAt = Date().addingTimeInterval(TimeInterval(seconds))
        } else {
            expiresAt = Date().addingTimeInterval(Constants.Twilio.tokenTTL)
            expiresIn = Int(Constants.Twilio.tokenTTL)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(token, forKey: .token)
        try container.encodeIfPresent(tokenType, forKey: .tokenType)
        try container.encodeIfPresent(identity, forKey: .identity)
        try container.encodeIfPresent(expiresIn, forKey: .expiresIn)

        if let expiresAt = expiresAt {
            let formatter = ISO8601DateFormatter()
            try container.encode(formatter.string(from: expiresAt), forKey: .expiresAt)
        }
    }
}
