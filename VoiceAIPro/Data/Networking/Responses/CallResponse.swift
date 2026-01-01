import Foundation

/// Response from call initiation endpoint
struct CallResponse: Codable {
    /// Twilio call SID
    let callSid: String

    /// Call status
    let status: String

    /// Direction (outbound/inbound)
    let direction: String?

    /// Phone number being called
    let to: String?

    /// Caller phone number
    let from: String?

    /// Prompt ID used
    let promptId: String?

    /// Session ID for WebSocket
    let sessionId: String?

    /// Timestamp
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case callSid = "call_sid"
        case status
        case direction
        case to
        case from
        case promptId = "prompt_id"
        case sessionId = "session_id"
        case createdAt = "created_at"
    }

    /// Parsed call status
    var callStatus: CallStatus? {
        CallStatus(rawValue: status)
    }

    /// Parsed call direction
    var callDirection: CallDirection? {
        CallDirection(rawValue: direction ?? "")
    }
}

/// Response containing call history
struct CallHistoryResponse: Codable {
    /// List of calls
    let calls: [CallHistoryItem]

    /// Total count
    let total: Int?

    /// Current offset
    let offset: Int?

    /// Limit used
    let limit: Int?
}
