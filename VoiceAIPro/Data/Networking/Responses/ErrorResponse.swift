import Foundation

/// Error response from server
struct ErrorResponse: Codable {
    /// Error type/code
    let error: String

    /// Human-readable message
    let message: String

    /// HTTP status code
    let statusCode: Int?

    /// Additional details
    let details: [String: String]?

    /// Timestamp
    let timestamp: Date?

    /// Request ID for debugging
    let requestId: String?

    enum CodingKeys: String, CodingKey {
        case error
        case message
        case statusCode = "status_code"
        case details
        case timestamp
        case requestId = "request_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        error = try container.decode(String.self, forKey: .error)
        message = try container.decode(String.self, forKey: .message)
        statusCode = try container.decodeIfPresent(Int.self, forKey: .statusCode)
        details = try container.decodeIfPresent([String: String].self, forKey: .details)
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId)

        if let timestampString = try? container.decode(String.self, forKey: .timestamp) {
            let formatter = ISO8601DateFormatter()
            timestamp = formatter.date(from: timestampString)
        } else {
            timestamp = nil
        }
    }
}

/// Validation error response
struct ValidationErrorResponse: Codable {
    /// Error type
    let error: String

    /// Overall message
    let message: String

    /// Field-specific errors
    let errors: [FieldError]?

    struct FieldError: Codable {
        let field: String
        let message: String
        let code: String?
    }
}

// MARK: - Error Parsing Extension

extension NetworkError {
    /// Parse error from response data
    static func from(data: Data, statusCode: Int) -> NetworkError {
        if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            return .serverError(statusCode)
        }
        return .httpError(statusCode)
    }
}
