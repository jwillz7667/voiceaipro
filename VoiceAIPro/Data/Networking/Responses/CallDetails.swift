import Foundation

/// Detailed call information
/// Note: Uses automatic snake_case conversion from NetworkingAPIClient's keyDecodingStrategy
struct CallDetails: Codable, Identifiable {
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

    /// Prompt ID used
    let promptId: UUID?

    /// Prompt name
    let promptName: String?

    /// Prompt instructions
    let promptInstructions: String?

    /// Configuration used
    let config: ConfigSnapshot?

    /// Recording info
    let recording: RecordingInfo?

    /// Transcript
    let transcript: [TranscriptItem]?

    /// Events count
    let eventsCount: Int?

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
}

/// Configuration snapshot stored with call
struct ConfigSnapshot: Codable {
    let model: String?
    let voice: String?
    let vadType: String?
    let transcriptionModel: String?
}

/// Recording info
struct RecordingInfo: Codable, Identifiable {
    let id: UUID
    let duration: Int?
    let fileSize: Int?
    let format: String?
    let createdAt: Date?

    /// Formatted duration
    var formattedDuration: String {
        guard let duration = duration else { return "--:--" }
        return Date.formatSeconds(duration)
    }

    /// Formatted file size
    var formattedFileSize: String {
        guard let size = fileSize else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

/// Transcript item
struct TranscriptItem: Codable, Identifiable {
    let id: UUID
    let speaker: String
    let content: String
    let timestamp: Date?

    /// Whether this is from the user
    var isUser: Bool {
        speaker.lowercased() == "user"
    }

    /// Whether this is from the AI
    var isAssistant: Bool {
        speaker.lowercased() == "assistant"
    }

    /// Formatted timestamp
    var formattedTimestamp: String {
        timestamp?.preciseTimeFormatted ?? ""
    }
}
