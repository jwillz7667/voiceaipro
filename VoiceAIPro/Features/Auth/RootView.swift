import SwiftUI

/// Root view - shows main content directly (no auth gate)
struct RootView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DIContainer

    var body: some View {
        ContentView()
    }
}

#Preview {
    RootView()
        .environmentObject(AppState())
        .environmentObject(DIContainer.shared)
}
