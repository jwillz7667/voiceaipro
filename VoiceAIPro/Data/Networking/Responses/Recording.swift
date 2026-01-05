import Foundation

/// Recording model
/// Note: Uses automatic snake_case conversion from NetworkingAPIClient's keyDecodingStrategy
struct Recording: Codable, Identifiable {
    /// Unique identifier
    let id: UUID

    /// Associated call SID
    let callSid: String

    /// Recording duration in seconds
    let duration: Int

    /// File size in bytes
    let fileSize: Int?

    /// Audio format
    let format: String?

    /// Sample rate
    let sampleRate: Int?

    /// Channels (1 = mono, 2 = stereo)
    let channels: Int?

    /// Creation timestamp
    let createdAt: Date

    /// Whether recording has transcript
    let hasTranscript: Bool?

    // Note: CodingKeys removed - NetworkingAPIClient uses .convertFromSnakeCase which
    // automatically converts JSON keys like "call_sid" to Swift property "callSid"

    /// Formatted duration
    var formattedDuration: String {
        Date.formatSeconds(duration)
    }

    /// Formatted file size
    var formattedFileSize: String {
        guard let size = fileSize else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    /// Formatted date
    var formattedDate: String {
        createdAt.smartFormatted
    }

    /// Audio details string
    var audioDetails: String {
        var parts: [String] = []

        if let format = format?.uppercased() {
            parts.append(format)
        }

        if let sampleRate = sampleRate {
            parts.append("\(sampleRate / 1000)kHz")
        }

        if let channels = channels {
            parts.append(channels == 1 ? "Mono" : "Stereo")
        }

        return parts.joined(separator: " • ")
    }
}

/// Response containing recordings list
struct RecordingsResponse: Codable {
    /// List of recordings
    let recordings: [Recording]

    /// Total count
    let total: Int?

    /// Current offset
    let offset: Int?

    /// Limit used
    let limit: Int?
}
