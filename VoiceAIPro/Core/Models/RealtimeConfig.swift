import Foundation

// MARK: - RealtimeConfig

/// Configuration for OpenAI Realtime API session
/// Matches the server-side configuration schema for seamless transmission
struct RealtimeConfig: Codable, Equatable {
    var model: RealtimeModel = .gptRealtime
    var voice: RealtimeVoice = .marin
    var voiceSpeed: Double = 1.0
    var vadConfig: VADConfig = .serverVAD()
    var noiseReduction: NoiseReduction? = nil
    var transcriptionModel: TranscriptionModel = .gpt4oTranscribe
    var temperature: Double = 0.8
    var maxOutputTokens: Int = 4096
    var instructions: String = ""

    /// Default configuration for new calls
    static let `default` = RealtimeConfig()

    /// Convert to JSON dictionary for API transmission
    func toAPIParams() -> [String: Any] {
        var params: [String: Any] = [
            "model": model.rawValue,
            "voice": voice.rawValue,
            "voiceSpeed": voiceSpeed,
            "transcriptionModel": transcriptionModel.rawValue,
            "temperature": temperature,
            "maxOutputTokens": maxOutputTokens,
            "instructions": instructions
        ]

        if let noiseReduction = noiseReduction {
            params["noiseReduction"] = noiseReduction.rawValue
        }

        // Add VAD config
        switch vadConfig {
        case .serverVAD(let serverParams):
            params["vadType"] = "server_vad"
            params["vadConfig"] = [
                "threshold": serverParams.threshold,
                "prefixPaddingMs": serverParams.prefixPaddingMs,
                "silenceDurationMs": serverParams.silenceDurationMs,
                "idleTimeoutMs": serverParams.idleTimeoutMs as Any,
                "createResponse": serverParams.createResponse,
                "interruptResponse": serverParams.interruptResponse
            ]
        case .semanticVAD(let semanticParams):
            params["vadType"] = "semantic_vad"
            params["vadConfig"] = [
                "eagerness": semanticParams.eagerness.rawValue,
                "createResponse": semanticParams.createResponse,
                "interruptResponse": semanticParams.interruptResponse
            ]
        case .disabled:
            params["vadType"] = "disabled"
        }

        return params
    }
}

// MARK: - RealtimeModel

/// Available OpenAI Realtime models
enum RealtimeModel: String, Codable, CaseIterable, Identifiable {
    case gptRealtime = "gpt-realtime"
    case gptRealtimeMini = "gpt-realtime-mini"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gptRealtime: return "GPT Realtime"
        case .gptRealtimeMini: return "GPT Realtime Mini"
        }
    }

    var description: String {
        switch self {
        case .gptRealtime: return "Full-featured model for complex conversations"
        case .gptRealtimeMini: return "Faster, lighter model for simple tasks"
        }
    }
}

// MARK: - RealtimeVoice

/// Available voices for OpenAI Realtime API
enum RealtimeVoice: String, Codable, CaseIterable, Identifiable {
    case marin
    case cedar
    case alloy
    case echo
    case shimmer
    case ash
    case ballad
    case coral
    case sage
    case verse

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }

    var description: String {
        switch self {
        case .marin: return "Professional, clear - Best for assistants"
        case .cedar: return "Natural, conversational - Best for support"
        case .alloy: return "Neutral, balanced - General purpose"
        case .echo: return "Warm, engaging - Customer service"
        case .shimmer: return "Energetic, expressive - Sales"
        case .ash: return "Confident, assertive - Business"
        case .ballad: return "Storytelling tone - Narratives"
        case .coral: return "Friendly, approachable - Casual"
        case .sage: return "Wise, thoughtful - Advisory"
        case .verse: return "Dramatic, expressive - Creative"
        }
    }

    /// Recommended voices for AI assistant use
    static let recommended: [RealtimeVoice] = [.marin, .cedar]
}

// MARK: - VADConfig

/// Voice Activity Detection configuration
enum VADConfig: Codable, Equatable {
    case serverVAD(ServerVADParams)
    case semanticVAD(SemanticVADParams)
    case disabled

    /// Create server VAD with default parameters
    static func serverVAD(
        threshold: Double = 0.5,
        prefixPadding: Int = 300,
        silenceDuration: Int = 500,
        idleTimeout: Int? = nil,
        createResponse: Bool = true,
        interruptResponse: Bool = true
    ) -> VADConfig {
        .serverVAD(ServerVADParams(
            threshold: threshold,
            prefixPaddingMs: prefixPadding,
            silenceDurationMs: silenceDuration,
            idleTimeoutMs: idleTimeout,
            createResponse: createResponse,
            interruptResponse: interruptResponse
        ))
    }

