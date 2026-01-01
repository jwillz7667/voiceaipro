import Foundation

/// Response for single prompt
struct PromptResponse: Codable {
    /// The prompt
    let prompt: PromptDTO

    /// Success message
    let message: String?
}

/// Response for prompts list
struct PromptsResponse: Codable {
    /// List of prompts
    let prompts: [PromptDTO]

    /// Total count
    let total: Int?
}

/// Prompt data transfer object (matches server format)
struct PromptDTO: Codable, Identifiable {
    let id: UUID
    let name: String
    let instructions: String
    let voice: String?
    let vadConfig: VADConfigDTO?
    let isDefault: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case instructions
        case voice
        case vadConfig = "vad_config"
        case isDefault = "is_default"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Convert to Prompt model
    func toPrompt() -> Prompt {
        let voiceEnum = RealtimeVoice(rawValue: voice ?? "") ?? .marin

        var vadConfigModel: VADConfig? = nil
        if let vad = vadConfig {
            vadConfigModel = vad.toVADConfig()
        }

        return Prompt(
            id: id,
            name: name,
            instructions: instructions,
            voice: voiceEnum,
            vadConfig: vadConfigModel ?? .serverVAD(),
            isDefault: isDefault,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

/// VAD configuration DTO
struct VADConfigDTO: Codable {
    let type: String?
    let threshold: Double?
    let prefixPaddingMs: Int?
    let silenceDurationMs: Int?
    let eagerness: String?

    enum CodingKeys: String, CodingKey {
        case type
        case threshold
        case prefixPaddingMs = "prefix_padding_ms"
        case silenceDurationMs = "silence_duration_ms"
        case eagerness
    }

    /// Convert to VADConfig model
    func toVADConfig() -> VADConfig {
        switch type?.lowercased() {
        case "server_vad":
            return .serverVAD(
                threshold: threshold,
                prefixPaddingMs: prefixPaddingMs,
                silenceDurationMs: silenceDurationMs
            )
        case "semantic_vad":
            let eagerLevel: SemanticVADEagerness
            switch eagerness?.lowercased() {
            case "low": eagerLevel = .low
            case "medium": eagerLevel = .medium
            case "high": eagerLevel = .high
            case "auto": eagerLevel = .auto
            default: eagerLevel = .auto
            }
            return .semanticVAD(eagerness: eagerLevel)
        default:
            return .serverVAD()
        }
    }
}
