import Foundation
import SwiftData

/// SwiftData model for storing favorite contacts for quick dialing
@Model
final class FavoriteContact {
    /// Contact name
    var name: String

    /// Phone number (stored as digits only)
    var phoneNumber: String

    /// Optional color identifier for visual distinction
    var colorName: String

    /// Order in the favorites list
    var sortOrder: Int

    /// When this favorite was created
    var createdAt: Date

    /// When this favorite was last called
    var lastCalledAt: Date?

    /// Total number of calls made to this contact
    var callCount: Int

    init(
        name: String,
        phoneNumber: String,
        colorName: String = "blue",
        sortOrder: Int = 0
    ) {
        self.name = name
        self.phoneNumber = phoneNumber.filter { $0.isNumber || $0 == "+" }
        self.colorName = colorName
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.lastCalledAt = nil
        self.callCount = 0
    }

    /// Formatted phone number for display
    var formattedPhoneNumber: String {
        let digits = phoneNumber.filter { $0.isNumber }
        guard !digits.isEmpty else { return phoneNumber }

        if digits.count <= 3 {
            return digits
        } else if digits.count <= 6 {
            let areaCode = String(digits.prefix(3))
            let remaining = String(digits.dropFirst(3))
            return "(\(areaCode)) \(remaining)"
        } else if digits.count <= 10 {
            let areaCode = String(digits.prefix(3))
            let middle = String(digits.dropFirst(3).prefix(3))
            let last = String(digits.dropFirst(6))
            return "(\(areaCode)) \(middle)-\(last)"
        } else {
            let countryCode = String(digits.prefix(1))
            let areaCode = String(digits.dropFirst(1).prefix(3))
            let middle = String(digits.dropFirst(4).prefix(3))
            let last = String(digits.dropFirst(7).prefix(4))
            return "+\(countryCode) (\(areaCode)) \(middle)-\(last)"
        }
    }

    /// Record a call to this contact
    func recordCall() {
        lastCalledAt = Date()
        callCount += 1
    }

    /// Available color options
    static let availableColors = [
        "blue", "green", "orange", "purple", "red", "pink", "teal", "indigo"
    ]

    /// Initials for avatar display
    var initials: String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            let first = components[0].prefix(1)
            let last = components[1].prefix(1)
            return "\(first)\(last)".uppercased()
        } else if let first = components.first {
            return String(first.prefix(2)).uppercased()
        }
        return "?"
    }
}

// MARK: - Sample Data

extension FavoriteContact {
    /// Sample favorites for previews
    static var sampleFavorites: [FavoriteContact] {
        [
            FavoriteContact(name: "Mom", phoneNumber: "5551234567", colorName: "pink", sortOrder: 0),
            FavoriteContact(name: "Work", phoneNumber: "5559876543", colorName: "blue", sortOrder: 1),
            FavoriteContact(name: "John Smith", phoneNumber: "5555550123", colorName: "green", sortOrder: 2),
            FavoriteContact(name: "Sarah", phoneNumber: "5555550456", colorName: "purple", sortOrder: 3),
        ]
    }
}
