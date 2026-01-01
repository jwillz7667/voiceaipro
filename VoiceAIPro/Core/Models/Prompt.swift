import Foundation

// MARK: - Prompt

/// A saved prompt template for AI conversations
/// Contains instructions, voice settings, and VAD configuration
struct Prompt: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var instructions: String
    var voice: RealtimeVoice
    var vadConfig: VADConfig
    var isDefault: Bool
    var createdAt: Date
    var updatedAt: Date

    /// Create a new prompt with default values
    init(
        id: UUID = UUID(),
        name: String,
        instructions: String,
        voice: RealtimeVoice = .marin,
        vadConfig: VADConfig = .serverVAD(),
        isDefault: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.instructions = instructions
        self.voice = voice
        self.vadConfig = vadConfig
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Create a config from this prompt
    func toConfig() -> RealtimeConfig {
        var config = RealtimeConfig.default
        config.voice = voice
        config.vadConfig = vadConfig
        config.instructions = instructions
        return config
    }

    /// Duplicate this prompt with a new name
    func duplicate(name: String? = nil) -> Prompt {
        Prompt(
            id: UUID(),
            name: name ?? "\(self.name) (Copy)",
            instructions: instructions,
            voice: voice,
            vadConfig: vadConfig,
            isDefault: false,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    /// Formatted creation date
    var formattedCreatedAt: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }

    /// Formatted update date
    var formattedUpdatedAt: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: updatedAt)
    }

    /// Short preview of instructions
    var instructionsPreview: String {
        if instructions.count <= 100 {
            return instructions
        }
        return String(instructions.prefix(100)) + "..."
    }
}

// MARK: - Sample Prompts

extension Prompt {
    /// Built-in sample prompts for quick start
    static let samples: [Prompt] = [
        Prompt(
            name: "General Assistant",
            instructions: """
            You are a helpful AI assistant conducting a phone conversation.
            Be natural, conversational, and helpful. Keep responses concise as this is a voice call.
            Listen carefully and ask clarifying questions when needed.
            Respond in a friendly, professional manner.
            """,
            voice: .marin,
            isDefault: true
        ),
        Prompt(
            name: "Customer Support",
            instructions: """
            You are a customer support representative for a technology company.
            Be empathetic, patient, and solution-oriented.
            Ask clarifying questions to understand the customer's issue.
            Provide clear, step-by-step instructions when helping with technical problems.
            If you cannot resolve an issue, offer to escalate to a human representative.
            """,
            voice: .cedar
        ),
        Prompt(
            name: "Appointment Scheduler",
            instructions: """
            You are an appointment scheduling assistant.
            Help callers schedule, reschedule, or cancel appointments.
            Confirm all details including date, time, and purpose.
            Be efficient but friendly.
            Always repeat back the confirmed appointment details.
            """,
            voice: .coral
        ),
        Prompt(
            name: "Sales Representative",
            instructions: """
            You are a sales representative for a software company.
            Be enthusiastic and knowledgeable about your products.
            Ask questions to understand the prospect's needs.
            Highlight relevant features and benefits.
            Be respectful of the caller's time and interest level.
            """,
            voice: .shimmer
        ),
        Prompt(
            name: "Survey Conductor",
            instructions: """
            You are conducting a customer satisfaction survey.
            Be polite and respect the caller's time.
            Ask each question clearly and wait for a complete response.
            Thank them for their feedback.
            Keep the survey focused and efficient.
            """,
            voice: .alloy
        )
    ]
}
