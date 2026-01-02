import SwiftUI
import SwiftData

// MARK: - FavoriteContact UI Extension

extension FavoriteContact {
    /// Get SwiftUI Color from color name
    var color: Color {
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
}

// MARK: - Edit Favorite Sheet

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
