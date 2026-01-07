import SwiftUI

/// Login view for user authentication
struct LoginView: View {
    @ObservedObject private var authService = AuthService.shared
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var showRegister = false
    @State private var showForgotPassword = false
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    headerSection

                    // Form
                    formSection

                    // Actions
                    actionsSection

                    // Footer links
                    footerSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
            .sheet(isPresented: $showRegister) {
                RegisterView()
            }
            .sheet(isPresented: $showForgotPassword) {
                ForgotPasswordView()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "phone.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("VoiceAI Pro")
                .font(.system(size: 32, weight: .bold))

            Text("Sign in to sync your data across devices")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Form

    private var formSection: some View {
        VStack(spacing: 16) {
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
                .textContentType(.password)
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

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 16) {
            // Login button
            Button {
                Task {
                    await login()
                }
            } label: {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Sign In")
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

            // Forgot password
            Button {
                showForgotPassword = true
            } label: {
                Text("Forgot password?")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 16) {
            HStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 1)
                Text("or")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 1)
            }

            Button {
                showRegister = true
            } label: {
                HStack {
                    Text("Don't have an account?")
                        .foregroundColor(.secondary)
                    Text("Sign up")
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
                .font(.subheadline)
            }
        }
        .padding(.top, 16)
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty &&
        email.contains("@")
    }

    // MARK: - Actions

    private func login() async {
        isLoading = true
        errorMessage = nil

        do {
            try await authService.login(email: email, password: password)
            // Success - the app should automatically navigate away
        } catch let error as AuthServiceError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "An unexpected error occurred"
        }

        isLoading = false
    }
}

#Preview {
    LoginView()
}
