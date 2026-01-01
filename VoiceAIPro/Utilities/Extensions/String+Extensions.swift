import Foundation

extension String {
    // MARK: - Phone Number Formatting

    /// Format as US phone number: (123) 456-7890
    var formattedPhoneNumber: String {
        let digits = self.filter { $0.isNumber }

        guard digits.count >= 10 else { return self }

        // Handle 10-digit US numbers
        if digits.count == 10 {
            let areaCode = digits.prefix(3)
            let prefix = digits.dropFirst(3).prefix(3)
            let suffix = digits.suffix(4)
            return "(\(areaCode)) \(prefix)-\(suffix)"
        }

        // Handle 11-digit numbers with country code
        if digits.count == 11 && digits.hasPrefix("1") {
            let cleaned = String(digits.dropFirst())
            let areaCode = cleaned.prefix(3)
            let prefix = cleaned.dropFirst(3).prefix(3)
            let suffix = cleaned.suffix(4)
            return "+1 (\(areaCode)) \(prefix)-\(suffix)"
        }

        // International format - just add + if not present
        if !self.hasPrefix("+") {
            return "+\(self)"
        }

        return self
    }

    /// Strip formatting from phone number, keeping only digits and leading +
    var strippedPhoneNumber: String {
        let hasPlus = self.hasPrefix("+")
        let digits = self.filter { $0.isNumber }
        return hasPlus ? "+\(digits)" : digits
    }

    /// Check if string looks like a valid phone number
    var isValidPhoneNumber: Bool {
        let digits = self.filter { $0.isNumber }
        return digits.count >= 10 && digits.count <= 15
    }

    // MARK: - Truncation

    /// Truncate string with ellipsis
    func truncated(to length: Int, trailing: String = "...") -> String {
        if self.count <= length {
            return self
        }
        return String(self.prefix(length - trailing.count)) + trailing
    }

    /// Truncate to fit within word boundaries
    func truncatedToWords(maxLength: Int) -> String {
        if self.count <= maxLength {
            return self
        }

        let truncated = String(self.prefix(maxLength))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "..."
        }
        return truncated + "..."
    }

    // MARK: - Validation

    /// Check if string is not empty after trimming whitespace
    var isNotBlank: Bool {
        !self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Trimmed version of the string
    var trimmed: String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Check if string contains only digits
    var isNumeric: Bool {
        !self.isEmpty && self.allSatisfy { $0.isNumber }
    }

    // MARK: - JSON

    /// Parse string as JSON dictionary
    var jsonDictionary: [String: Any]? {
        guard let data = self.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Parse string as JSON array
    var jsonArray: [[String: Any]]? {
        guard let data = self.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    }

    // MARK: - Base64

    /// Encode string to base64
    var base64Encoded: String? {
        self.data(using: .utf8)?.base64EncodedString()
    }

    /// Decode base64 string
    var base64Decoded: String? {
        guard let data = Data(base64Encoded: self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - URL

    /// Check if string is a valid URL
    var isValidURL: Bool {
        URL(string: self) != nil
    }

    /// Convert to URL
    var asURL: URL? {
        URL(string: self)
    }

    // MARK: - Localization

    /// Localized string
    var localized: String {
        NSLocalizedString(self, comment: "")
    }

    /// Localized string with format arguments
    func localized(with arguments: CVarArg...) -> String {
        String(format: self.localized, arguments: arguments)
    }

    // MARK: - Case Conversion

    /// Convert to title case
    var titleCased: String {
        self.lowercased().capitalized
    }

    /// Convert to sentence case (first letter capitalized)
    var sentenceCased: String {
        guard let first = self.first else { return self }
        return first.uppercased() + self.dropFirst().lowercased()
    }

    // MARK: - Masking

    /// Mask phone number for privacy (e.g., "***-***-1234")
    var maskedPhoneNumber: String {
        let digits = self.filter { $0.isNumber }
        guard digits.count >= 4 else { return String(repeating: "*", count: self.count) }
        let lastFour = digits.suffix(4)
        return "***-***-\(lastFour)"
    }
}

// MARK: - Optional String

extension Optional where Wrapped == String {
    /// Return empty string if nil
    var orEmpty: String {
        self ?? ""
    }

    /// Check if nil or empty
    var isNilOrEmpty: Bool {
        self?.isEmpty ?? true
    }

    /// Check if has content
    var hasContent: Bool {
        if let value = self {
            return value.isNotBlank
        }
        return false
    }
}
