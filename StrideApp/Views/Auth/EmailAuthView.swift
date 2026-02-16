import SwiftUI

struct EmailAuthView: View {
    @EnvironmentObject private var authService: AuthService
    @State private var isSignUp = true
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case name, email, password
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 24)

            // Mode toggle
            Picker("Mode", selection: $isSignUp) {
                Text("Sign Up").tag(true)
                Text("Sign In").tag(false)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 32)

            Spacer().frame(height: 36)

            // Form
            VStack(spacing: 20) {
                if isSignUp {
                    formField(title: "NAME", text: $name, prompt: "Your name", field: .name)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                }

                formField(title: "EMAIL", text: $email, prompt: "email@example.com", field: .email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                VStack(alignment: .leading, spacing: 8) {
                    Text("PASSWORD")
                        .font(.inter(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(1)

                    SecureField("At least 8 characters", text: $password)
                        .textContentType(isSignUp ? .newPassword : .password)
                        .focused($focusedField, equals: .password)
                        .font(.inter(size: 16))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 32)

            // Error
            if let error = authService.error {
                Text(error)
                    .font(.inter(size: 13))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 16)
            }

            Spacer()

            // Submit button
            Button(action: submit) {
                Group {
                    if authService.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(isSignUp ? "Create Account" : "Sign In")
                            .font(.inter(size: 16, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(isFormValid ? Color.stridePrimary : Color.stridePrimary.opacity(0.4))
                .clipShape(Capsule())
            }
            .disabled(!isFormValid || authService.isLoading)
            .padding(.horizontal, 32)

            Spacer().frame(height: 40)
        }
        .background(Color(.systemBackground))
        .navigationTitle(isSignUp ? "Create Account" : "Sign In")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: isSignUp) { _, _ in
            authService.error = nil
        }
    }

    // MARK: - Form Field

    @ViewBuilder
    private func formField(title: String, text: Binding<String>, prompt: String, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.inter(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(1)

            TextField(prompt, text: text)
                .focused($focusedField, equals: field)
                .font(.inter(size: 16))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        let emailValid = email.contains("@") && email.contains(".")
        let passwordValid = password.count >= 8
        if isSignUp {
            return emailValid && passwordValid && !name.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return emailValid && passwordValid
    }

    // MARK: - Submit

    private func submit() {
        focusedField = nil
        Task {
            do {
                if isSignUp {
                    try await authService.registerEmail(
                        email: email.trimmingCharacters(in: .whitespaces).lowercased(),
                        password: password,
                        name: name.trimmingCharacters(in: .whitespaces)
                    )
                } else {
                    try await authService.loginEmail(
                        email: email.trimmingCharacters(in: .whitespaces).lowercased(),
                        password: password
                    )
                }
            } catch {
                authService.error = error.localizedDescription
            }
        }
    }
}

#Preview {
    NavigationStack {
        EmailAuthView()
            .environmentObject(AuthService.shared)
    }
}
