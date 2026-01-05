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
/// Note: Uses automatic snake_case conversion from NetworkingAPIClient's keyDecodingStrategy
struct PromptDTO: Codable, Identifiable {
    let id: UUID
    let userId: String?
    let name: String
    let instructions: String
    let voice: String?
    let vadConfig: VADConfigDTO?
    let isDefault: Bool
    let createdAt: Date
    let updatedAt: Date

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
/// Note: Server sends camelCase keys (prefixPaddingMs, silenceDurationMs, createResponse)
/// so we don't need CodingKeys - the decoder's convertFromSnakeCase won't apply
/// since the keys are already camelCase
struct VADConfigDTO: Codable {
    let type: String?
    let threshold: Double?
    let prefixPaddingMs: Int?
    let silenceDurationMs: Int?
    let idleTimeoutMs: Int?
    let eagerness: String?
    let createResponse: Bool?
    let interruptResponse: Bool?

    /// Convert to VADConfig model
    func toVADConfig() -> VADConfig {
        switch type?.lowercased() {
        case "server_vad":
            return .serverVAD(
                threshold: threshold ?? 0.5,
                prefixPadding: prefixPaddingMs ?? 300,
                silenceDuration: silenceDurationMs ?? 500
            )
        case "semantic_vad":
            let eagerLevel: SemanticVADParams.Eagerness
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
