import SwiftUI

/// Call control buttons for active call
struct CallControlsView: View {
    @Binding var isMuted: Bool
    @Binding var isSpeakerEnabled: Bool
    @State private var showKeypad = false

    var onEndCall: () -> Void
    var onSendDigit: ((String) -> Void)?

    var body: some View {
        VStack(spacing: 24) {
            // Top row: Mute, Speaker, Keypad
            HStack(spacing: 40) {
                // Mute button
                CallControlButton(
                    icon: isMuted ? "mic.slash.fill" : "mic.fill",
                    label: isMuted ? "Unmute" : "Mute",
                    isActive: isMuted,
                    activeColor: .red
                ) {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    isMuted.toggle()
                }

                // Speaker button
                CallControlButton(
                    icon: isSpeakerEnabled ? "speaker.wave.3.fill" : "speaker.fill",
                    label: "Speaker",
                    isActive: isSpeakerEnabled,
                    activeColor: .blue
                ) {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    isSpeakerEnabled.toggle()
                }

                // Keypad button
                CallControlButton(
                    icon: "circle.grid.3x3.fill",
                    label: "Keypad",
                    isActive: showKeypad,
                    activeColor: .blue
                ) {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showKeypad.toggle()
                    }
                }
            }

            // Keypad (when visible)
            if showKeypad {
                InCallKeypad { digit in
                    onSendDigit?(digit)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            // End call button
            Button(action: {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)
                onEndCall()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 22, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(width: 72, height: 72)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.red, .red.opacity(0.85)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .shadow(color: .red.opacity(0.4), radius: 10, y: 5)
            }
            .buttonStyle(ScaleButtonStyle())
        }
    }
}

/// Individual call control button
struct CallControlButton: View {
    let icon: String
    let label: String
    var isActive: Bool = false
    var activeColor: Color = .blue
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isActive ? activeColor.opacity(0.2) : .thinMaterial)
                        .frame(width: 64, height: 64)

                    if isActive {
                        Circle()
                            .stroke(activeColor.opacity(0.5), lineWidth: 2)
                            .frame(width: 64, height: 64)
                    }

                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(isActive ? activeColor : .primary)
                }

                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

/// In-call DTMF keypad
struct InCallKeypad: View {
    var onDigit: (String) -> Void

    private let keys: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["*", "0", "#"]
    ]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 16) {
                    ForEach(row, id: \.self) { key in
                        Button(action: {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            onDigit(key)
                        }) {
                            Text(key)
                                .font(.system(size: 24, weight: .medium, design: .rounded))
                                .foregroundColor(.primary)
                                .frame(width: 56, height: 56)
                                .background(
                                    Circle()
                                        .fill(.thinMaterial)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
            }
        }
        .padding()
        .subtleGlass()
    }
}

/// Scale button style for control buttons
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Compact call controls for smaller display
struct CompactCallControls: View {
    @Binding var isMuted: Bool
    @Binding var isSpeakerEnabled: Bool
    var onEndCall: () -> Void

    var body: some View {
        HStack(spacing: 32) {
            CircleGlassButton(
                icon: isMuted ? "mic.slash.fill" : "mic.fill",
                isActive: isMuted,
                activeColor: .red
            ) {
                isMuted.toggle()
            }

            CircleGlassButton(
                icon: "phone.down.fill",
                size: 70,
                isDestructive: true
            ) {
                onEndCall()
            }

            CircleGlassButton(
                icon: isSpeakerEnabled ? "speaker.wave.3.fill" : "speaker.fill",
                isActive: isSpeakerEnabled,
                activeColor: .blue
            ) {
                isSpeakerEnabled.toggle()
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black.opacity(0.9)
            .ignoresSafeArea()

        CallControlsView(
            isMuted: .constant(false),
            isSpeakerEnabled: .constant(true),
            onEndCall: {},
            onSendDigit: { digit in
                print("Digit: \(digit)")
            }
        )
    }
}
