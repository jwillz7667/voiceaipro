import SwiftUI

/// Root view that handles authentication gating
/// Shows LoginView when not authenticated, ContentView when authenticated
struct RootView: View {
    @ObservedObject private var authService = AuthService.shared
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DIContainer

    var body: some View {
        Group {
            if authService.isAuthenticated {
                ContentView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authService.isAuthenticated)
    }
}

#Preview {
    RootView()
        .environmentObject(AppState())
        .environmentObject(DIContainer.shared)
}
