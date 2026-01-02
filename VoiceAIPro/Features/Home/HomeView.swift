import SwiftUI
import SwiftData

/// Main home tab with integrated dialer, favorites, and recent activity
struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DIContainer
    @Environment(\.modelContext) private var modelContext

    @State private var phoneNumber: String = ""
    @State private var showEventLog = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Connection status
                    ConnectionStatusCard()

                    // Dialer
                    DialerCard(phoneNumber: $phoneNumber) {
                        initiateCall()
                    }

                    // Favorites
                    FavoritesCard(
                        onSelectFavorite: { favorite in
                            phoneNumber = favorite.phoneNumber
                        },
                        onCallFavorite: { favorite in
                            phoneNumber = favorite.phoneNumber
                            favorite.recordCall()
                            initiateCall()
                        }
                    )

                    // Recent activity
                    RecentActivityCard(
                        onSelectCall: { call in
                            phoneNumber = call.phoneNumber
                        },
                        onCallNumber: { number in
                            phoneNumber = number
                            initiateCall()
                        }
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 100) // Space for tab bar
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("VoiceAI Pro")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        showEventLog = true
                    }) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.blue)
                    }
                }
            }
            .sheet(isPresented: $showEventLog) {
                EventLogSheet()
            }
        }
    }

    private func initiateCall() {
        guard !phoneNumber.isEmpty else { return }

        let cleanNumber = phoneNumber.filter { $0.isNumber || $0 == "+" }
        guard cleanNumber.count >= 10 else { return }

        Task {
            do {
                try await container.callManager.startCall(to: cleanNumber)
                // Clear phone number after successful call initiation
                phoneNumber = ""
            } catch {
                appState.showError("Failed to start call: \(error.localizedDescription)")
            }
        }
    }
}

/// Event log sheet for debugging
struct EventLogSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if appState.events.isEmpty {
                    ContentUnavailableView(
                        "No Events",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Events will appear here during calls")
                    )
                } else {
                    ForEach(appState.events.reversed()) { event in
                        EventLogRow(event: event)
                    }
                }
            }
            .navigationTitle("Event Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        appState.clearEvents()
                    }) {
                        Text("Clear")
                            .foregroundColor(.red)
                    }
                    .disabled(appState.events.isEmpty)
                }
            }
        }
    }
}

/// Individual event log row
struct EventLogRow: View {
    let event: CallEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Event type icon
            Image(systemName: event.eventType.icon)
                .font(.system(size: 14))
                .foregroundColor(eventColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.eventType.displayName)
                        .font(.system(size: 14, weight: .medium))

                    Spacer()

                    Text(formattedTime)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                if let description = event.eventDescription {
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: event.timestamp)
    }

    private var eventColor: Color {
        switch event.eventType.category {
        case .session: return .gray
        case .audio: return .blue
        case .transcript: return .green
        case .response: return .purple
        case .error: return .red
        case .call: return .orange
        case .other: return .secondary
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(AppState())
        .environmentObject(DIContainer.shared)
        .modelContainer(for: [CallRecord.self, FavoriteContact.self], inMemory: true)
}
