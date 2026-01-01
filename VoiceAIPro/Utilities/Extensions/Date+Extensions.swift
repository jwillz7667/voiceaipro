import Foundation

extension Date {
    // MARK: - Relative Formatting

    /// Format as relative time (e.g., "2 hours ago", "Yesterday")
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    /// Format as relative time with full words
    var relativeFormattedFull: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    // MARK: - Standard Formats

    /// Format as time only (e.g., "2:30 PM")
    var timeFormatted: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    /// Format as date only (e.g., "Dec 31, 2025")
    var dateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: self)
    }

    /// Format as full date and time
    var dateTimeFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    /// Format with precise time including milliseconds
    var preciseTimeFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: self)
    }

    // MARK: - Smart Formatting

    /// Smart format based on how recent the date is
    /// - Today: "2:30 PM"
    /// - Yesterday: "Yesterday, 2:30 PM"
    /// - This week: "Monday, 2:30 PM"
    /// - Earlier: "Dec 31, 2:30 PM"
    var smartFormatted: String {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(self) {
            return "Today, \(timeFormatted)"
        } else if calendar.isDateInYesterday(self) {
            return "Yesterday, \(timeFormatted)"
        } else if calendar.isDate(self, equalTo: now, toGranularity: .weekOfYear) {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, h:mm a"
            return formatter.string(from: self)
        } else if calendar.isDate(self, equalTo: now, toGranularity: .year) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, h:mm a"
            return formatter.string(from: self)
        } else {
            return dateTimeFormatted
        }
    }

    // MARK: - ISO8601

    /// Format as ISO8601 string for API communication
    var iso8601: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }

    /// Create date from ISO8601 string
    static func fromISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }

        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    // MARK: - Duration Formatting

    /// Format duration from this date to now
    var durationFromNow: String {
        let interval = Date().timeIntervalSince(self)
        return Self.formatDuration(interval)
    }

    /// Format a time interval as duration string
    static func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    /// Format seconds as duration
    static func formatSeconds(_ seconds: Int) -> String {
        formatDuration(TimeInterval(seconds))
    }

    // MARK: - Comparisons

    /// Check if date is within the last N minutes
    func isWithinLastMinutes(_ minutes: Int) -> Bool {
        let cutoff = Date().addingTimeInterval(-Double(minutes * 60))
        return self > cutoff
    }

    /// Check if date is within the last N hours
    func isWithinLastHours(_ hours: Int) -> Bool {
        let cutoff = Date().addingTimeInterval(-Double(hours * 3600))
        return self > cutoff
    }

    /// Check if date is within the last N days
    func isWithinLastDays(_ days: Int) -> Bool {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -days, to: Date())!
        return self > cutoff
    }
}

// MARK: - TimeInterval Extensions

extension TimeInterval {
    /// Format as readable duration (e.g., "2h 30m")
    var readableDuration: String {
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        } else if minutes > 0 {
            return seconds > 0 ? "\(minutes)m \(seconds)s" : "\(minutes)m"
        } else {
            return "\(seconds)s"
        }
    }

    /// Format as MM:SS or HH:MM:SS
    var callDuration: String {
        Date.formatDuration(self)
    }
}
