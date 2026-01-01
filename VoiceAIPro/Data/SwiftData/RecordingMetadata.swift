import Foundation
import SwiftData

/// SwiftData model for persisted recording metadata
@Model
final class RecordingMetadata {
    // MARK: - Attributes

    /// Unique identifier
    @Attribute(.unique) var id: UUID

    /// Associated call session ID
    var callSessionId: UUID

    /// Associated call SID
    var callSid: String?

    /// Duration in seconds
    var durationSeconds: Int

    /// File size in bytes
    var fileSizeBytes: Int64

    /// Audio format (e.g., "wav", "mp3")
    var format: String

    /// Sample rate in Hz
    var sampleRate: Int?

    /// Number of channels (1=mono, 2=stereo)
    var channels: Int?

    /// When the recording was created
    var createdAt: Date

    /// Local file path if downloaded
    var localPath: String?

    /// When downloaded locally
    var downloadedAt: Date?

    /// When synced with server
    var syncedAt: Date?

    /// Whether transcript is available
    var hasTranscript: Bool

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        callSessionId: UUID,
        callSid: String? = nil,
        durationSeconds: Int,
        fileSizeBytes: Int64,
        format: String = "wav",
        sampleRate: Int? = nil,
        channels: Int? = nil,
        createdAt: Date = Date(),
        localPath: String? = nil,
        downloadedAt: Date? = nil,
        syncedAt: Date? = nil,
        hasTranscript: Bool = false
    ) {
        self.id = id
        self.callSessionId = callSessionId
        self.callSid = callSid
        self.durationSeconds = durationSeconds
        self.fileSizeBytes = fileSizeBytes
        self.format = format
        self.sampleRate = sampleRate
        self.channels = channels
        self.createdAt = createdAt
        self.localPath = localPath
        self.downloadedAt = downloadedAt
        self.syncedAt = syncedAt
        self.hasTranscript = hasTranscript
    }

    /// Create from server Recording model
    convenience init(from recording: Recording) {
        self.init(
            id: recording.id,
            callSessionId: UUID(), // Will be updated when linked to call
            callSid: recording.callSid,
            durationSeconds: recording.duration,
            fileSizeBytes: Int64(recording.fileSize ?? 0),
            format: recording.format ?? "wav",
            sampleRate: recording.sampleRate,
            channels: recording.channels,
            createdAt: recording.createdAt,
            syncedAt: Date(),
            hasTranscript: recording.hasTranscript ?? false
        )
    }

    // MARK: - Computed Properties

    /// Whether this recording is downloaded locally
    var isDownloaded: Bool {
        localPath != nil
    }

    /// Whether this recording is synced
    var isSynced: Bool {
        syncedAt != nil
    }

    /// Formatted duration
    var formattedDuration: String {
        Date.formatSeconds(durationSeconds)
    }

    /// Formatted file size
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    /// Formatted date
    var formattedDate: String {
        createdAt.smartFormatted
    }

    /// Audio details string
    var audioDetails: String {
        var parts: [String] = []

        parts.append(format.uppercased())

        if let sampleRate = sampleRate {
            parts.append("\(sampleRate / 1000)kHz")
        }

        if let channels = channels {
            parts.append(channels == 1 ? "Mono" : "Stereo")
        }

        return parts.joined(separator: " • ")
    }

    /// Local file URL if downloaded
    var localURL: URL? {
        guard let path = localPath else { return nil }
        return URL(fileURLWithPath: path)
    }

    // MARK: - Mutations

    /// Set local download path
    func setLocalPath(_ path: String) {
        localPath = path
        downloadedAt = Date()
    }

    /// Clear local download
    func clearLocalDownload() {
        // Delete file if exists
        if let url = localURL {
            try? FileManager.default.removeItem(at: url)
        }
        localPath = nil
        downloadedAt = nil
    }

    /// Mark as synced
    func markSynced() {
        syncedAt = Date()
    }
}

// MARK: - Fetch Descriptors

extension RecordingMetadata {
    /// Fetch recent recordings
    static func recentRecordings(limit: Int = 50) -> FetchDescriptor<RecordingMetadata> {
        var descriptor = FetchDescriptor<RecordingMetadata>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return descriptor
    }

    /// Fetch recording by ID
    static func byId(_ id: UUID) -> FetchDescriptor<RecordingMetadata> {
        var descriptor = FetchDescriptor<RecordingMetadata>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    /// Fetch recording for a call
    static func forCall(callSid: String) -> FetchDescriptor<RecordingMetadata> {
        FetchDescriptor<RecordingMetadata>(
            predicate: #Predicate { $0.callSid == callSid },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
    }

    /// Fetch downloaded recordings
    static func downloadedRecordings() -> FetchDescriptor<RecordingMetadata> {
        FetchDescriptor<RecordingMetadata>(
            predicate: #Predicate { $0.localPath != nil },
            sortBy: [SortDescriptor(\.downloadedAt, order: .reverse)]
        )
    }

    /// Fetch unsynced recordings
    static func unsyncedRecordings() -> FetchDescriptor<RecordingMetadata> {
        FetchDescriptor<RecordingMetadata>(
            predicate: #Predicate { $0.syncedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
    }
}
