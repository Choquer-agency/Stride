import SwiftUI
import Combine

/// Main tab navigation for the app
struct MainTabView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject var workoutManager: WorkoutManager
    @ObservedObject var storageManager: StorageManager
    @ObservedObject var goalManager: GoalManager
    @ObservedObject var trainingPlanManager: TrainingPlanManager
    
    @State private var selectedTab = 0
    
    enum Tab: Int {
        case run = 0
        case workout = 1
        case plan = 2
        case activity = 3
        case settings = 4
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            RunView(bluetoothManager: bluetoothManager, workoutManager: workoutManager)
                .tabItem {
                    Label("Run", systemImage: "figure.run")
                }
                .tag(0)
            
            // Workout Tab - guided workout experience
            WorkoutGuideView(
                trainingPlanManager: trainingPlanManager,
                workoutManager: workoutManager,
                bluetoothManager: bluetoothManager
            )
                .tabItem {
                    Label("Workout", systemImage: "list.bullet.clipboard")
                }
                .tag(1)
            
            // Plan Tab - shows calendar if plan exists AND summary dismissed, otherwise shows generation view
            Group {
                if trainingPlanManager.hasActivePlan && !trainingPlanManager.showPlanSummary {
                    PlanCalendarView(planManager: trainingPlanManager, storageManager: storageManager)
                } else {
                    PlanGenerationView(
                        planManager: trainingPlanManager,
                        goalManager: goalManager,
                        storageManager: storageManager,
                        selectedTab: $selectedTab
                    )
                }
            }
            .tabItem {
                Label("Plan", systemImage: "calendar")
            }
            .tag(2)
            
            ActivityView(
                storageManager: storageManager,
                goalManager: goalManager,
                trainingPlanManager: trainingPlanManager
            )
                .tabItem {
                    Label("Activity", systemImage: "chart.bar.fill")
                }
                .tag(3)
            
            SettingsView(
                bluetoothManager: bluetoothManager,
                goalManager: goalManager,
                workoutManager: workoutManager,
                storageManager: storageManager
            )
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(4)
        }
    }
}

