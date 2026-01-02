import SwiftUI

/// Full-screen active call UI overlay
struct ActiveCallView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DIContainer

    @State private var callDuration: TimeInterval = 0
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            // Background
            backgroundGradient
                .ignoresSafeArea()

            // Content
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 60)

                // Phone number
                VStack(spacing: 8) {
                    Text(formattedPhoneNumber)
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)

                    // Call status
                    HStack(spacing: 6) {
                        if appState.callStatus == .initiating || appState.callStatus == .ringing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        Text(appState.callStatus.displayName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }

                Spacer()
                    .frame(height: 40)

                // Audio visualization
                VStack(spacing: 16) {
                    WaveformView(
                        isActive: appState.callStatus == .connected,
                        isAISpeaking: appState.isAISpeaking,
                        isUserSpeaking: appState.isUserSpeaking
                    )
                    .frame(height: 50)

                    // Speaking indicator
                    if appState.callStatus == .connected {
                        Text(speakingStatus)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 40)

                Spacer()
                    .frame(height: 40)

                // Call duration
                if appState.callStatus == .connected {
                    Text(formattedDuration)
                        .font(.system(size: 56, weight: .light, design: .monospaced))
                        .foregroundColor(.white)
                }

                Spacer()

                // Call controls
                CallControlsView(
                    isMuted: $appState.isMuted,
                    isSpeakerEnabled: $appState.isSpeakerEnabled,
                    onEndCall: endCall,
                    onSendDigit: sendDigit
                )

                Spacer()
                    .frame(height: 50)
            }
            .padding(.horizontal, 20)
        }
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
    }

    // MARK: - Computed Properties

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.1, green: 0.1, blue: 0.15),
                Color(red: 0.05, green: 0.05, blue: 0.1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(
            // Subtle animated gradient
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            appState.isAISpeaking ? Color.blue.opacity(0.15) :
                            appState.isUserSpeaking ? Color.green.opacity(0.15) :
                            Color.white.opacity(0.05),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 300
                    )
                )
                .scaleEffect(2)
                .offset(y: -100)
        )
    }

    private var formattedPhoneNumber: String {
        guard let call = appState.currentCall else { return "Unknown" }
        let digits = call.phoneNumber.filter { $0.isNumber }

        if digits.count == 10 {
            let areaCode = String(digits.prefix(3))
            let middle = String(digits.dropFirst(3).prefix(3))
            let last = String(digits.dropFirst(6))
            return "(\(areaCode)) \(middle)-\(last)"
        } else if digits.count == 11 {
            let countryCode = String(digits.prefix(1))
            let areaCode = String(digits.dropFirst(1).prefix(3))
            let middle = String(digits.dropFirst(4).prefix(3))
            let last = String(digits.dropFirst(7).prefix(4))
            return "+\(countryCode) (\(areaCode)) \(middle)-\(last)"
        }
        return call.phoneNumber
    }

    private var formattedDuration: String {
        let minutes = Int(callDuration) / 60
        let seconds = Int(callDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var speakingStatus: String {
        if appState.isAISpeaking {
            return "AI is speaking..."
        } else if appState.isUserSpeaking {
            return "Listening..."
        } else {
            return "Ready"
        }
    }

    // MARK: - Actions

    private func startTimer() {
        callDuration = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if appState.callStatus == .connected {
                callDuration += 1
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func endCall() {
        Task {
            appState.endCall()
        }
    }

    private func sendDigit(_ digit: String) {
        container.callManager.sendDTMF(digit)
    }
}

/// Overlay modifier for showing active call
struct ActiveCallOverlayModifier: ViewModifier {
    @EnvironmentObject var appState: AppState

    func body(content: Content) -> some View {
        ZStack {
            content

            if appState.isCallActive {
                ActiveCallView()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(100)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: appState.isCallActive)
    }
}

extension View {
    /// Show active call overlay when call is in progress
    func activeCallOverlay() -> some View {
        modifier(ActiveCallOverlayModifier())
    }
}

#Preview {
    ActiveCallView()
        .environmentObject({
            let state = AppState()
            state.currentCall = CallSession(
                id: UUID(),
                phoneNumber: "5551234567",
                direction: .outbound,
                status: .connected,
                startedAt: Date(),
                config: .default
            )
            state.callStatus = .connected
            state.isAISpeaking = true
            return state
        }())
        .environmentObject(DIContainer.shared)
}
