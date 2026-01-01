import Foundation
import SwiftData
import Combine

/// Central manager for all SwiftData operations
@MainActor
class DataManager: ObservableObject {
    // MARK: - Properties

    /// Model container
    let container: ModelContainer

    /// Main context for UI operations
    var context: ModelContext { container.mainContext }

    /// Cached user settings
    @Published private(set) var settings: UserSettings?

    // MARK: - Initialization

    init() throws {
        let schema = Schema([
            CallRecord.self,
            EventLogEntry.self,
            SavedPrompt.self,
            TranscriptEntry.self,
            RecordingMetadata.self,
            UserSettings.self
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        container = try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Initialize with existing container
    init(container: ModelContainer) {
        self.container = container
    }

    /// Load initial data
    func loadInitialData() {
        settings = UserSettings.getOrCreate(context: context)
    }

    // MARK: - Call Records

    /// Save a call record from session
    func saveCallRecord(_ session: CallSession) throws {
        let record = CallRecord(from: session)
        context.insert(record)
        try context.save()
    }

    /// Update an existing call record
    func updateCallRecord(_ callSid: String, updates: (inout CallRecord) -> Void) throws {
        guard var record = getCallRecord(callSid: callSid) else { return }
        updates(&record)
        try context.save()
    }

    /// Get call records with pagination
    func getCallRecords(limit: Int = 50, offset: Int = 0) -> [CallRecord] {
        var descriptor = CallRecord.recentCalls(limit: limit)
        descriptor.fetchOffset = offset
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Get call record by ID
    func getCallRecord(id: UUID) -> CallRecord? {
        let descriptor = CallRecord.byId(id)
        return try? context.fetch(descriptor).first
    }

    /// Get call record by call SID
    func getCallRecord(callSid: String) -> CallRecord? {
        let descriptor = CallRecord.byCallSid(callSid)
        return try? context.fetch(descriptor).first
    }

    /// Delete call record
    func deleteCallRecord(id: UUID) throws {
        guard let record = getCallRecord(id: id) else { return }
        context.delete(record)
        try context.save()
    }

    // MARK: - Events

    /// Save events for a call
    func saveEvents(_ events: [CallEvent], for callSid: String) throws {
        let callRecord = getCallRecord(callSid: callSid)

        for event in events {
            let entry = EventLogEntry(from: event)
            entry.callRecord = callRecord
            context.insert(entry)
        }

        try context.save()
    }

    /// Save single event
    func saveEvent(_ event: CallEvent) throws {
        let entry = EventLogEntry(from: event)

        if let callSid = event.callId.nilIfEmpty {
            entry.callRecord = getCallRecord(callSid: callSid)
        }

        context.insert(entry)
        try context.save()
    }

    /// Get events for a call
    func getEvents(for callSid: String) -> [EventLogEntry] {
        let descriptor = EventLogEntry.events(forCallSid: callSid)
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Get recent events
    func getRecentEvents(limit: Int = 100) -> [EventLogEntry] {
        let descriptor = EventLogEntry.recentEvents(limit: limit)
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Clear events for a call
    func clearEvents(for callSid: String) throws {
        let events = getEvents(for: callSid)
        for event in events {
            context.delete(event)
        }
        try context.save()
    }

    // MARK: - Transcripts

    /// Save transcript entry
    func saveTranscript(_ entry: TranscriptEntry) throws {
        if let callSid = entry.callSid {
            entry.callRecord = getCallRecord(callSid: callSid)
        }
        context.insert(entry)
        try context.save()
    }

    /// Get transcripts for a call
    func getTranscripts(for callSid: String) -> [TranscriptEntry] {
        let descriptor = TranscriptEntry.transcripts(forCallSid: callSid)
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Prompts

    /// Save a prompt
    func savePrompt(_ prompt: Prompt) throws {
        let savedPrompt = SavedPrompt(from: prompt)
        context.insert(savedPrompt)
        try context.save()
    }

    /// Update a prompt
    func updatePrompt(_ prompt: Prompt) throws {
        guard let existing = getSavedPrompt(id: prompt.id) else {
            try savePrompt(prompt)
            return
        }
        existing.update(from: prompt)
        try context.save()
    }

    /// Delete a prompt
    func deletePrompt(id: UUID) throws {
        guard let prompt = getSavedPrompt(id: id) else { return }
        context.delete(prompt)
        try context.save()
    }

    /// Get all prompts
    func getPrompts() -> [SavedPrompt] {
        let descriptor = SavedPrompt.allPrompts()
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Get saved prompt by ID
    func getSavedPrompt(id: UUID) -> SavedPrompt? {
        var descriptor = FetchDescriptor<SavedPrompt>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Get default prompt
    func getDefaultPrompt() -> SavedPrompt? {
        let descriptor = SavedPrompt.defaultPrompt()
        return try? context.fetch(descriptor).first
    }

    /// Set default prompt
    func setDefaultPrompt(id: UUID) throws {
        // Clear existing default
        let allPrompts = getPrompts()
        for prompt in allPrompts {
            prompt.isDefault = (prompt.id == id)
        }
        try context.save()
    }

    // MARK: - Recordings

    /// Save recording metadata
    func saveRecordingMetadata(_ recording: Recording) throws {
        let metadata = RecordingMetadata(from: recording)
        context.insert(metadata)
        try context.save()
    }

    /// Get recordings with pagination
    func getRecordings(limit: Int = 50, offset: Int = 0) -> [RecordingMetadata] {
        var descriptor = RecordingMetadata.recentRecordings(limit: limit)
        descriptor.fetchOffset = offset
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Get recording by ID
    func getRecording(id: UUID) -> RecordingMetadata? {
        let descriptor = RecordingMetadata.byId(id)
        return try? context.fetch(descriptor).first
    }

    /// Update recording local path
    func updateRecordingLocalPath(id: UUID, path: String) throws {
        guard let recording = getRecording(id: id) else { return }
        recording.setLocalPath(path)
        try context.save()
    }

    /// Delete recording
    func deleteRecording(id: UUID) throws {
        guard let recording = getRecording(id: id) else { return }
        recording.clearLocalDownload()
        context.delete(recording)
        try context.save()
    }

    // MARK: - Settings

    /// Get user settings (creates if needed)
    func getSettings() -> UserSettings {
        if let settings = settings {
            return settings
        }
        let newSettings = UserSettings.getOrCreate(context: context)
        settings = newSettings
        return newSettings
    }

    /// Update settings
    func updateSettings(_ updates: (inout UserSettings) -> Void) throws {
        var currentSettings = getSettings()
        updates(&currentSettings)
        try context.save()
    }

    // MARK: - Sync Operations

    /// Sync call history with server data
    func syncCallHistory(with serverHistory: [CallHistoryItem]) async throws {
        for item in serverHistory {
            if let existing = getCallRecord(id: item.id) {
                // Update existing
                existing.status = item.status
                existing.endedAt = item.endedAt
                existing.durationSeconds = item.durationSeconds
                existing.recordingId = item.recordingId
                existing.markSynced()
            } else {
                // Create new
                let record = CallRecord(from: item)
                context.insert(record)
            }
        }
        try context.save()
    }

    /// Sync prompts with server data
    func syncPrompts(with serverPrompts: [Prompt]) async throws {
        for prompt in serverPrompts {
            if let existing = getSavedPrompt(id: prompt.id) {
                existing.update(from: prompt)
                existing.markSynced(serverId: prompt.id.uuidString)
            } else {
                let saved = SavedPrompt(from: prompt)
                saved.markSynced(serverId: prompt.id.uuidString)
                context.insert(saved)
            }
        }
        try context.save()
    }

    /// Sync recordings with server data
    func syncRecordings(with serverRecordings: [Recording]) async throws {
        for recording in serverRecordings {
            if let existing = getRecording(id: recording.id) {
                existing.markSynced()
            } else {
                let metadata = RecordingMetadata(from: recording)
                context.insert(metadata)
            }
        }
        try context.save()
    }

    // MARK: - Cleanup

    /// Delete old data beyond retention period
    func cleanupOldData(olderThan days: Int = 30) throws {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        // Clean old events (but keep those with callRecord)
        let oldEventsDescriptor = FetchDescriptor<EventLogEntry>(
            predicate: #Predicate { $0.timestamp < cutoffDate && $0.callRecord == nil }
        )
        if let oldEvents = try? context.fetch(oldEventsDescriptor) {
            for event in oldEvents {
                context.delete(event)
            }
        }

        try context.save()
    }
}

// MARK: - String Extension

extension String {
    /// Returns nil if string is empty
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
