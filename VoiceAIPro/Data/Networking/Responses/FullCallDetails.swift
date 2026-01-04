import Foundation

/// Full call details response from the server
/// Matches the server's /api/calls/:callSid/full endpoint
struct FullCallDetailsResponse: Codable {
    /// Source of data (database or active)
    let source: String?

    /// Call details
    let call: FullCallInfo

    /// Event log entries
    let events: [ServerEventEntry]?

    /// Transcript entries
    let transcripts: [ServerTranscriptEntry]?

    /// Recording entries
    let recordings: [ServerRecordingEntry]?

    /// Statistics
    let statistics: CallStatistics?
}

/// Full call info from server
struct FullCallInfo: Codable, Identifiable {
    let id: UUID
    let callSid: String?
    let direction: String
    let phoneNumber: String
    let status: String
    let startedAt: Date
    let endedAt: Date?
    let durationSeconds: Int?
    let config: AnyCodable?
    let userId: String?
    let prompt: ServerPromptInfo?

    enum CodingKeys: String, CodingKey {
        case id
        case callSid = "call_sid"
        case direction
        case phoneNumber = "phone_number"
        case status
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationSeconds = "duration_seconds"
        case config
        case userId = "user_id"
        case prompt
    }
}

/// Prompt info from server
struct ServerPromptInfo: Codable {
    let id: UUID
    let name: String?
    let instructions: String?
    let voice: String?
}

/// Event entry from server
struct ServerEventEntry: Codable, Identifiable {
    let id: UUID
    let eventType: String
    let direction: String?
    let payload: AnyCodable?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case eventType = "event_type"
        case direction
        case payload
        case createdAt = "created_at"
    }
}

/// Transcript entry from server
struct ServerTranscriptEntry: Codable, Identifiable {
    let id: UUID
    let speaker: String
    let content: String
    let timestampMs: Int?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case speaker
        case content
        case timestampMs = "timestamp_ms"
        case createdAt = "created_at"
    }

    /// Convert to SwiftData TranscriptEntry
    func toTranscriptEntry(callSid: String?) -> TranscriptEntry {
        TranscriptEntry(
            id: id,
            speaker: speaker,
            content: content,
            timestampMs: timestampMs,
            createdAt: createdAt ?? Date(),
            callSid: callSid,
            isFinal: true
        )
    }
}

/// Recording entry from server
struct ServerRecordingEntry: Codable, Identifiable {
    let id: UUID
    let durationSeconds: Int?
    let fileSizeBytes: Int64?
    let format: String?
    let createdAt: Date?
    let callSid: String?
    let sampleRate: Int?
    let channels: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case durationSeconds = "duration_seconds"
        case fileSizeBytes = "file_size_bytes"
        case format
        case createdAt = "created_at"
        case callSid = "call_sid"
        case sampleRate = "sample_rate"
        case channels
    }

    /// Convert to SwiftData RecordingMetadata
    func toRecordingMetadata(callSessionId: UUID) -> RecordingMetadata {
        RecordingMetadata(
            id: id,
            callSessionId: callSessionId,
            callSid: callSid,
            durationSeconds: durationSeconds ?? 0,
            fileSizeBytes: fileSizeBytes ?? 0,
            format: format ?? "wav",
            sampleRate: sampleRate,
            channels: channels,
            createdAt: createdAt ?? Date(),
            syncedAt: Date(),
            hasTranscript: false
        )
    }
}

/// Call statistics from server
struct CallStatistics: Codable {
    let eventCount: Int?
    let transcriptCount: Int?
    let recordingCount: Int?
    let userMessageCount: Int?
    let assistantMessageCount: Int?

    enum CodingKeys: String, CodingKey {
        case eventCount = "event_count"
        case transcriptCount = "transcript_count"
        case recordingCount = "recording_count"
        case userMessageCount = "user_message_count"
        case assistantMessageCount = "assistant_message_count"
    }
}

/// Call transcripts response from server
struct CallTranscriptsResponse: Codable {
    /// Source of data (database or active)
    let source: String?

    /// Transcript entries
    let transcripts: [ServerTranscriptEntry]
}

/// Wrapper for dynamic JSON values
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            let context = EncodingError.Context(codingPath: container.codingPath, debugDescription: "Unknown type")
            throw EncodingError.invalidValue(value, context)
        }
    }
}
