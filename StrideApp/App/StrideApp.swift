import SwiftUI
import SwiftData
import PostHog

@main
struct StrideApp: App {
    @StateObject private var bluetoothManager = BluetoothManager()
    @StateObject private var authService = AuthService.shared
    let modelContainer: ModelContainer
    
    init() {
        do {
            let schema = Schema([
                TrainingPlan.self,
                Week.self,
                Workout.self,
                RunLog.self
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

            // PostHog analytics + session replay
            let phConfig = PostHogConfig(
                apiKey: "phc_rkWtGyOhUq2PpSZvTKoc48fGNHAkjom4SYlCITQovqR",
                host: "https://us.i.posthog.com"
            )
            phConfig.sessionReplay = true
            phConfig.sessionReplayConfig.maskAllTextInputs = true
            phConfig.sessionReplayConfig.maskAllImages = true
            phConfig.sessionReplayConfig.captureNetworkTelemetry = true
            phConfig.sessionReplayConfig.screenshotMode = true
            PostHogSDK.shared.setup(phConfig)

            // One-time migration: copy existing completed Workouts → RunLog entries
            migrateWorkoutsToRunLog(container: modelContainer)
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }

    private func migrateWorkoutsToRunLog(container: ModelContainer) {
        guard !UserDefaults.standard.bool(forKey: "hasRunRunLogMigrationV1") else { return }

        let context = ModelContext(container)

        do {
            let predicate = #Predicate<Workout> { $0.isCompleted == true }
            let descriptor = FetchDescriptor<Workout>(predicate: predicate)
            let completedWorkouts = try context.fetch(descriptor)

            for workout in completedWorkouts {
                let isOrphaned = workout.week == nil
                let isFreeRun = isOrphaned && workout.title == "Free Run"

                let runLog = RunLog(
                    distanceKm: workout.actualDistanceKm ?? workout.distanceKm ?? 0,
                    durationSeconds: workout.actualDurationSeconds ?? Double(workout.durationMinutes ?? 0) * 60,
                    avgPaceSecPerKm: workout.actualAvgPaceSecPerKm ?? 0,
                    kmSplitsJSON: workout.kmSplitsJSON,
                    feedbackRating: workout.feedbackRating,
                    notes: workout.notes,
                    plannedWorkoutId: isFreeRun ? nil : workout.id,
                    plannedWorkoutTitle: isFreeRun ? nil : workout.title,
                    plannedWorkoutTypeRaw: isFreeRun ? nil : workout.workoutTypeRaw,
                    plannedDistanceKm: isFreeRun ? nil : workout.distanceKm,
                    plannedDurationMinutes: isFreeRun ? nil : workout.durationMinutes,
                    plannedPaceDescription: isFreeRun ? nil : workout.paceDescription,
                    completionScore: workout.completionScore,
                    planName: workout.week?.plan?.raceName ?? workout.week?.plan?.raceType.displayName,
                    weekNumber: workout.week?.weekNumber
                )
                runLog.completedAt = workout.completedAt ?? workout.date

                context.insert(runLog)

                // Delete orphaned free-run Workout objects (they have no plan context)
                if isOrphaned {
                    context.delete(workout)
                }
            }

            try context.save()
            UserDefaults.standard.set(true, forKey: "hasRunRunLogMigrationV1")
        } catch {
            #if DEBUG
            print("RunLog migration failed: \(error)")
            #endif
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bluetoothManager)
                .environmentObject(authService)
                .preferredColorScheme(.light)
                .onAppear {
                    RunSyncService.shared.configure(with: modelContainer)
                }
                .onChange(of: authService.authState) { _, newState in
                    if case .signedIn = newState {
                        RunSyncService.shared.syncPendingRuns()
                    }
                }
        }
        .modelContainer(modelContainer)
    }
}
