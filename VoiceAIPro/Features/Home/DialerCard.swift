import SwiftUI

/// Integrated dialer card with phone input and dial pad
struct DialerCard: View {
    @EnvironmentObject var appState: AppState
    @Binding var phoneNumber: String
    var onCall: () -> Void

    private let dialPadKeys: [[DialKey]] = [
        [.digit("1", ""), .digit("2", "ABC"), .digit("3", "DEF")],
        [.digit("4", "GHI"), .digit("5", "JKL"), .digit("6", "MNO")],
        [.digit("7", "PQRS"), .digit("8", "TUV"), .digit("9", "WXYZ")],
        [.symbol("*"), .digit("0", "+"), .symbol("#")]
    ]

    var body: some View {
        GlassCard(padding: 16) {
            VStack(spacing: 16) {
                // Phone number display
                PhoneDisplayField(
                    phoneNumber: phoneNumber,
                    placeholder: "Enter number"
                ) {
                    deleteLastDigit()
                }

                // Dial pad
                VStack(spacing: 12) {
                    ForEach(dialPadKeys, id: \.self) { row in
                        HStack(spacing: 12) {
                            ForEach(row, id: \.self) { key in
                                DialPadButton(key: key) {
                                    appendDigit(key.mainValue)
                                }
                            }
                        }
                    }
                }

                // Call button
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    onCall()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Call")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(
                                LinearGradient(
                                    colors: isCallEnabled ? [.green, .green.opacity(0.85)] : [.gray, .gray.opacity(0.85)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .shadow(color: isCallEnabled ? .green.opacity(0.4) : .clear, radius: 8, y: 4)
                }
                .disabled(!isCallEnabled)
                .animation(.easeInOut(duration: 0.2), value: isCallEnabled)
            }
        }
    }

    private var isCallEnabled: Bool {
        phoneNumber.filter { $0.isNumber }.count >= 10 && appState.isServerConnected
    }

    private func appendDigit(_ digit: String) {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        phoneNumber += digit
    }

    private func deleteLastDigit() {
        if !phoneNumber.isEmpty {
            phoneNumber.removeLast()
        }
    }
}

/// Dial pad key types
enum DialKey: Hashable {
    case digit(String, String) // Main digit, sub-letters
    case symbol(String)

    var mainValue: String {
        switch self {
        case .digit(let digit, _): return digit
        case .symbol(let symbol): return symbol
        }
    }

    var subValue: String? {
        switch self {
        case .digit(_, let letters): return letters.isEmpty ? nil : letters
        case .symbol: return nil
        }
    }
}

/// Individual dial pad button
struct DialPadButton: View {
    let key: DialKey
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(key.mainValue)
                    .font(.system(size: 28, weight: .regular, design: .rounded))
                    .foregroundColor(.primary)

                if let sub = key.subValue {
                    Text(sub)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .tracking(2)
                }
            }
            .frame(width: 72, height: 72)
            .background(
                Circle()
                    .fill(.thinMaterial)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.03))
                    )
            )
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(DialButtonStyle(isPressed: $isPressed))
    }
}

/// Custom button style for dial buttons
struct DialButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, newValue in
                isPressed = newValue
            }
    }
}

#Preview {
    ZStack {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()

        DialerCard(phoneNumber: .constant("5551234567")) {
            print("Call initiated")
        }
        .environmentObject(AppState())
        .padding()
    }
}
