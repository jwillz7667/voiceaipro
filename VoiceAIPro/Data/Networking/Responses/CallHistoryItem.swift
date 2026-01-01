import Foundation

/// Single call in history
struct CallHistoryItem: Codable, Identifiable {
    /// Unique identifier
    let id: UUID

    /// Twilio call SID
    let callSid: String

    /// Direction (outbound/inbound)
    let direction: String

    /// Phone number
    let phoneNumber: String

    /// Call status
    let status: String

    /// Call start time
    let startedAt: Date

    /// Call end time
    let endedAt: Date?

    /// Duration in seconds
    let durationSeconds: Int?

    /// Whether call has recording
    let hasRecording: Bool?

    /// Recording ID if available
    let recordingId: UUID?

    /// Prompt used
    let promptName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case callSid = "call_sid"
        case direction
        case phoneNumber = "phone_number"
        case status
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationSeconds = "duration_seconds"
        case hasRecording = "has_recording"
        case recordingId = "recording_id"
        case promptName = "prompt_name"
    }

    /// Parsed call status
    var callStatus: CallStatus? {
        CallStatus(rawValue: status)
    }

    /// Parsed call direction
    var callDirection: CallDirection {
        CallDirection(rawValue: direction) ?? .outbound
    }

    /// Formatted duration
    var formattedDuration: String {
        guard let duration = durationSeconds else { return "--:--" }
        return Date.formatSeconds(duration)
    }

    /// Formatted phone number
    var formattedPhoneNumber: String {
        phoneNumber.formattedPhoneNumber
    }

    /// Formatted start time
    var formattedStartTime: String {
        startedAt.smartFormatted
    }

    /// Convert to CallSession
    func toCallSession() -> CallSession {
        CallSession(
            id: id,
            callSid: callSid,
            direction: callDirection,
            phoneNumber: phoneNumber,
            status: callStatus ?? .ended,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            config: .default
        )
    }
}
