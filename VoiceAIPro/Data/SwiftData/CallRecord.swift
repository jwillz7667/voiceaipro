import Foundation
import SwiftData

/// SwiftData model for persisted call records
@Model
final class CallRecord {
    /// Unique identifier
    var id: UUID

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

    /// Configuration snapshot as JSON
    var configJson: String?

    /// Recording ID if available
    var recordingId: UUID?

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
        configJson: String? = nil,
        recordingId: UUID? = nil
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
        self.configJson = configJson
        self.recordingId = recordingId
    }

    /// Create from CallSession
    convenience init(from session: CallSession) {
        let configData = try? JSONEncoder().encode(session.config)
        let configJson = configData.flatMap { String(data: $0, encoding: .utf8) }

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
            configJson: configJson
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

    /// Parse config from JSON
    var config: RealtimeConfig? {
        guard let json = configJson,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(RealtimeConfig.self, from: data)
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
            config: config ?? .default
        )
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
}
