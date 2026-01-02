import Foundation
import SwiftData

/// SwiftData model for storing favorite contacts for quick dialing
@Model
final class FavoriteContact {
    /// Unique identifier
    var id: UUID

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
        self.id = UUID()
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

    /// Get SwiftUI Color from color name
    var color: SwiftUI.Color {
        switch colorName {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "red": return .red
        case "pink": return .pink
        case "teal": return .teal
        case "indigo": return .indigo
        default: return .blue
        }
    }

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

// MARK: - SwiftData Schema

extension FavoriteContact {
    /// Schema version for migrations
    static var schemaVersion: Int { 1 }
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

import SwiftUI

/// View for adding/editing a favorite contact
struct EditFavoriteSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var favorite: FavoriteContact?
    var onSave: ((FavoriteContact) -> Void)?

    @State private var name: String = ""
    @State private var phoneNumber: String = ""
    @State private var selectedColor: String = "blue"

    var isEditing: Bool { favorite != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Contact Info") {
                    TextField("Name", text: $name)
                    TextField("Phone Number", text: $phoneNumber)
                        .keyboardType(.phonePad)
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(FavoriteContact.availableColors, id: \.self) { color in
                            Button(action: {
                                selectedColor = color
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                            }) {
                                Circle()
                                    .fill(colorFromName(color))
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: selectedColor == color ? 3 : 0)
                                    )
                                    .overlay(
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(.white)
                                            .opacity(selectedColor == color ? 1 : 0)
                                    )
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle(isEditing ? "Edit Favorite" : "Add Favorite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(name.isEmpty || phoneNumber.isEmpty)
                }
            }
            .onAppear {
                if let favorite = favorite {
                    name = favorite.name
                    phoneNumber = favorite.phoneNumber
                    selectedColor = favorite.colorName
                }
            }
        }
    }

    private func save() {
        if let existing = favorite {
            existing.name = name
            existing.phoneNumber = phoneNumber
            existing.colorName = selectedColor
            onSave?(existing)
        } else {
            let newFavorite = FavoriteContact(
                name: name,
                phoneNumber: phoneNumber,
                colorName: selectedColor
            )
            modelContext.insert(newFavorite)
            onSave?(newFavorite)
        }
        dismiss()
    }

    private func colorFromName(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "red": return .red
        case "pink": return .pink
        case "teal": return .teal
        case "indigo": return .indigo
        default: return .blue
        }
    }
}

#Preview {
    EditFavoriteSheet()
        .modelContainer(for: FavoriteContact.self, inMemory: true)
}
