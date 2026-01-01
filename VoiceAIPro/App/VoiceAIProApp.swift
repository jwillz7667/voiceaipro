import SwiftUI
import SwiftData

/// Main entry point for the VoiceAI Pro application
@main
struct VoiceAIProApp: App {
    /// App delegate for handling system-level events
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// Global application state
    @StateObject private var appState = AppState()

    /// Dependency injection container
    @StateObject private var container = DIContainer.shared

    /// SwiftData model container for local persistence
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            CallRecord.self,
            SavedPrompt.self,
            EventLogEntry.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(container)
                .modelContainer(sharedModelContainer)
                .onAppear {
                    configureAppearance()
                    container.initialize(modelContainer: sharedModelContainer)
                }
                .preferredColorScheme(.none) // Respect system setting
        }
    }

    /// Configure global appearance settings
    private func configureAppearance() {
        // Navigation bar appearance
        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithOpaqueBackground()
        navigationAppearance.backgroundColor = UIColor.systemBackground
        navigationAppearance.titleTextAttributes = [
            .foregroundColor: UIColor.label,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        navigationAppearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor.label,
            .font: UIFont.systemFont(ofSize: 34, weight: .bold)
        ]

        UINavigationBar.appearance().standardAppearance = navigationAppearance
        UINavigationBar.appearance().compactAppearance = navigationAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance

        // Tab bar appearance
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor.systemBackground

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        // Tint color
        UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = UIColor(Color.voiceAIPrimary)
    }
}
