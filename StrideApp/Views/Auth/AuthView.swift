import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @EnvironmentObject private var authService: AuthService
    @State private var showEmailAuth = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let buttonWidth = geometry.size.width * 0.78

                VStack(spacing: 0) {
                    Spacer()

                    // Logo
                    StrideLogoView(height: geometry.size.width * 88.0 / 402.0)

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

                    // Sign-in buttons
                    VStack(spacing: 14) {
                        // Apple
                        appleSignInButton(width: buttonWidth)

                        // Google
                        Button(action: handleGoogleSignIn) {
                            HStack(spacing: 10) {
                                Image(systemName: "g.circle.fill")
                                    .font(.title2)
                                Text("Continue with Google")
                                    .font(.inter(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.primary)
                            .frame(width: buttonWidth)
                            .padding(.vertical, 16)
                            .background(Color(.systemBackground))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.strideBorder, lineWidth: 1))
                        }

                        // Email
                        Button(action: { showEmailAuth = true }) {
                            HStack(spacing: 10) {
                                Image(systemName: "envelope.fill")
                                    .font(.title3)
                                Text("Continue with Email")
                                    .font(.inter(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(width: buttonWidth)
                            .padding(.vertical, 16)
                            .background(Color.stridePrimary)
                            .clipShape(Capsule())
                        }
                    }

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
            .navigationDestination(isPresented: $showEmailAuth) {
                EmailAuthView()
            }
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

    // MARK: - Google Sign In

    private func handleGoogleSignIn() {
        // Google Sign-In requires the GoogleSignIn SDK.
        // When the SDK is added via SPM, uncomment below:
        //
        // guard let presentingVC = UIApplication.shared.connectedScenes
        //     .compactMap({ $0 as? UIWindowScene })
        //     .flatMap({ $0.windows })
        //     .first(where: { $0.isKeyWindow })?.rootViewController
        // else { return }
        //
        // GIDSignIn.sharedInstance.signIn(withPresenting: presentingVC) { result, error in
        //     guard let result, error == nil,
        //           let idToken = result.user.idToken?.tokenString
        //     else { return }
        //     Task {
        //         try? await authService.signInWithGoogle(idToken: idToken)
        //     }
        // }

        // Placeholder: show a message that Google Sign-In SDK needs to be added
        authService.error = "Google Sign-In requires adding the GoogleSignIn SDK via SPM"
    }
}

#Preview {
    AuthView()
        .environmentObject(AuthService.shared)
}
