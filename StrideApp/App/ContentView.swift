import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject private var authService: AuthService

    var body: some View {
        // Auth disabled — go straight to main app
        MainTabView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: TrainingPlan.self, inMemory: true)
        .environmentObject(AuthService.shared)
}
