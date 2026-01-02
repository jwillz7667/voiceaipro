import SwiftUI

/// Glass-styled text field with subtle appearance
struct GlassTextField: View {
    let placeholder: String
    @Binding var text: String
    var icon: String? = nil
    var keyboardType: UIKeyboardType = .default
    var isSecure: Bool = false
    var onSubmit: (() -> Void)? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 24)
            }

            if isSecure {
                SecureField(placeholder, text: $text)
                    .focused($isFocused)
                    .onSubmit { onSubmit?() }
            } else {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
                    .focused($isFocused)
                    .onSubmit { onSubmit?() }
            }

            if !text.isEmpty {
                Button(action: {
                    text = ""
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.thinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.03))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isFocused ? Color.blue.opacity(0.5) : Color.white.opacity(0.1),
                    lineWidth: isFocused ? 1.5 : 0.5
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

/// Large phone number display field (non-editable display)
struct PhoneDisplayField: View {
    let phoneNumber: String
    var placeholder: String = "Enter number"
    var onDelete: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Text(phoneNumber.isEmpty ? placeholder : formattedNumber)
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .foregroundColor(phoneNumber.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .center)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if !phoneNumber.isEmpty, let onDelete = onDelete {
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    onDelete()
                }) {
                    Image(systemName: "delete.left.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.thinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.03))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }

    private var formattedNumber: String {
        formatPhoneNumber(phoneNumber)
    }

    private func formatPhoneNumber(_ number: String) -> String {
        let digits = number.filter { $0.isNumber }
        guard !digits.isEmpty else { return number }

        // Format as +1 (XXX) XXX-XXXX for US numbers
        if digits.count <= 3 {
            return digits
        } else if digits.count <= 6 {
            let areaCode = String(digits.prefix(3))
            let remaining = String(digits.dropFirst(3))
            return "(\(areaCode)) \(remaining)"
        } else if digits.count <= 10 {
            let areaCode = String(digits.prefix(3))
            let middle = String(digits.dropFirst(3).prefix(3))
            let last = String(digits.dropFirst(6))
            return "(\(areaCode)) \(middle)-\(last)"
        } else {
            // International format
            let countryCode = String(digits.prefix(1))
            let areaCode = String(digits.dropFirst(1).prefix(3))
            let middle = String(digits.dropFirst(4).prefix(3))
            let last = String(digits.dropFirst(7).prefix(4))
            return "+\(countryCode) (\(areaCode)) \(middle)-\(last)"
        }
    }
}

#Preview {
    ZStack {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()

        VStack(spacing: 20) {
            GlassTextField(
                placeholder: "Enter phone number",
                text: .constant(""),
                icon: "phone.fill",
                keyboardType: .phonePad
            )

            GlassTextField(
                placeholder: "Search",
                text: .constant("Hello"),
                icon: "magnifyingglass"
            )

            PhoneDisplayField(phoneNumber: "")

            PhoneDisplayField(phoneNumber: "5551234567") {
                print("Delete tapped")
            }

            PhoneDisplayField(phoneNumber: "15551234567") {
                print("Delete tapped")
            }
        }
        .padding()
    }
}
