import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject private var authService: AuthService

    var body: some View {
        Group {
            switch authService.authState {
            case .unknown:
                // Brief splash while we check the keychain + validate the cached user.
                Color(.systemBackground).ignoresSafeArea()
            case .signedOut:
                AuthView()
            case .needsProfile(let user):
                ProfileSetupView(user: user)
            case .signedIn:
                MainTabView()
            }
        }
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
