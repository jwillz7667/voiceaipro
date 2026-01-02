import SwiftUI
import SwiftData

/// Main content view with 5-tab navigation
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DIContainer
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab: Tab = .home

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                HomeView()
                    .tabItem {
                        Label("Home", systemImage: "phone.fill")
                    }
                    .tag(Tab.home)

                CallHistoryView()
                    .tabItem {
                        Label("History", systemImage: "clock.fill")
                    }
                    .tag(Tab.history)

                TranscriptsView()
                    .tabItem {
                        Label("Transcripts", systemImage: "text.bubble.fill")
                    }
                    .tag(Tab.transcripts)

                RecordingsView()
                    .tabItem {
                        Label("Recordings", systemImage: "waveform.circle.fill")
                    }
                    .tag(Tab.recordings)

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    .tag(Tab.settings)
            }
            .tint(.blue)

            // Active call overlay
            if appState.isCallActive {
                ActiveCallView()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(100)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: appState.isCallActive)
        .alert(item: $appState.activeAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK")) {
                    appState.dismissAlert()
                }
            )
        }
        .onAppear {
            setupInitialState()
        }
    }

    private func setupInitialState() {
        // Configure tab bar appearance for subtle glass look
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemThinMaterial)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

// MARK: - Tab Enum

enum Tab: String, CaseIterable {
    case home
    case history
    case transcripts
    case recordings
    case settings
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(DIContainer.shared)
        .modelContainer(for: [CallRecord.self, SavedPrompt.self, EventLogEntry.self, FavoriteContact.self, TranscriptEntry.self, RecordingMetadata.self], inMemory: true)
}
