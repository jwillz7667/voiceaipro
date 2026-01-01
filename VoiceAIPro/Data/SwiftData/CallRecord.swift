import Foundation
import SwiftData

/// SwiftData model for persisted call records
@Model
final class CallRecord {
    // MARK: - Attributes

    /// Unique identifier
    @Attribute(.unique) var id: UUID

    /// Twilio call SID
    var callSid: String?

    /// Call direction (inbound/outbound)
    var direction: String

    /// Phone number (to or from)
    var phoneNumber: String

    /// Call status
    var status: String

    /// When the call started
    var startedAt: Date

    /// When the call ended
    var endedAt: Date?

    /// Duration in seconds
    var durationSeconds: Int?

    /// Associated prompt ID
    var promptId: UUID?

    /// Prompt name (for display)
    var promptName: String?

    /// Configuration snapshot as Data
    var configSnapshot: Data?

    /// Recording ID if available
    var recordingId: UUID?

    /// When synced with server
    var syncedAt: Date?

    // MARK: - Relationships

    /// Event log entries for this call
    @Relationship(deleteRule: .cascade, inverse: \EventLogEntry.callRecord)
    var events: [EventLogEntry]?

    /// Transcript entries for this call
    @Relationship(deleteRule: .cascade, inverse: \TranscriptEntry.callRecord)
    var transcripts: [TranscriptEntry]?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        callSid: String? = nil,
        direction: String,
        phoneNumber: String,
        status: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        durationSeconds: Int? = nil,
        promptId: UUID? = nil,
        promptName: String? = nil,
        configSnapshot: Data? = nil,
        recordingId: UUID? = nil,
        syncedAt: Date? = nil
    ) {
        self.id = id
        self.callSid = callSid
        self.direction = direction
        self.phoneNumber = phoneNumber
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.promptId = promptId
        self.promptName = promptName
        self.configSnapshot = configSnapshot
        self.recordingId = recordingId
        self.syncedAt = syncedAt
    }

    /// Create from CallSession
    convenience init(from session: CallSession) {
        let configData = try? JSONEncoder().encode(session.config)

        self.init(
            id: session.id,
            callSid: session.callSid,
            direction: session.direction.rawValue,
            phoneNumber: session.phoneNumber,
            status: session.status.rawValue,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            durationSeconds: session.durationSeconds,
            promptId: session.promptId,
            configSnapshot: configData
        )
    }

    /// Create from server history item
    convenience init(from item: CallHistoryItem) {
        self.init(
            id: item.id,
            callSid: item.callSid,
            direction: item.direction,
            phoneNumber: item.phoneNumber,
            status: item.status,
            startedAt: item.startedAt,
            endedAt: item.endedAt,
            durationSeconds: item.durationSeconds,
            promptName: item.promptName,
            recordingId: item.recordingId,
            syncedAt: Date()
        )
    }

    // MARK: - Computed Properties

    /// Parse direction enum
    var callDirection: CallDirection {
        CallDirection(rawValue: direction) ?? .outbound
    }

    /// Parse status enum
    var callStatus: CallStatus {
        CallStatus(rawValue: status) ?? .ended
    }

    /// Formatted phone number
    var formattedPhoneNumber: String {
        phoneNumber.formattedPhoneNumber
    }

    /// Formatted duration
    var formattedDuration: String {
        guard let duration = durationSeconds else { return "--:--" }
        return Date.formatSeconds(duration)
    }

    /// Formatted start time
    var formattedStartTime: String {
        startedAt.smartFormatted
    }

    /// Parse config from snapshot
    var decodedConfig: RealtimeConfig? {
        guard let data = configSnapshot else { return nil }
        return try? JSONDecoder().decode(RealtimeConfig.self, from: data)
    }

    /// Whether this record is synced
    var isSynced: Bool {
        syncedAt != nil
    }

    /// Whether this call has a recording
    var hasRecording: Bool {
        recordingId != nil
    }

    /// Events count
    var eventsCount: Int {
        events?.count ?? 0
    }

    /// Transcript count
    var transcriptCount: Int {
        transcripts?.count ?? 0
    }

    /// Convert to CallSession
    func toCallSession() -> CallSession {
        CallSession(
            id: id,
            callSid: callSid,
            direction: callDirection,
            phoneNumber: phoneNumber,
            status: callStatus,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            promptId: promptId,
            config: decodedConfig ?? .default
        )
    }

    // MARK: - Mutations

    /// Update from session
    func update(from session: CallSession) {
        callSid = session.callSid
        status = session.status.rawValue
        endedAt = session.endedAt
        durationSeconds = session.durationSeconds

        if let configData = try? JSONEncoder().encode(session.config) {
            configSnapshot = configData
        }
    }

    /// Mark as synced
    func markSynced() {
        syncedAt = Date()
    }
}

// MARK: - Fetch Descriptors

extension CallRecord {
    /// Fetch recent calls sorted by start time
    static func recentCalls(limit: Int = 50) -> FetchDescriptor<CallRecord> {
        var descriptor = FetchDescriptor<CallRecord>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return descriptor
    }

    /// Fetch call by ID
    static func byId(_ id: UUID) -> FetchDescriptor<CallRecord> {
        var descriptor = FetchDescriptor<CallRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    /// Fetch call by call SID
    static func byCallSid(_ callSid: String) -> FetchDescriptor<CallRecord> {
        var descriptor = FetchDescriptor<CallRecord>(
            predicate: #Predicate { $0.callSid == callSid }
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    /// Fetch calls by direction
    static func calls(direction: CallDirection) -> FetchDescriptor<CallRecord> {
        let directionValue = direction.rawValue
        return FetchDescriptor<CallRecord>(
            predicate: #Predicate { $0.direction == directionValue },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
    }

    /// Fetch calls with recordings
    static func callsWithRecordings() -> FetchDescriptor<CallRecord> {
        FetchDescriptor<CallRecord>(
            predicate: #Predicate { $0.recordingId != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
    }

    /// Fetch unsynced calls
    static func unsyncedCalls() -> FetchDescriptor<CallRecord> {
        FetchDescriptor<CallRecord>(
            predicate: #Predicate { $0.syncedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
    }

    /// Fetch calls in date range
    static func calls(from startDate: Date, to endDate: Date) -> FetchDescriptor<CallRecord> {
        FetchDescriptor<CallRecord>(
            predicate: #Predicate { $0.startedAt >= startDate && $0.startedAt <= endDate },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
    }
}
