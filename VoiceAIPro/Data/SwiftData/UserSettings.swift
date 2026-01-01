import Foundation
import SwiftData

/// SwiftData model for user settings (local only, not synced)
@Model
final class UserSettings {
    // MARK: - Attributes

    /// Device unique identifier
    var deviceId: UUID

    /// Default configuration as encoded data
    var defaultConfigData: Data?

    /// Whether recording is enabled
    var recordingEnabled: Bool

    /// Whether event logging is enabled
    var eventLoggingEnabled: Bool

    /// Whether haptic feedback is enabled
    var hapticFeedbackEnabled: Bool

    /// Auto-answer enabled
    var autoAnswerEnabled: Bool

    /// Default voice selection
    var defaultVoice: String

    /// Default VAD type
    var defaultVADType: String

    /// Last sync date with server
    var lastSyncDate: Date?

    /// Theme preference (system/light/dark)
    var themePreference: String

    /// Notifications enabled
    var notificationsEnabled: Bool

    /// Show transcript during call
    var showTranscriptDuringCall: Bool

    /// Save transcripts locally
    var saveTranscriptsLocally: Bool

    /// Auto-download recordings
    var autoDownloadRecordings: Bool

    // MARK: - Initialization

    init(
        deviceId: UUID = UUID(),
        defaultConfigData: Data? = nil,
        recordingEnabled: Bool = true,
        eventLoggingEnabled: Bool = true,
        hapticFeedbackEnabled: Bool = true,
        autoAnswerEnabled: Bool = false,
        defaultVoice: String = RealtimeVoice.marin.rawValue,
        defaultVADType: String = "server_vad",
        lastSyncDate: Date? = nil,
        themePreference: String = "system",
        notificationsEnabled: Bool = true,
        showTranscriptDuringCall: Bool = true,
        saveTranscriptsLocally: Bool = true,
        autoDownloadRecordings: Bool = false
    ) {
        self.deviceId = deviceId
        self.defaultConfigData = defaultConfigData
        self.recordingEnabled = recordingEnabled
        self.eventLoggingEnabled = eventLoggingEnabled
        self.hapticFeedbackEnabled = hapticFeedbackEnabled
        self.autoAnswerEnabled = autoAnswerEnabled
        self.defaultVoice = defaultVoice
        self.defaultVADType = defaultVADType
        self.lastSyncDate = lastSyncDate
        self.themePreference = themePreference
        self.notificationsEnabled = notificationsEnabled
        self.showTranscriptDuringCall = showTranscriptDuringCall
        self.saveTranscriptsLocally = saveTranscriptsLocally
        self.autoDownloadRecordings = autoDownloadRecordings
    }

    // MARK: - Static Factory

    /// Get or create settings
    @MainActor
    static func getOrCreate(context: ModelContext) -> UserSettings {
        let descriptor = FetchDescriptor<UserSettings>()

        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        // Load device ID from UserDefaults if exists
        let deviceId: UUID
        if let savedIdString = UserDefaults.standard.string(forKey: Constants.Persistence.deviceIdKey),
           let savedId = UUID(uuidString: savedIdString) {
            deviceId = savedId
        } else {
            deviceId = UUID()
            UserDefaults.standard.set(deviceId.uuidString, forKey: Constants.Persistence.deviceIdKey)
        }

        let settings = UserSettings(deviceId: deviceId)
        context.insert(settings)

        return settings
    }

    // MARK: - Computed Properties

    /// Default realtime config
    var defaultConfig: RealtimeConfig {
        if let data = defaultConfigData,
           let config = try? JSONDecoder().decode(RealtimeConfig.self, from: data) {
            return config
        }
        return .default
    }

    /// Default voice enum
    var defaultRealtimeVoice: RealtimeVoice {
        RealtimeVoice(rawValue: defaultVoice) ?? .marin
    }

    /// Theme preference enum
    var theme: ThemePreference {
        ThemePreference(rawValue: themePreference) ?? .system
    }

    /// Device ID string
    var deviceIdString: String {
        deviceId.uuidString
    }

    // MARK: - Mutations

    /// Set default config
    func setDefaultConfig(_ config: RealtimeConfig) {
        defaultConfigData = try? JSONEncoder().encode(config)
    }

    /// Set default voice
    func setDefaultVoice(_ voice: RealtimeVoice) {
        defaultVoice = voice.rawValue
    }

    /// Set theme
    func setTheme(_ theme: ThemePreference) {
        themePreference = theme.rawValue
    }

    /// Mark as synced
    func markSynced() {
        lastSyncDate = Date()
    }
}

// MARK: - Theme Preference

enum ThemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "gear"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}
