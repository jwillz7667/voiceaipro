import Foundation
import SwiftData

/// SwiftData model for persisted prompts
@Model
final class SavedPrompt {
    /// Unique identifier
    var id: UUID

    /// Server ID (if synced)
    var serverId: String?

    /// Prompt name
    var name: String

    /// AI instructions
    var instructions: String

    /// Voice selection
    var voice: String

    /// VAD configuration as JSON
    var vadConfigJson: String?

    /// Whether this is the default prompt
    var isDefault: Bool

    /// Creation timestamp
    var createdAt: Date

    /// Last update timestamp
    var updatedAt: Date

    /// Whether prompt is synced with server
    var isSynced: Bool

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        serverId: String? = nil,
        name: String,
        instructions: String,
        voice: String = "marin",
        vadConfigJson: String? = nil,
        isDefault: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isSynced: Bool = false
    ) {
        self.id = id
        self.serverId = serverId
        self.name = name
        self.instructions = instructions
        self.voice = voice
        self.vadConfigJson = vadConfigJson
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isSynced = isSynced
    }

    /// Create from Prompt model
    convenience init(from prompt: Prompt) {
        let vadData = try? JSONEncoder().encode(prompt.vadConfig)
        let vadJson = vadData.flatMap { String(data: $0, encoding: .utf8) }

        self.init(
            id: prompt.id,
            name: prompt.name,
            instructions: prompt.instructions,
            voice: prompt.voice.rawValue,
            vadConfigJson: vadJson,
            isDefault: prompt.isDefault,
            createdAt: prompt.createdAt,
            updatedAt: prompt.updatedAt
        )
    }

    // MARK: - Computed Properties

    /// Parse voice enum
    var realtimeVoice: RealtimeVoice {
        RealtimeVoice(rawValue: voice) ?? .marin
    }

    /// Parse VAD config from JSON
    var vadConfig: VADConfig? {
        guard let json = vadConfigJson,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(VADConfig.self, from: data)
    }

    /// Instructions preview
    var instructionsPreview: String {
        instructions.truncatedToWords(maxLength: 100)
    }

    /// Formatted creation date
    var formattedCreatedAt: String {
        createdAt.dateFormatted
    }

    /// Formatted update date
    var formattedUpdatedAt: String {
        updatedAt.dateFormatted
    }

    /// Convert to Prompt model
    func toPrompt() -> Prompt {
        Prompt(
            id: id,
            name: name,
            instructions: instructions,
            voice: realtimeVoice,
            vadConfig: vadConfig ?? .serverVAD(),
            isDefault: isDefault,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    // MARK: - Mutations

    /// Update from Prompt model
    func update(from prompt: Prompt) {
        name = prompt.name
        instructions = prompt.instructions
        voice = prompt.voice.rawValue
        isDefault = prompt.isDefault
        updatedAt = Date()

        if let vadData = try? JSONEncoder().encode(prompt.vadConfig) {
            vadConfigJson = String(data: vadData, encoding: .utf8)
        }
    }

    /// Mark as synced
    func markSynced(serverId: String) {
        self.serverId = serverId
        self.isSynced = true
    }
}

// MARK: - Fetch Descriptors

extension SavedPrompt {
    /// Fetch all prompts sorted by name
    static func allPrompts() -> FetchDescriptor<SavedPrompt> {
        FetchDescriptor<SavedPrompt>(
            sortBy: [SortDescriptor(\.name)]
        )
    }

    /// Fetch default prompt
    static func defaultPrompt() -> FetchDescriptor<SavedPrompt> {
        var descriptor = FetchDescriptor<SavedPrompt>(
            predicate: #Predicate { $0.isDefault }
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    /// Fetch prompts needing sync
    static func unsyncedPrompts() -> FetchDescriptor<SavedPrompt> {
        FetchDescriptor<SavedPrompt>(
            predicate: #Predicate { !$0.isSynced }
        )
    }
}
