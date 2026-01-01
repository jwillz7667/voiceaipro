import Foundation

/// Application-wide constants
enum Constants {
    // MARK: - App Info

    enum App {
        static let name = "VoiceAI Pro"
        static let version = "1.0.0"
    }

    // MARK: - API Configuration

    enum API {
        /// Base URL for the REST API server
        /// Update this to your Railway deployment URL
        static let baseURL = "https://your-server.railway.app"

        /// WebSocket URL for real-time communication
        static let wsURL = "wss://your-server.railway.app"

        /// API endpoints
        enum Endpoints {
            static let token = "/api/token"
            static let calls = "/api/calls"
            static let callsOutgoing = "/api/calls/outgoing"
            static let callsEnd = "/api/calls/:id/end"
            static let callsHistory = "/api/calls/history"
            static let recordings = "/api/recordings"
            static let prompts = "/api/prompts"
            static let events = "/api/events"
            static let sessionConfig = "/api/session/config"
        }

        /// WebSocket paths
        enum WebSocket {
            static let iosClient = "/ios-client"
            static let events = "/events"
        }
    }

    // MARK: - Twilio Configuration

    enum Twilio {
        /// These values are fetched from the server at runtime
        /// The server holds the actual credentials

        /// Maximum token TTL in seconds (typically 1 hour)
        static let tokenTTL: TimeInterval = 3600

        /// Token refresh buffer - refresh before expiration
        static let tokenRefreshBuffer: TimeInterval = 300 // 5 minutes
    }

    // MARK: - Audio Configuration

    enum Audio {
        /// OpenAI Realtime API sample rate (fixed)
        static let sampleRate = 24000

        /// Mono audio channel
        static let channelCount = 1

        /// 16-bit PCM audio
        static let bitsPerSample = 16

        /// Bytes per sample (16-bit = 2 bytes)
        static let bytesPerSample = bitsPerSample / 8

        /// Twilio's μ-law sample rate
        static let twilioSampleRate = 8000

        /// Audio buffer size in samples (~100ms at 24kHz)
        static let bufferSampleCount = 2400

        /// Audio buffer duration in seconds
        static let bufferDuration: Double = 0.1
    }

    // MARK: - UI Configuration

    enum UI {
        /// Animation duration for standard transitions
        static let animationDuration: Double = 0.3

        /// Debounce delay for search inputs
        static let searchDebounce: TimeInterval = 0.3

        /// Maximum events to display in event log
        static let maxEventLogItems = 500

        /// Maximum recent calls to show on dashboard
        static let recentCallsCount = 5
    }

    // MARK: - Persistence

    enum Persistence {
        /// UserDefaults key for device ID
        static let deviceIdKey = "VoiceAIPro.deviceId"

        /// UserDefaults key for last used config
        static let lastConfigKey = "VoiceAIPro.lastConfig"

        /// UserDefaults key for event log filter preferences
        static let eventFilterKey = "VoiceAIPro.eventFilter"

        /// Maximum call records to keep locally
        static let maxLocalCallRecords = 1000

        /// Maximum event log entries per call
        static let maxEventsPerCall = 10000
    }

    // MARK: - Timeouts

    enum Timeouts {
        /// API request timeout
        static let apiRequest: TimeInterval = 30

        /// WebSocket connection timeout
        static let webSocketConnect: TimeInterval = 15

        /// WebSocket ping interval
        static let webSocketPing: TimeInterval = 30

        /// OpenAI session ready timeout
        static let sessionReady: TimeInterval = 15

        /// Twilio call connect timeout
        static let callConnect: TimeInterval = 60

        /// Token fetch retry delay
        static let tokenRetryDelay: TimeInterval = 2
    }

    // MARK: - Limits

    enum Limits {
        /// Maximum instructions length
        static let maxInstructionsLength = 4096

        /// Maximum prompt name length
        static let maxPromptNameLength = 255

        /// Maximum phone number length
        static let maxPhoneNumberLength = 20

        /// Maximum reconnection attempts
        static let maxReconnectAttempts = 3
    }
}

// MARK: - Feature Flags

enum FeatureFlags {
    /// Enable debug event logging
    static let debugEventLog = true

    /// Enable audio recording
    static let recordingEnabled = true

    /// Show high-volume events in event log
    static let showHighVolumeEvents = false

    /// Enable semantic VAD option
    static let semanticVADEnabled = true
}

// MARK: - Error Codes

enum ErrorCode: String {
    case networkError = "E001"
    case authenticationFailed = "E002"
    case callFailed = "E003"
    case webSocketError = "E004"
    case audioSessionError = "E005"
    case permissionDenied = "E006"
    case invalidConfiguration = "E007"
    case serverError = "E008"
    case tokenExpired = "E009"
    case callKitError = "E010"

    var description: String {
        switch self {
        case .networkError: return "Network connection error"
        case .authenticationFailed: return "Authentication failed"
        case .callFailed: return "Call connection failed"
        case .webSocketError: return "WebSocket connection error"
        case .audioSessionError: return "Audio session error"
        case .permissionDenied: return "Permission denied"
        case .invalidConfiguration: return "Invalid configuration"
        case .serverError: return "Server error"
        case .tokenExpired: return "Token expired"
        case .callKitError: return "CallKit error"
        }
    }
}
