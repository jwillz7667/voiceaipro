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

    /// Initialize from server response dictionary
    init?(from dict: [String: Any]) {
        // Required fields
        guard let idString = dict["id"] as? String,
              let id = UUID(uuidString: idString),
              let callSid = dict["call_sid"] as? String,
              let direction = dict["direction"] as? String,
              let phoneNumber = dict["phone_number"] as? String,
              let status = dict["status"] as? String,
              let startedAtString = dict["started_at"] as? String else {
            return nil
        }

        // Parse date
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let startedAt = formatter.date(from: startedAtString) else {
            return nil
        }

        self.id = id
        self.callSid = callSid
        self.direction = direction
        self.phoneNumber = phoneNumber
        self.status = status
        self.startedAt = startedAt

        // Optional fields
        if let endedAtString = dict["ended_at"] as? String {
            self.endedAt = formatter.date(from: endedAtString)
        } else {
            self.endedAt = nil
        }

        self.durationSeconds = dict["duration_seconds"] as? Int
        self.hasRecording = dict["has_recording"] as? Bool
        if let recordingIdString = dict["recording_id"] as? String {
            self.recordingId = UUID(uuidString: recordingIdString)
        } else {
            self.recordingId = nil
        }
        self.promptName = dict["prompt_name"] as? String
    }
}
