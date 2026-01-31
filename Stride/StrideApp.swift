import SwiftUI
import BackgroundTasks
import Security

@main
struct StrideApp: App {
    @ObservedObject private var authManager = AuthManager.shared
    @StateObject private var storageManager = StorageManager()
    @StateObject private var bluetoothManager = BluetoothManager()
    @StateObject private var workoutManager: WorkoutManager
    @StateObject private var goalManager: GoalManager
    @StateObject private var trainingPlanManager: TrainingPlanManager
    @StateObject private var adaptationManager: WeeklyAdaptationManager
    @Environment(\.scenePhase) private var scenePhase
    
    // Background task identifier
    private static let weeklyAdaptationTaskIdentifier = "com.stride.weeklyAdaptation"
    
    init() {
        let storage = StorageManager()
        let workout = WorkoutManager(storageManager: storage)
        let goal = GoalManager(storageManager: storage)
        
        // Configure AI Training Plan Generator (ChatGPT as primary coach)
        let aiGenerator: AITrainingPlanGenerator? = {
            // Use SecureKeyManager to get API key from multiple sources
            if let apiKey = SecureKeyManager.getOpenAIAPIKey() {
                print("✅ AI Coach enabled with ChatGPT API")
                return AITrainingPlanGenerator(apiKey: apiKey)
            } else {
                print("⚠️ AI Coach disabled - No API key found. Training plans require AI.")
                print("   Configure your API key in Settings or add OPENAI_API_KEY to Xcode scheme")
                return nil
            }
        }()
        
        let planManager = TrainingPlanManager(storageManager: storage, aiGenerator: aiGenerator)
        let adaptation = WeeklyAdaptationManager(storageManager: storage, trainingPlanManager: planManager)
        _storageManager = StateObject(wrappedValue: storage)
        _workoutManager = StateObject(wrappedValue: workout)
        _goalManager = StateObject(wrappedValue: goal)
        _trainingPlanManager = StateObject(wrappedValue: planManager)
        _adaptationManager = StateObject(wrappedValue: adaptation)
        
        // Register background tasks
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.weeklyAdaptationTaskIdentifier,
            using: nil
        ) { task in
            Self.handleWeeklyAdaptation(task: task as! BGAppRefreshTask, adaptationManager: adaptation)
        }
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated {
                    MainTabView(
                        bluetoothManager: bluetoothManager,
                        workoutManager: workoutManager,
                        storageManager: storageManager,
                        goalManager: goalManager,
                        trainingPlanManager: trainingPlanManager
                    )
                } else {
                    SignInView(authManager: authManager)
                }
            }
            .onAppear {
                // Connect workout manager to bluetooth manager
                bluetoothManager.setWorkoutManager(workoutManager)
                
                // One-time migration: Clear old plans generated with failed AI (v1.0 migration)
                performOneTimeMigrationIfNeeded()
                
                // Validate goal storage on startup
                let validation = storageManager.validateGoalStorage()
                if validation.isValid {
                    print("✅ \(validation.details)")
                } else {
                    print("⚠️ \(validation.details)")
                }
                
                // Schedule initial background task for weekly adaptation
                scheduleWeeklyAdaptationTask()
                
                // Check if adaptation should run on app launch (fallback for missed Sunday)
                Task {
                    await adaptationManager.checkAndRunIfNeeded()
                }
                
                // Generate test data if no workouts exist (for demo purposes)
                #if DEBUG
                if storageManager.workouts.isEmpty {
                    TestDataGenerator.generateTestWorkouts(storageManager: storageManager)
                }
                #endif
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                handleScenePhaseChange(from: oldPhase, to: newPhase)
            }
        }
    }
    
    // MARK: - Scene Phase Handling
    
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            print("📱 App became active")
            
            // Reload goal to ensure fresh state
            goalManager.loadActiveGoal()
            
            // App returned to foreground
            if workoutManager.isRecording {
                workoutManager.enterForeground()
                print("Workout resumed in foreground")
            }
            
            // Check if adaptation should run (fallback mechanism)
            Task {
                await adaptationManager.checkAndRunIfNeeded()
            }
            
        case .inactive:
            print("📱 App became inactive")
            // Transitioning between states (brief)
            
        case .background:
            print("📱 App entered background")
            // App went to background
            if workoutManager.isRecording {
                workoutManager.enterBackground()
                print("Workout continues in background")
            }
            
            // Re-schedule background task when entering background
            scheduleWeeklyAdaptationTask()
            
        @unknown default:
            print("📱 Unknown scene phase")
        }
    }
    
    // MARK: - Background Task Scheduling
    
    private func scheduleWeeklyAdaptationTask() {
        let request = BGAppRefreshTaskRequest(identifier: Self.weeklyAdaptationTaskIdentifier)
        
        // Schedule for next Sunday at 6 AM
        let calendar = Calendar.current
        var components = DateComponents()
        components.weekday = 1 // Sunday
        components.hour = 6
        components.minute = 0
        
        if let nextSunday = calendar.nextDate(
            after: Date(),
            matching: components,
            matchingPolicy: .nextTime
        ) {
            request.earliestBeginDate = nextSunday
            
            do {
                try BGTaskScheduler.shared.submit(request)
                print("📅 Scheduled weekly adaptation for \(nextSunday)")
            } catch {
                print("❌ Failed to schedule background task: \(error)")
            }
        }
    }
    
    private static func handleWeeklyAdaptation(task: BGAppRefreshTask, adaptationManager: WeeklyAdaptationManager) {
        print("📅 Background weekly adaptation triggered")
        
        // Schedule next occurrence
        let calendar = Calendar.current
        var components = DateComponents()
        components.weekday = 1 // Sunday
        components.hour = 6
        
        if let nextSunday = calendar.nextDate(
            after: Date(),
            matching: components,
            matchingPolicy: .nextTime
        ) {
            let request = BGAppRefreshTaskRequest(identifier: weeklyAdaptationTaskIdentifier)
            request.earliestBeginDate = nextSunday
            try? BGTaskScheduler.shared.submit(request)
        }
        
        // Run adaptation asynchronously
        Task {
            do {
                await try adaptationManager.runWeeklyAdaptation()
                task.setTaskCompleted(success: true)
                print("✅ Background adaptation completed successfully")
            } catch {
                print("❌ Background adaptation failed: \(error)")
                task.setTaskCompleted(success: false)
            }
        }
    }
    
    // MARK: - One-Time Migration
    
    /// Perform one-time migration to clear old plans and switch to OpenAI
    private func performOneTimeMigrationIfNeeded() {
        let migrationKey = "migration_v1_openai_switch_completed"
        let defaults = UserDefaults.standard
        
        guard !defaults.bool(forKey: migrationKey) else {
            // Migration already completed
            return
        }
        
        print("🔄 Performing one-time migration: Clearing old training plans...")
        
        // Delete any existing training plan (generated with failing API)
        do {
            try storageManager.deleteTrainingPlan()
            print("✅ Cleared old training plan")
        } catch {
            // No plan to delete - that's fine
            print("ℹ️ No old training plan to clear")
        }
        
        // Clear old API key from keychain (previous provider used different keychain account)
        // This ensures a clean slate for OpenAI
        let oldKeychainQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.stride.apikeys",
            kSecAttrAccount as String: "anthropic_api_key"
        ]
        SecItemDelete(oldKeychainQuery as CFDictionary)
        print("✅ Cleared old API key from keychain")
        
        // Mark migration as complete
        defaults.set(true, forKey: migrationKey)
        print("✅ Migration complete - switched to OpenAI/ChatGPT")
    }
}
