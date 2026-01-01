import Foundation

// MARK: - CallSession

/// Represents an active or completed phone call session
struct CallSession: Identifiable, Codable, Equatable {
    let id: UUID
    var callSid: String?
    var direction: CallDirection
    var phoneNumber: String
    var status: CallStatus
    var startedAt: Date
    var endedAt: Date?
    var durationSeconds: Int?
    var promptId: UUID?
    var config: RealtimeConfig

    /// Create a new outbound call session
    static func outbound(
        to phoneNumber: String,
        promptId: UUID? = nil,
        config: RealtimeConfig = .default
    ) -> CallSession {
        CallSession(
            id: UUID(),
            callSid: nil,
            direction: .outbound,
            phoneNumber: phoneNumber,
            status: .initiating,
            startedAt: Date(),
            endedAt: nil,
            durationSeconds: nil,
            promptId: promptId,
            config: config
        )
    }

    /// Create a new inbound call session
    static func inbound(
        from phoneNumber: String,
        callSid: String,
        config: RealtimeConfig = .default
    ) -> CallSession {
        CallSession(
            id: UUID(),
            callSid: callSid,
            direction: .inbound,
            phoneNumber: phoneNumber,
            status: .ringing,
            startedAt: Date(),
            endedAt: nil,
            durationSeconds: nil,
            promptId: nil,
            config: config
        )
    }

    /// Formatted phone number for display
    var formattedPhoneNumber: String {
        phoneNumber.formattedPhoneNumber
    }

    /// Duration formatted as "MM:SS" or "HH:MM:SS"
    var formattedDuration: String {
        guard let duration = durationSeconds else {
            if status == .connected {
                let elapsed = Int(Date().timeIntervalSince(startedAt))
                return formatDuration(elapsed)
            }
            return "--:--"
        }
        return formatDuration(duration)
    }

    /// Check if call is currently active
    var isActive: Bool {
        switch status {
        case .initiating, .ringing, .connected:
            return true
        case .ended, .failed:
            return false
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

// MARK: - CallDirection

/// Direction of a phone call
enum CallDirection: String, Codable, CaseIterable {
    case inbound
    case outbound

    var displayName: String {
        switch self {
        case .inbound: return "Incoming"
        case .outbound: return "Outgoing"
        }
    }

    var icon: String {
        switch self {
        case .inbound: return "phone.arrow.down.left"
        case .outbound: return "phone.arrow.up.right"
        }
    }
}

// MARK: - CallStatus

/// Status of a phone call
enum CallStatus: String, Codable, CaseIterable {
    case initiating
    case ringing
    case connected
    case ended
    case failed

    var displayName: String {
        switch self {
        case .initiating: return "Connecting..."
        case .ringing: return "Ringing"
        case .connected: return "Connected"
        case .ended: return "Ended"
        case .failed: return "Failed"
        }
    }

    var icon: String {
        switch self {
        case .initiating: return "phone.connection"
        case .ringing: return "phone.badge.waveform"
        case .connected: return "phone.fill"
        case .ended: return "phone.down"
        case .failed: return "phone.down.circle"
        }
    }

    /// Whether this status represents an active call
    var isActive: Bool {
        switch self {
        case .initiating, .ringing, .connected:
            return true
        case .ended, .failed:
            return false
        }
    }
}

// MARK: - String Extension for Phone Formatting

private extension String {
    var formattedPhoneNumber: String {
        // Remove all non-numeric characters
        let digits = self.filter { $0.isNumber }

        guard digits.count >= 10 else { return self }

        // Handle US phone numbers
        if digits.count == 10 {
            let areaCode = digits.prefix(3)
            let prefix = digits.dropFirst(3).prefix(3)
            let suffix = digits.suffix(4)
            return "(\(areaCode)) \(prefix)-\(suffix)"
        } else if digits.count == 11 && digits.hasPrefix("1") {
            let cleaned = String(digits.dropFirst())
            let areaCode = cleaned.prefix(3)
            let prefix = cleaned.dropFirst(3).prefix(3)
            let suffix = cleaned.suffix(4)
            return "+1 (\(areaCode)) \(prefix)-\(suffix)"
        }

        // Return as-is for international numbers
        return self
    }
}
