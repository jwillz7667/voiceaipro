import SwiftUI

/// Compact connection status indicator with animated dot
struct ConnectionStatusCard: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        GlassCard(padding: 12) {
            HStack(spacing: 12) {
                // Animated status dot
                StatusDot(state: appState.connectionState)

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)

                    Text(statusSubtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Optional debug button
                if appState.connectionState == .connected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.green)
                }
            }
        }
    }

    private var statusTitle: String {
        switch appState.connectionState {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting..."
        case .reconnecting:
            return "Reconnecting..."
        case .disconnected:
            return "Disconnected"
        case .error:
            return "Connection Error"
        }
    }

    private var statusSubtitle: String {
        let serverStatus = appState.isServerConnected ? "Server: Online" : "Server: Offline"
        let twilioStatus = appState.isTwilioRegistered ? "Twilio: Ready" : "Twilio: Not Ready"
        return "\(serverStatus) • \(twilioStatus)"
    }
}

/// Animated status dot with pulsing effect
struct StatusDot: View {
    let state: ConnectionState

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            // Outer pulse ring
            if state == .connected || state == .connecting {
                Circle()
                    .fill(color.opacity(0.3))
                    .frame(width: 24, height: 24)
                    .scaleEffect(isPulsing ? 1.3 : 1.0)
                    .opacity(isPulsing ? 0 : 0.5)
            }

            // Main dot
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)

            // Inner highlight
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.5), .clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 6
                    )
                )
                .frame(width: 12, height: 12)
        }
        .onAppear {
            if state == .connected || state == .connecting || state == .reconnecting {
                withAnimation(
                    .easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: false)
                ) {
                    isPulsing = true
                }
            }
        }
        .onChange(of: state) { _, newState in
            isPulsing = false
            if newState == .connected || newState == .connecting || newState == .reconnecting {
                withAnimation(
                    .easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: false)
                ) {
                    isPulsing = true
                }
            }
        }
    }

    private var color: Color {
        switch state {
        case .connected:
            return .green
        case .connecting, .reconnecting:
            return .orange
        case .disconnected:
            return .gray
        case .error:
            return .red
        }
    }
}

#Preview {
    ZStack {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()

        VStack(spacing: 16) {
            ConnectionStatusCard()
                .environmentObject(AppState())
        }
        .padding()
    }
}
