import SwiftUI
import AuthenticationServices

/// Sign in screen with Apple Sign-In
struct SignInView: View {
    @ObservedObject var authManager: AuthManager
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.black, Color(red: 0.1, green: 0.15, blue: 0.2)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // Logo and branding
                VStack(spacing: 24) {
                    Image("StrideLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                    
                    Image("StrideWordmark")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 40)
                    
                    Text("Intelligent Training for Runners")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // Features list
                VStack(alignment: .leading, spacing: 16) {
                    featureRow(icon: "figure.run", text: "Personalized training plans")
                    featureRow(icon: "chart.line.uptrend.xyaxis", text: "Track your progress")
                    featureRow(icon: "brain", text: "AI-powered coaching")
                    featureRow(icon: "icloud", text: "Sync across devices")
                }
                .padding(.horizontal, 32)
                
                Spacer()
                
                // Sign in button
                VStack(spacing: 16) {
                    SignInWithAppleButton(
                        onRequest: { request in
                            request.requestedScopes = [.email, .fullName]
                        },
                        onCompletion: { _ in }
                    )
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 54)
                    .cornerRadius(12)
                    .onTapGesture {
                        authManager.signInWithApple()
                    }
                    
                    // Loading indicator
                    if authManager.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                    
                    // Error message
                    if let error = authManager.authError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Privacy notice
                    Text("By signing in, you agree to our Terms of Service and Privacy Policy")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }
    
    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.cyan)
                .frame(width: 32)
            
            Text(text)
                .font(.body)
                .foregroundColor(.white)
        }
    }
}

#Preview {
    SignInView(authManager: AuthManager.shared)
}
