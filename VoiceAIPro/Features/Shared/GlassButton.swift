import SwiftUI

/// Subtle glass button with haptic feedback and press animation
struct GlassButton: View {
    let title: String
    var icon: String? = nil
    var style: ButtonStyle = .primary
    var isEnabled: Bool = true
    let action: () -> Void

    enum ButtonStyle {
        case primary
        case secondary
        case destructive
        case call

        var foregroundColor: Color {
            switch self {
            case .primary: return .white
            case .secondary: return .primary
            case .destructive: return .white
            case .call: return .white
            }
        }

        var backgroundColor: Color {
            switch self {
            case .primary: return .blue
            case .secondary: return .clear
            case .destructive: return .red
            case .call: return .green
            }
        }

        var gradient: LinearGradient? {
            switch self {
            case .call:
                return LinearGradient(
                    colors: [Color.green, Color.green.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            case .destructive:
                return LinearGradient(
                    colors: [Color.red, Color.red.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            default:
                return nil
            }
        }
    }

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            guard isEnabled else { return }
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            action()
        }) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(style.foregroundColor.opacity(isEnabled ? 1 : 0.5))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Group {
                    if let gradient = style.gradient {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(gradient)
                            .opacity(isEnabled ? 1 : 0.5)
                    } else if style == .secondary {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.thinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(style.backgroundColor.opacity(isEnabled ? 1 : 0.5))
                    }
                }
            )
            .shadow(color: style.backgroundColor.opacity(0.3), radius: isPressed ? 2 : 4, y: isPressed ? 1 : 2)
        }
        .buttonStyle(PressableButtonStyle(isPressed: $isPressed))
        .disabled(!isEnabled)
    }
}

/// Custom button style for press animation
struct PressableButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, newValue in
                isPressed = newValue
            }
    }
}

/// Circular glass button for call controls
struct CircleGlassButton: View {
    let icon: String
    var iconSize: CGFloat = 24
    var size: CGFloat = 60
    var isActive: Bool = false
    var activeColor: Color = .blue
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(foregroundColor)
                .frame(width: size, height: size)
                .background(backgroundView)
                .clipShape(Circle())
                .shadow(color: shadowColor, radius: isPressed ? 2 : 6, y: isPressed ? 1 : 3)
        }
        .buttonStyle(PressableButtonStyle(isPressed: $isPressed))
    }

    private var foregroundColor: Color {
        if isDestructive { return .white }
        if isActive { return activeColor }
        return .primary
    }

    private var shadowColor: Color {
        if isDestructive { return .red.opacity(0.4) }
        if isActive { return activeColor.opacity(0.3) }
        return .black.opacity(0.1)
    }

    @ViewBuilder
    private var backgroundView: some View {
        if isDestructive {
            LinearGradient(
                colors: [.red, .red.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else if isActive {
            Circle()
                .fill(activeColor.opacity(0.2))
                .overlay(Circle().stroke(activeColor.opacity(0.3), lineWidth: 1))
        } else {
            Circle()
                .fill(.thinMaterial)
                .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
        }
    }
}

#Preview {
    ZStack {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()

        VStack(spacing: 20) {
            GlassButton(title: "Primary", icon: "phone.fill", style: .primary) {}
            GlassButton(title: "Secondary", icon: "gear", style: .secondary) {}
            GlassButton(title: "Call Now", icon: "phone.fill", style: .call) {}
            GlassButton(title: "End Call", icon: "phone.down.fill", style: .destructive) {}
            GlassButton(title: "Disabled", style: .primary, isEnabled: false) {}

            HStack(spacing: 30) {
                CircleGlassButton(icon: "mic.slash.fill", isActive: true, activeColor: .red) {}
                CircleGlassButton(icon: "speaker.wave.2.fill") {}
                CircleGlassButton(icon: "phone.down.fill", size: 70, isDestructive: true) {}
            }
        }
        .padding()
    }
}
