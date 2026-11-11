import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @EnvironmentObject private var authService: AuthService

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let buttonWidth = geometry.size.width * 0.78

                VStack(spacing: 0) {
                    Spacer()

                    // Logo — two-tone (red mark, black wordmark)
                    StrideLogoView(height: geometry.size.width * 53.0 / 402.0)

                    Spacer().frame(height: 32)

                    // Title
                    Text("WELCOME TO STRIDE")
                        .font(.barlowCondensed(size: 32, weight: .medium))

                    Spacer().frame(height: 12)

                    // Subtitle
                    Text("Your personal running coach")
                        .font(.inter(size: 14))
                        .foregroundStyle(.secondary)

                    Spacer()

                    appleSignInButton(width: buttonWidth)

                    Spacer().frame(height: 24)

                    // Privacy links
                    HStack(spacing: 4) {
                        Link("Privacy Policy", destination: URL(string: "https://stride.app/privacy")!)
                        Text("·")
                        Link("Terms of Service", destination: URL(string: "https://stride.app/terms")!)
                    }
                    .font(.inter(size: 11))
                    .foregroundStyle(.tertiary)

                    Spacer().frame(height: 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(.systemBackground))
            .overlay {
                if authService.isLoading {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .overlay {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(1.3)
                        }
                }
            }
            .alert("Sign In Error", isPresented: showError) {
                Button("OK") { authService.error = nil }
            } message: {
                Text(authService.error ?? "")
            }
        }
    }

    private var showError: Binding<Bool> {
        Binding(
            get: { authService.error != nil },
            set: { if !$0 { authService.error = nil } }
        )
    }

    // MARK: - Apple Sign In

    @ViewBuilder
    private func appleSignInButton(width: CGFloat) -> some View {
        SignInWithAppleButton(.continue) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            handleAppleSignIn(result)
        }
        .signInWithAppleButtonStyle(.black)
        .frame(width: width, height: 52)
        .clipShape(Capsule())
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8)
            else { return }

            let fullName = [
                credential.fullName?.givenName,
                credential.fullName?.familyName,
            ].compactMap { $0 }.joined(separator: " ")

            Task {
                do {
                    try await authService.signInWithApple(
                        identityToken: identityToken,
                        userIdentifier: credential.user,
                        fullName: fullName.isEmpty ? nil : fullName,
                        email: credential.email
                    )
                } catch {
                    authService.error = error.localizedDescription
                }
            }

        case .failure(let error):
            // User cancelled or other error
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                authService.error = error.localizedDescription
            }
        }
    }

}

#Preview {
    AuthView()
        .environmentObject(AuthService.shared)
}
