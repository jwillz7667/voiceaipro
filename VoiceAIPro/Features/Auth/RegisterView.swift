import SwiftUI

/// Registration view for new users
struct RegisterView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var authService = AuthService.shared

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var name = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSuccess = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection

                    // Form
                    formSection

                    // Password requirements
                    passwordRequirements

                    // Register button
                    registerButton
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Create Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Account Created", isPresented: $showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Please check your email to verify your account, then sign in.")
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Join VoiceAI Pro")
                .font(.title2)
                .fontWeight(.bold)

            Text("Create an account to sync your data across all your devices")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Form

    private var formSection: some View {
        VStack(spacing: 16) {
            // Name field
            VStack(alignment: .leading, spacing: 8) {
                Text("Name (optional)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                TextField("Your name", text: $name)
                    .textContentType(.name)
                    .autocapitalization(.words)
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
            }

            // Email field
            VStack(alignment: .leading, spacing: 8) {
                Text("Email")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                TextField("you@example.com", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
            }

            // Password field
            VStack(alignment: .leading, spacing: 8) {
                Text("Password")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                HStack {
                    if showPassword {
                        TextField("Password", text: $password)
                    } else {
                        SecureField("Password", text: $password)
                    }

                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                }
                .textContentType(.newPassword)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }

            // Confirm password field
            VStack(alignment: .leading, spacing: 8) {
                Text("Confirm Password")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                SecureField("Confirm password", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
            }

            // Error message
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Password Requirements

    private var passwordRequirements: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Password must contain:")
                .font(.footnote)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                requirementRow("At least 8 characters", met: password.count >= 8)
                requirementRow("One uppercase letter", met: password.contains(where: { $0.isUppercase }))
                requirementRow("One lowercase letter", met: password.contains(where: { $0.isLowercase }))
                requirementRow("One number", met: password.contains(where: { $0.isNumber }))
                requirementRow("Passwords match", met: !confirmPassword.isEmpty && password == confirmPassword)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func requirementRow(_ text: String, met: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .foregroundColor(met ? .green : .gray)
                .font(.footnote)

            Text(text)
                .font(.footnote)
                .foregroundColor(met ? .primary : .secondary)
        }
    }

    // MARK: - Register Button

    private var registerButton: some View {
        Button {
            Task {
                await register()
            }
        } label: {
            HStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Create Account")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isFormValid ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(!isFormValid || isLoading)
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        email.contains("@") &&
        password.count >= 8 &&
        password.contains(where: { $0.isUppercase }) &&
        password.contains(where: { $0.isLowercase }) &&
        password.contains(where: { $0.isNumber }) &&
        password == confirmPassword
    }

    // MARK: - Actions

    private func register() async {
        isLoading = true
        errorMessage = nil

        do {
            let _ = try await authService.register(
                email: email,
                password: password,
                name: name.isEmpty ? nil : name
            )
            showSuccess = true
        } catch let error as AuthServiceError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "An unexpected error occurred"
        }

        isLoading = false
    }
}

#Preview {
    RegisterView()
}
