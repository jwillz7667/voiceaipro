import SwiftUI

/// Custom animated toggle with spring animation and haptic feedback
struct AnimatedToggle: View {
    let title: String
    @Binding var isOn: Bool
    var subtitle: String? = nil
    var icon: String? = nil
    var activeColor: Color = .blue

    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isOn.toggle()
            }
        }) {
            HStack(spacing: 12) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(isOn ? activeColor : .secondary)
                        .frame(width: 28)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Custom toggle track
                ZStack {
                    Capsule()
                        .fill(isOn ? activeColor : Color(.systemGray4))
                        .frame(width: 51, height: 31)

                    Circle()
                        .fill(.white)
                        .frame(width: 27, height: 27)
                        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                        .offset(x: isOn ? 10 : -10)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Toggle row for settings lists
struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var subtitle: String? = nil
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.blue)
                    .frame(width: 28)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16))
                    .foregroundColor(.primary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .onChange(of: isOn) { _, _ in
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }
        }
    }
}

#Preview {
    ZStack {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()

        VStack(spacing: 24) {
            GlassCard {
                VStack(spacing: 16) {
                    AnimatedToggle(
                        title: "Auto-create response",
                        isOn: .constant(true),
                        subtitle: "Automatically respond after speech",
                        icon: "waveform"
                    )

                    Divider()

                    AnimatedToggle(
                        title: "Allow interruption",
                        isOn: .constant(false),
                        icon: "hand.raised.fill"
                    )
                }
            }

            GlassCard {
                VStack(spacing: 16) {
                    ToggleRow(
                        title: "Noise Reduction",
                        isOn: .constant(true),
                        subtitle: "Reduce background noise",
                        icon: "waveform.badge.minus"
                    )
                }
            }
        }
        .padding()
    }
}
