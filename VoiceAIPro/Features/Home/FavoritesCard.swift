import SwiftUI
import SwiftData

/// Horizontal scrolling favorites card for quick dialing
struct FavoritesCard: View {
    @Query(sort: \FavoriteContact.sortOrder) private var favorites: [FavoriteContact]
    @Environment(\.modelContext) private var modelContext

    var onSelectFavorite: (FavoriteContact) -> Void
    var onCallFavorite: (FavoriteContact) -> Void

    @State private var showingAddSheet = false
    @State private var editingFavorite: FavoriteContact?

    var body: some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Text("Favorites")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    Button(action: {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        showingAddSheet = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Add")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(.blue)
                    }
                }

                // Favorites scroll
                if favorites.isEmpty {
                    emptyState
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(favorites) { favorite in
                                FavoriteButton(favorite: favorite) {
                                    onCallFavorite(favorite)
                                } onLongPress: {
                                    editingFavorite = favorite
                                }
                            }

                            // Add new button
                            AddFavoriteButton {
                                showingAddSheet = true
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            EditFavoriteSheet { newFavorite in
                newFavorite.sortOrder = favorites.count
            }
        }
        .sheet(item: $editingFavorite) { favorite in
            EditFavoriteSheet(favorite: favorite)
        }
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "star")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)
                Text("No favorites yet")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 20)
            Spacer()
        }
    }
}

/// Individual favorite contact button
struct FavoriteButton: View {
    let favorite: FavoriteContact
    let onTap: () -> Void
    var onLongPress: (() -> Void)?

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            onTap()
        }) {
            VStack(spacing: 8) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(favorite.color.opacity(0.2))
                        .frame(width: 56, height: 56)

                    Text(favorite.initials)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(favorite.color)
                }
                .overlay(
                    Circle()
                        .stroke(favorite.color.opacity(0.3), lineWidth: 2)
                )

                // Name
                Text(favorite.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .frame(width: 60)
            }
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(FavoriteButtonStyle(isPressed: $isPressed))
        .contextMenu {
            Button(action: { onTap() }) {
                Label("Call", systemImage: "phone.fill")
            }
            if let onLongPress = onLongPress {
                Button(action: onLongPress) {
                    Label("Edit", systemImage: "pencil")
                }
            }
        }
    }
}

/// Button style for favorites
struct FavoriteButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, newValue in
                isPressed = newValue
            }
    }
}

/// Add new favorite button
struct AddFavoriteButton: View {
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            action()
        }) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(.thinMaterial)
                        .frame(width: 56, height: 56)

                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                )

                Text("Add")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 60)
            }
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(FavoriteButtonStyle(isPressed: $isPressed))
    }
}

// Extension to make FavoriteContact identifiable for sheet binding
extension FavoriteContact: Identifiable {}

#Preview {
    ZStack {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()

        FavoritesCard(
            onSelectFavorite: { _ in },
            onCallFavorite: { _ in }
        )
        .modelContainer(for: FavoriteContact.self, inMemory: true)
        .padding()
    }
}
