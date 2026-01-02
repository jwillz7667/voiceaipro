import SwiftUI

/// Simple audio waveform visualization
struct WaveformView: View {
    var isActive: Bool = true
    var isAISpeaking: Bool = false
    var isUserSpeaking: Bool = false

    @State private var animationPhase: CGFloat = 0

    private let barCount = 20
    private let minHeight: CGFloat = 4
    private let maxHeight: CGFloat = 40

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                WaveformBar(
                    height: barHeight(for: index),
                    color: barColor
                )
            }
        }
        .frame(height: maxHeight)
        .onAppear {
            if isActive {
                startAnimation()
            }
        }
        .onChange(of: isActive) { _, newValue in
            if newValue {
                startAnimation()
            }
        }
        .onChange(of: isAISpeaking) { _, _ in
            // Trigger animation update
        }
        .onChange(of: isUserSpeaking) { _, _ in
            // Trigger animation update
        }
    }

    private func startAnimation() {
        withAnimation(
            .linear(duration: 1.5)
            .repeatForever(autoreverses: false)
        ) {
            animationPhase = 1
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        guard isActive else { return minHeight }

        let phase = animationPhase * 2 * .pi
        let offset = CGFloat(index) / CGFloat(barCount) * 2 * .pi

        // Different wave patterns for AI vs User speaking
        let amplitude: CGFloat
        let frequency: CGFloat

        if isAISpeaking {
            amplitude = 0.8
            frequency = 2
        } else if isUserSpeaking {
            amplitude = 0.6
            frequency = 3
        } else {
            amplitude = 0.2
            frequency = 1
        }

        let wave = sin(phase * frequency + offset) * amplitude
        let normalized = (wave + 1) / 2 // 0 to 1

        return minHeight + normalized * (maxHeight - minHeight)
    }

    private var barColor: Color {
        if isAISpeaking {
            return .blue
        } else if isUserSpeaking {
            return .green
        } else {
            return .secondary.opacity(0.5)
        }
    }
}

/// Individual waveform bar
struct WaveformBar: View {
    var height: CGFloat
    var color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 4, height: height)
            .animation(.spring(response: 0.15, dampingFraction: 0.6), value: height)
    }
}

/// Circular audio level indicator
struct AudioLevelIndicator: View {
    var level: CGFloat // 0 to 1
    var isActive: Bool = true
    var color: Color = .blue

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 4)

            // Active ring
            Circle()
                .trim(from: 0, to: isActive ? level : 0)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: level)

            // Pulse effect when speaking
            if isActive && level > 0.1 {
                Circle()
                    .stroke(color.opacity(0.3), lineWidth: 2)
                    .scaleEffect(1 + level * 0.3)
                    .opacity(1 - level)
            }
        }
    }
}

/// Dual waveform for both parties
struct DualWaveformView: View {
    var isAISpeaking: Bool
    var isUserSpeaking: Bool

    var body: some View {
        VStack(spacing: 16) {
            // AI waveform
            HStack(spacing: 12) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 16))
                    .foregroundColor(.blue)
                    .frame(width: 24)

                WaveformView(
                    isActive: true,
                    isAISpeaking: isAISpeaking,
                    isUserSpeaking: false
                )
                .frame(maxWidth: .infinity)
            }

            // User waveform
            HStack(spacing: 12) {
                Image(systemName: "person.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.green)
                    .frame(width: 24)

                WaveformView(
                    isActive: true,
                    isAISpeaking: false,
                    isUserSpeaking: isUserSpeaking
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .subtleGlass()
    }
}

#Preview {
    ZStack {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()

        VStack(spacing: 30) {
            GlassCard {
                VStack(spacing: 16) {
                    Text("Idle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    WaveformView(isActive: true)
                }
            }

            GlassCard {
                VStack(spacing: 16) {
                    Text("AI Speaking")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    WaveformView(isActive: true, isAISpeaking: true)
                }
            }

            GlassCard {
                VStack(spacing: 16) {
                    Text("User Speaking")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    WaveformView(isActive: true, isUserSpeaking: true)
                }
            }

            DualWaveformView(isAISpeaking: true, isUserSpeaking: false)
        }
        .padding()
    }
}
