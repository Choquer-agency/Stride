import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject private var authService: AuthService

    var body: some View {
        Group {
            switch authService.authState {
            case .unknown:
                // Splash screen while checking stored token
                VStack {
                    Spacer()
                    StrideLogoView(height: 64)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))

            case .signedOut:
                AuthView()

            case .needsProfile(let user):
                ProfileSetupView(user: user)

            case .signedIn:
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authService.authState.stateKey)
        .task {
            await authService.checkAuthState()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: TrainingPlan.self, inMemory: true)
        .environmentObject(AuthService.shared)
}