    /// Create semantic VAD with default parameters
    static func semanticVAD(
        eagerness: SemanticVADParams.Eagerness = .auto,
        createResponse: Bool = true,
        interruptResponse: Bool = true
    ) -> VADConfig {
        .semanticVAD(SemanticVADParams(
            eagerness: eagerness,
            createResponse: createResponse,
            interruptResponse: interruptResponse
        ))
    }

    var displayName: String {
        switch self {
        case .serverVAD: return "Server VAD"
        case .semanticVAD: return "Semantic VAD"
        case .disabled: return "Manual (Disabled)"
        }
    }

    var description: String {
        switch self {
        case .serverVAD: return "Audio-level voice detection"
        case .semanticVAD: return "Context-aware speech detection"
        case .disabled: return "Manual push-to-talk mode"
        }
    }

    /// Convert to API-compatible dictionary format
    func toAPIParams() -> [String: Any] {
        switch self {
        case .serverVAD(let params):
            var result: [String: Any] = [
                "type": "server_vad",
                "threshold": params.threshold,
                "prefix_padding_ms": params.prefixPaddingMs,
                "silence_duration_ms": params.silenceDurationMs,
                "create_response": params.createResponse,
                "interrupt_response": params.interruptResponse
            ]
            if let idleTimeout = params.idleTimeoutMs {
                result["idle_timeout_ms"] = idleTimeout
            }
            return result
        case .semanticVAD(let params):
            return [
                "type": "semantic_vad",
                "eagerness": params.eagerness.rawValue,
                "create_response": params.createResponse,
                "interrupt_response": params.interruptResponse
            ]
        case .disabled:
            return ["type": "disabled"]
        }
    }
}

// MARK: - ServerVADParams

/// Parameters for server-side Voice Activity Detection
struct ServerVADParams: Codable, Equatable {
    var threshold: Double
    var prefixPaddingMs: Int
    var silenceDurationMs: Int
    var idleTimeoutMs: Int?
    var createResponse: Bool
    var interruptResponse: Bool

    static let `default` = ServerVADParams(
        threshold: 0.5,
        prefixPaddingMs: 300,
        silenceDurationMs: 500,
        idleTimeoutMs: nil,
        createResponse: true,
        interruptResponse: true
    )
}

// MARK: - SemanticVADParams

/// Parameters for semantic Voice Activity Detection
struct SemanticVADParams: Codable, Equatable {
    var eagerness: Eagerness
    var createResponse: Bool
    var interruptResponse: Bool

    enum Eagerness: String, Codable, CaseIterable, Identifiable {
        case low
        case medium
        case high
        case auto

        var id: String { rawValue }

        var displayName: String {
            rawValue.capitalized
        }

        var description: String {
            switch self {
            case .low: return "Wait longer for user to finish"
            case .medium: return "Balanced response timing"
            case .high: return "Respond quickly to pauses"
            case .auto: return "Automatically adjust timing"
            }
        }
    }

    static let `default` = SemanticVADParams(
        eagerness: .auto,
        createResponse: true,
        interruptResponse: true
    )
}

// MARK: - NoiseReduction

/// Noise reduction modes for audio input
enum NoiseReduction: String, Codable, CaseIterable, Identifiable {
    case nearField = "near_field"
    case farField = "far_field"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nearField: return "Near Field"
        case .farField: return "Far Field"
        }
    }

    var description: String {
        switch self {
        case .nearField: return "Optimized for close microphone (phone calls)"
        case .farField: return "Optimized for distant microphone (speakerphone)"
        }
    }
}

// MARK: - TranscriptionModel

/// Available transcription models for user speech
enum TranscriptionModel: String, Codable, CaseIterable, Identifiable {
    case gpt4oTranscribe = "gpt-4o-transcribe"
    case gpt4oMiniTranscribe = "gpt-4o-mini-transcribe"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gpt4oTranscribe: return "GPT-4o Transcribe"
        case .gpt4oMiniTranscribe: return "GPT-4o Mini Transcribe"
        }
    }

    var description: String {
        switch self {
        case .gpt4oTranscribe: return "Best accuracy, context-aware (Recommended)"
        case .gpt4oMiniTranscribe: return "Faster, more cost-effective"
        }
    }
}
