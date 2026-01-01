import Foundation
import SwiftData

/// SwiftData model for persisted event log entries
@Model
final class EventLogEntry {
    /// Unique identifier
    var id: UUID

    /// Associated call record ID
    var callRecordId: UUID

    /// Twilio call SID
    var callSid: String

    /// Event timestamp
    var timestamp: Date

    /// Event type
    var eventType: String

    /// Event direction (incoming/outgoing)
    var direction: String

    /// Event payload as JSON
    var payloadJson: String?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        callRecordId: UUID,
        callSid: String,
        timestamp: Date = Date(),
        eventType: String,
        direction: String,
        payloadJson: String? = nil
    ) {
        self.id = id
        self.callRecordId = callRecordId
        self.callSid = callSid
        self.timestamp = timestamp
        self.eventType = eventType
        self.direction = direction
        self.payloadJson = payloadJson
    }

    /// Create from CallEvent
    convenience init(from event: CallEvent, callRecordId: UUID) {
        self.init(
            id: event.id,
            callRecordId: callRecordId,
            callSid: event.callId,
            timestamp: event.timestamp,
            eventType: event.eventType.rawValue,
            direction: event.direction.rawValue,
            payloadJson: event.payload
        )
    }

    // MARK: - Computed Properties

    /// Parse event type
    var type: EventType? {
        EventType(rawValue: eventType)
    }

    /// Parse direction
    var eventDirection: EventDirection {
        EventDirection(rawValue: direction) ?? .incoming
    }

    /// Formatted timestamp
    var formattedTimestamp: String {
        timestamp.preciseTimeFormatted
    }

    /// Parse payload
    var payload: [String: Any]? {
        guard let json = payloadJson,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Convert to CallEvent
    func toCallEvent() -> CallEvent? {
        guard let type = type else { return nil }

        return CallEvent(
            id: id,
            timestamp: timestamp,
            callId: callSid,
            eventType: type,
            direction: eventDirection,
            payload: payloadJson
        )
    }

    /// Display name for the event
    var displayName: String {
        type?.displayName ?? eventType
    }

    /// Icon for the event
    var icon: String {
        type?.icon ?? "questionmark.circle"
    }
}

// MARK: - Fetch Descriptors

extension EventLogEntry {
    /// Fetch events for a specific call
    static func events(forCallSid callSid: String) -> FetchDescriptor<EventLogEntry> {
        FetchDescriptor<EventLogEntry>(
            predicate: #Predicate { $0.callSid == callSid },
            sortBy: [SortDescriptor(\.timestamp)]
        )
    }

    /// Fetch events for a specific call record
    static func events(forCallRecordId recordId: UUID) -> FetchDescriptor<EventLogEntry> {
        FetchDescriptor<EventLogEntry>(
            predicate: #Predicate { $0.callRecordId == recordId },
            sortBy: [SortDescriptor(\.timestamp)]
        )
    }

    /// Fetch recent events across all calls
    static func recentEvents(limit: Int = 100) -> FetchDescriptor<EventLogEntry> {
        var descriptor = FetchDescriptor<EventLogEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return descriptor
    }

    /// Fetch error events
    static func errorEvents() -> FetchDescriptor<EventLogEntry> {
        let errorType = EventType.error.rawValue
        return FetchDescriptor<EventLogEntry>(
            predicate: #Predicate { $0.eventType == errorType },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
    }
}
