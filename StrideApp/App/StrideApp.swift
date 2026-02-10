import SwiftUI
import SwiftData

@main
struct StrideApp: App {
    @StateObject private var bluetoothManager = BluetoothManager()
    let modelContainer: ModelContainer
    
    init() {
        do {
            let schema = Schema([
                TrainingPlan.self,
                Week.self,
                Workout.self
            ])
            
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none  // Disable CloudKit for now to avoid CoreData errors
            )
            
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bluetoothManager)
                .preferredColorScheme(.light)
        }
        .modelContainer(modelContainer)
    }
}
