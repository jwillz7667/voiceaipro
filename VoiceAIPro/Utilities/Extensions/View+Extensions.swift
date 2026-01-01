import SwiftUI

// MARK: - View Extensions

extension View {
    // MARK: - Card Styling

    /// Apply card-style background with shadow
    func cardStyle(
        backgroundColor: Color = .voiceAISurface,
        cornerRadius: CGFloat = 12,
        shadowRadius: CGFloat = 4
    ) -> some View {
        self
            .background(backgroundColor)
            .cornerRadius(cornerRadius)
            .shadow(color: .black.opacity(0.1), radius: shadowRadius, x: 0, y: 2)
    }

    /// Apply glass morphism effect
    func glassStyle(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(.ultraThinMaterial)
            .cornerRadius(cornerRadius)
    }

    // MARK: - Button Styling

    /// Style as primary action button
    func primaryButtonStyle() -> some View {
        self
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.voiceAIPrimary)
            .cornerRadius(12)
    }

    /// Style as secondary action button
    func secondaryButtonStyle() -> some View {
        self
            .font(.headline)
            .foregroundColor(.voiceAIPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.voiceAIPrimary.opacity(0.1))
            .cornerRadius(12)
    }

    /// Style as call button
    func callButtonStyle(isActive: Bool = false) -> some View {
        self
            .font(.system(size: 24, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 72, height: 72)
            .background(
                isActive
                    ? AnyShapeStyle(Color.voiceAIError)
                    : AnyShapeStyle(Color.callButtonGradient)
            )
            .clipShape(Circle())
            .shadow(color: (isActive ? Color.voiceAIError : Color.voiceAISuccess).opacity(0.4),
                    radius: 8, x: 0, y: 4)
    }

    // MARK: - Conditional Modifiers

    /// Apply modifier conditionally
    @ViewBuilder
    func `if`<Content: View>(
        _ condition: Bool,
        transform: (Self) -> Content
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    /// Apply modifier if value is non-nil
    @ViewBuilder
    func ifLet<Value, Content: View>(
        _ value: Value?,
        transform: (Self, Value) -> Content
    ) -> some View {
        if let value = value {
            transform(self, value)
        } else {
            self
        }
    }

    // MARK: - Layout Helpers

    /// Embed in horizontal scroll view
    func horizontalScroll(showsIndicators: Bool = false) -> some View {
        ScrollView(.horizontal, showsIndicators: showsIndicators) {
            self
        }
    }

    /// Embed in vertical scroll view
    func verticalScroll(showsIndicators: Bool = true) -> some View {
        ScrollView(.vertical, showsIndicators: showsIndicators) {
            self
        }
    }

    /// Add standard content padding
    func contentPadding() -> some View {
        self.padding(.horizontal, 16)
    }

    // MARK: - Loading State

    /// Overlay with loading indicator
    func loading(_ isLoading: Bool) -> some View {
        self.overlay {
            if isLoading {
                ZStack {
                    Color.black.opacity(0.3)
                    ProgressView()
                        .scaleEffect(1.5)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
                .ignoresSafeArea()
            }
        }
    }

    /// Show placeholder when empty
    func placeholder<Placeholder: View>(
        when isEmpty: Bool,
        @ViewBuilder placeholder: () -> Placeholder
    ) -> some View {
        ZStack {
            if isEmpty {
                placeholder()
            } else {
                self
            }
        }
    }

    // MARK: - Animation Helpers

    /// Apply standard spring animation
    func springAnimation() -> some View {
        self.animation(.spring(response: 0.3, dampingFraction: 0.7), value: UUID())
    }

    /// Animate on appear
    func animateOnAppear(_ animation: Animation = .easeInOut(duration: 0.3)) -> some View {
        self.transition(.opacity.combined(with: .scale(scale: 0.95)))
            .animation(animation, value: UUID())
    }

    // MARK: - Accessibility

    /// Add accessibility identifier for UI testing
    func testID(_ identifier: String) -> some View {
        self.accessibilityIdentifier(identifier)
    }
}

// MARK: - Shake Effect

extension View {
    /// Apply shake animation (for error states)
    func shake(times: Int = 3) -> some View {
        self.modifier(ShakeModifier(times: times))
    }
}

struct ShakeModifier: ViewModifier {
    @State private var shake = false
    let times: Int

    func body(content: Content) -> some View {
        content
            .offset(x: shake ? -10 : 0)
            .animation(
                Animation.default.repeatCount(times, autoreverses: true).speed(6),
                value: shake
            )
            .onAppear {
                shake = true
            }
    }
}

// MARK: - Keyboard Toolbar

extension View {
    /// Add done button to keyboard toolbar
    func keyboardDoneButton() -> some View {
        self.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
            }
        }
    }
}
