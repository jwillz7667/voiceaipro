import Foundation
import SwiftData

/// SwiftData model for persisted transcript entries
@Model
final class TranscriptEntry {
    // MARK: - Attributes

    /// Unique identifier
    @Attribute(.unique) var id: UUID

    /// Speaker (user/assistant)
    var speaker: String

    /// Transcript content
    var content: String

    /// Timestamp in milliseconds from call start
    var timestampMs: Int?

    /// When created
    var createdAt: Date

    /// Call SID for reference
    var callSid: String?

    /// Whether this is a final transcript (vs interim)
    var isFinal: Bool

    // MARK: - Relationships

    /// Parent call record
    var callRecord: CallRecord?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        speaker: String,
        content: String,
        timestampMs: Int? = nil,
        createdAt: Date = Date(),
        callSid: String? = nil,
        isFinal: Bool = true
    ) {
        self.id = id
        self.speaker = speaker
        self.content = content
        self.timestampMs = timestampMs
        self.createdAt = createdAt
        self.callSid = callSid
        self.isFinal = isFinal
    }

    /// Create user transcript entry
    static func user(content: String, callSid: String?, timestampMs: Int? = nil) -> TranscriptEntry {
        TranscriptEntry(
            speaker: "user",
            content: content,
            timestampMs: timestampMs,
            callSid: callSid
        )
    }

    /// Create assistant transcript entry
    static func assistant(content: String, callSid: String?, timestampMs: Int? = nil) -> TranscriptEntry {
        TranscriptEntry(
            speaker: "assistant",
            content: content,
            timestampMs: timestampMs,
            callSid: callSid
        )
    }

    // MARK: - Computed Properties

    /// Whether this is from the user
    var isUser: Bool {
        speaker.lowercased() == "user"
    }

    /// Whether this is from the AI assistant
    var isAssistant: Bool {
        speaker.lowercased() == "assistant"
    }

    /// Display name for speaker
    var speakerDisplayName: String {
        isUser ? "You" : "AI"
    }

    /// Icon for speaker
    var speakerIcon: String {
        isUser ? "person.circle" : "sparkles"
    }

    /// Formatted timestamp
    var formattedTimestamp: String {
        if let ms = timestampMs {
            let seconds = ms / 1000
            let minutes = seconds / 60
            let remainingSeconds = seconds % 60
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
        return createdAt.preciseTimeFormatted
    }

    /// Content preview (truncated)
    var contentPreview: String {
        content.truncatedToWords(maxLength: 50)
    }
}

// MARK: - Fetch Descriptors

extension TranscriptEntry {
    /// Fetch transcripts for a specific call SID
    static func transcripts(forCallSid callSid: String) -> FetchDescriptor<TranscriptEntry> {
        FetchDescriptor<TranscriptEntry>(
            predicate: #Predicate { $0.callSid == callSid },
            sortBy: [SortDescriptor(\.createdAt)]
        )
    }

    /// Fetch user transcripts only
    static func userTranscripts(forCallSid callSid: String) -> FetchDescriptor<TranscriptEntry> {
        let speaker = "user"
        return FetchDescriptor<TranscriptEntry>(
            predicate: #Predicate { $0.callSid == callSid && $0.speaker == speaker },
            sortBy: [SortDescriptor(\.createdAt)]
        )
    }

    /// Fetch assistant transcripts only
    static func assistantTranscripts(forCallSid callSid: String) -> FetchDescriptor<TranscriptEntry> {
        let speaker = "assistant"
        return FetchDescriptor<TranscriptEntry>(
            predicate: #Predicate { $0.callSid == callSid && $0.speaker == speaker },
            sortBy: [SortDescriptor(\.createdAt)]
        )
    }

    /// Fetch recent transcripts
    static func recentTranscripts(limit: Int = 50) -> FetchDescriptor<TranscriptEntry> {
        var descriptor = FetchDescriptor<TranscriptEntry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return descriptor
    }
}
