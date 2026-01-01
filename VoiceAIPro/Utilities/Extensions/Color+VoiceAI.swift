import SwiftUI

extension Color {
    // MARK: - Brand Colors

    /// Primary brand color - iOS Blue
    static let voiceAIPrimary = Color(hex: "007AFF")

    /// Secondary brand color - Purple
    static let voiceAISecondary = Color(hex: "5856D6")

    /// Success color - Green
    static let voiceAISuccess = Color(hex: "34C759")

    /// Warning color - Orange
    static let voiceAIWarning = Color(hex: "FF9500")

    /// Error color - Red
    static let voiceAIError = Color(hex: "FF3B30")

    // MARK: - Semantic Colors

    /// Background color adapting to light/dark mode
    static let voiceAIBackground = Color(.systemBackground)

    /// Secondary background for cards and surfaces
    static let voiceAISurface = Color(.secondarySystemBackground)

    /// Tertiary background for nested surfaces
    static let voiceAITertiary = Color(.tertiarySystemBackground)

    /// Text colors
    static let voiceAILabel = Color(.label)
    static let voiceAISecondaryLabel = Color(.secondaryLabel)
    static let voiceAITertiaryLabel = Color(.tertiaryLabel)

    // MARK: - Call Status Colors

    /// Color for active/connected call
    static let callActive = Color.voiceAISuccess

    /// Color for ringing call
    static let callRinging = Color.voiceAIWarning

    /// Color for failed call
    static let callFailed = Color.voiceAIError

    /// Color for ended call
    static let callEnded = Color.voiceAISecondaryLabel

    // MARK: - Event Log Colors

    /// Color for incoming events
    static let eventIncoming = Color(hex: "30D158")

    /// Color for outgoing events
    static let eventOutgoing = Color(hex: "64D2FF")

    /// Color for error events
    static let eventError = Color.voiceAIError

    /// Color for session events
    static let eventSession = Color(hex: "BF5AF2")

    /// Color for audio events
    static let eventAudio = Color(hex: "FFD60A")

    // MARK: - Voice Colors

    /// Colors for different voice options
    static func voiceColor(for voice: RealtimeVoice) -> Color {
        switch voice {
        case .marin: return Color(hex: "007AFF")
        case .cedar: return Color(hex: "34C759")
        case .alloy: return Color(hex: "8E8E93")
        case .echo: return Color(hex: "FF9500")
        case .shimmer: return Color(hex: "FFD60A")
        case .ash: return Color(hex: "5856D6")
        case .ballad: return Color(hex: "AF52DE")
        case .coral: return Color(hex: "FF6482")
        case .sage: return Color(hex: "30D158")
        case .verse: return Color(hex: "64D2FF")
        }
    }

    // MARK: - Gradient Colors

    /// Primary gradient for buttons and highlights
    static let voiceAIGradient = LinearGradient(
        colors: [voiceAIPrimary, voiceAISecondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Call button gradient
    static let callButtonGradient = LinearGradient(
        colors: [Color(hex: "34C759"), Color(hex: "30D158")],
        startPoint: .top,
        endPoint: .bottom
    )

    /// End call button gradient
    static let endCallGradient = LinearGradient(
        colors: [Color(hex: "FF3B30"), Color(hex: "FF6961")],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Hex Color Initializer

extension Color {
    /// Initialize a Color from a hex string
    /// - Parameter hex: Hex color string (e.g., "007AFF" or "#007AFF")
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - UIColor Convenience

extension UIColor {
    static let voiceAIPrimary = UIColor(Color.voiceAIPrimary)
    static let voiceAISecondary = UIColor(Color.voiceAISecondary)
    static let voiceAISuccess = UIColor(Color.voiceAISuccess)
    static let voiceAIWarning = UIColor(Color.voiceAIWarning)
    static let voiceAIError = UIColor(Color.voiceAIError)
}
