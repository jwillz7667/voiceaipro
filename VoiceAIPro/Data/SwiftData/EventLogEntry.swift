import Foundation
import SwiftData

/// SwiftData model for persisted event log entries
@Model
final class EventLogEntry {
    // MARK: - Attributes

    /// Unique identifier
    @Attribute(.unique) var id: UUID

    /// Event type
    var eventType: String

    /// Event direction (incoming/outgoing)
    var direction: String

    /// Event payload as JSON data
    var payloadData: Data?

    /// Event timestamp
    var timestamp: Date

    /// Call SID for reference
    var callSid: String?

    // MARK: - Relationships

    /// Parent call record
    var callRecord: CallRecord?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        eventType: String,
        direction: String,
        payloadData: Data? = nil,
        timestamp: Date = Date(),
        callSid: String? = nil
    ) {
        self.id = id
        self.eventType = eventType
        self.direction = direction
        self.payloadData = payloadData
        self.timestamp = timestamp
        self.callSid = callSid
    }

    /// Create from CallEvent
    convenience init(from event: CallEvent) {
        var payloadData: Data? = nil
        if let payload = event.payload {
            payloadData = payload.data(using: .utf8)
        }

        self.init(
            id: event.id,
            eventType: event.eventType.rawValue,
            direction: event.direction.rawValue,
            payloadData: payloadData,
            timestamp: event.timestamp,
            callSid: event.callId
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

    /// Parse payload as dictionary
    var decodedPayload: [String: Any]? {
        guard let data = payloadData else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Payload as string
    var payloadString: String? {
        guard let data = payloadData else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Convert to CallEvent
    func toCallEvent() -> CallEvent? {
        guard let type = type else { return nil }

        return CallEvent(
            id: id,
            timestamp: timestamp,
            callId: callSid ?? "",
            eventType: type,
            direction: eventDirection,
            payload: payloadString
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

    /// Category of the event
    var category: EventCategory {
        type?.category ?? .other
    }
}

// MARK: - Fetch Descriptors

extension EventLogEntry {
    /// Fetch events for a specific call SID
    static func events(forCallSid callSid: String) -> FetchDescriptor<EventLogEntry> {
        FetchDescriptor<EventLogEntry>(
            predicate: #Predicate { $0.callSid == callSid },
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

    /// Fetch events by type
    static func events(ofType type: EventType) -> FetchDescriptor<EventLogEntry> {
        let typeValue = type.rawValue
        return FetchDescriptor<EventLogEntry>(
            predicate: #Predicate { $0.eventType == typeValue },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
    }

    /// Fetch events in date range
    static func events(from startDate: Date, to endDate: Date) -> FetchDescriptor<EventLogEntry> {
        FetchDescriptor<EventLogEntry>(
            predicate: #Predicate { $0.timestamp >= startDate && $0.timestamp <= endDate },
            sortBy: [SortDescriptor(\.timestamp)]
        )
    }
}
