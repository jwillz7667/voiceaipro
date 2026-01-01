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
            EventLogEntry.self,
            TranscriptEntry.self,
            RecordingMetadata.self,
            UserSettings.self
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
                    initializeServices()
                }
                .preferredColorScheme(.none) // Respect system setting
        }
    }

    /// Initialize all services and connect them
    private func initializeServices() {
        // Initialize DI container with dependencies
        container.initialize(modelContainer: sharedModelContainer, appState: appState)

        // Connect AppDelegate with CallManager for VoIP push handling
        appDelegate.callManager = container.callManager

        // Initialize call manager asynchronously
        Task {
            do {
                try await container.callManager.initialize()
                print("[VoiceAIProApp] Call manager initialized successfully")
            } catch {
                print("[VoiceAIProApp] Failed to initialize call manager: \(error)")
            }
        }

        // Register for push notifications
        setupPushNotificationHandling()
    }

    /// Set up push notification observers
    private func setupPushNotificationHandling() {
        // Handle VoIP token
        NotificationCenter.default.addObserver(
            forName: .voipTokenReceived,
            object: nil,
            queue: .main
        ) { [weak container] notification in
            if let token = notification.userInfo?["token"] as? Data {
                container?.callManager.registerForPushNotifications(deviceToken: token)
            }
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
