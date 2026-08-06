import SwiftUI
import SwiftData
import PostHog

@main
struct StrideApp: App {
    // UIKit adapter required for APNs delegate callbacks (SwiftUI App lifecycle
    // doesn't expose application:didRegisterForRemoteNotifications:).
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var bluetoothManager = BluetoothManager()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var authService = AuthService.shared
    @StateObject private var pushManager = PushNotificationManager.shared
    @StateObject private var deepLinkRouter = DeepLinkRouter.shared
    @Environment(\.scenePhase) private var scenePhase
    let modelContainer: ModelContainer
    
    init() {
        do {
            let schema = Schema([
                TrainingPlan.self,
                Week.self,
                Workout.self,
                RunLog.self,
                Shoe.self,
                CoachingMessage.self,
                WellnessCheckin.self,
                ChatMessage.self,
                NutritionLog.self,
                HydrationLog.self,
                RaceFuelingPlan.self,
                RecipeTemplate.self,
                RaceLogisticsChecklist.self,
                StrengthExercise.self,
                StrengthSession.self,
                StrengthSet.self
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

            // One-time migration: re-parse plans to recover weeks lost by old parser bug
            reparsePlansIfNeeded(container: modelContainer)
            rebuildPlansForTitleFixIfNeeded(container: modelContainer)
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }

    /// One-time V2 re-parse: earlier builds mis-extracted workout titles from
    /// em-dash day lines (title became the whole raw sentence). Rebuild every
    /// active plan's weeks from rawPlanContent with the fixed parser,
    /// preserving completed-workout data by calendar date.
    private func rebuildPlansForTitleFixIfNeeded(container: ModelContainer) {
        guard !UserDefaults.standard.bool(forKey: "hasRunPlanReparseMigrationV2") else { return }

        let context = ModelContext(container)
        do {
            let descriptor = FetchDescriptor<TrainingPlan>(
                predicate: #Predicate<TrainingPlan> { !$0.isArchived }
            )
            let plans = try context.fetch(descriptor)
            let calendar = Calendar.current

            for plan in plans {
                guard let rawContent = plan.rawPlanContent, !rawContent.isEmpty else { continue }
                let parsedWeeks = PlanParser.parse(content: rawContent, startDate: plan.startDate, raceDate: plan.raceDate)
                guard !parsedWeeks.isEmpty else { continue }

                var completionData: [DateComponents: Workout] = [:]
                for week in plan.weeks {
                    for workout in week.workouts where workout.isCompleted {
                        completionData[calendar.dateComponents([.year, .month, .day], from: workout.date)] = workout
                    }
                }

                for week in plan.weeks { context.delete(week) }
                plan.weeks.removeAll()

                for parsedWeek in parsedWeeks {
                    let week = Week(weekNumber: parsedWeek.weekNumber, theme: parsedWeek.theme)
                    for parsedWorkout in parsedWeek.workouts {
                        let workout = Workout(
                            date: parsedWorkout.date,
                            workoutType: parsedWorkout.workoutType,
                            title: parsedWorkout.title,
                            details: parsedWorkout.details,
                            distanceKm: parsedWorkout.distanceKm,
                            durationMinutes: parsedWorkout.durationMinutes,
                            paceDescription: parsedWorkout.paceDescription
                        )
                        let key = calendar.dateComponents([.year, .month, .day], from: parsedWorkout.date)
                        if let old = completionData[key] {
                            workout.isCompleted = old.isCompleted
                            workout.completedAt = old.completedAt
                            workout.notes = old.notes
                            workout.actualDistanceKm = old.actualDistanceKm
                            workout.actualDurationSeconds = old.actualDurationSeconds
                            workout.actualAvgPaceSecPerKm = old.actualAvgPaceSecPerKm
                            workout.completionScore = old.completionScore
                            workout.kmSplitsJSON = old.kmSplitsJSON
                            workout.feedbackRating = old.feedbackRating
                        }
                        week.workouts.append(workout)
                    }
                    plan.weeks.append(week)
                }
            }

            try context.save()
            UserDefaults.standard.set(true, forKey: "hasRunPlanReparseMigrationV2")
        } catch {
            #if DEBUG
            print("Plan title-fix reparse migration failed: \(error)")
            #endif
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
                    planName: workout.week?.plan?.raceName ?? workout.week?.plan?.displayDistance,
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
    
    private func reparsePlansIfNeeded(container: ModelContainer) {
        guard !UserDefaults.standard.bool(forKey: "hasRunPlanReparseMigrationV1") else { return }

        let context = ModelContext(container)

        do {
            let descriptor = FetchDescriptor<TrainingPlan>()
            let plans = try context.fetch(descriptor)

            var totalAdded = 0

            for plan in plans {
                guard let rawContent = plan.rawPlanContent, !rawContent.isEmpty else { continue }

                let parsedWeeks = PlanParser.parse(content: rawContent, startDate: plan.startDate, raceDate: plan.raceDate)

                // Build set of existing week numbers
                let existingWeekNumbers = Set(plan.weeks.map { $0.weekNumber })

                // Find missing weeks
                let missingWeeks = parsedWeeks.filter { !existingWeekNumbers.contains($0.weekNumber) }
                guard !missingWeeks.isEmpty else { continue }

                for parsedWeek in missingWeeks {
                    let week = Week(weekNumber: parsedWeek.weekNumber, theme: parsedWeek.theme)

                    for parsedWorkout in parsedWeek.workouts {
                        let workout = Workout(
                            date: parsedWorkout.date,
                            workoutType: parsedWorkout.workoutType,
                            title: parsedWorkout.title,
                            details: parsedWorkout.details,
                            distanceKm: parsedWorkout.distanceKm,
                            durationMinutes: parsedWorkout.durationMinutes,
                            paceDescription: parsedWorkout.paceDescription
                        )
                        week.workouts.append(workout)
                    }

                    plan.weeks.append(week)
                }

                totalAdded += missingWeeks.count

                #if DEBUG
                print("Re-parsed plan '\(plan.raceName ?? plan.displayDistance)': added \(missingWeeks.count) missing weeks (now \(plan.weeks.count) total)")
                #endif
            }

            try context.save()
            UserDefaults.standard.set(true, forKey: "hasRunPlanReparseMigrationV1")

            #if DEBUG
            if totalAdded > 0 {
                print("Plan reparse migration complete: added \(totalAdded) missing weeks across all plans")
            } else {
                print("Plan reparse migration: no missing weeks found")
            }
            #endif
        } catch {
            #if DEBUG
            print("Plan reparse migration failed: \(error)")
            #endif
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bluetoothManager)
                .environmentObject(locationManager)
                .environmentObject(authService)
                .environmentObject(pushManager)
                .environmentObject(deepLinkRouter)
                .preferredColorScheme(.light)
                .onAppear {
                    RunSyncService.shared.configure(with: modelContainer)
                    // If we're already signed in when the app re-appears (backgrounded
                    // → foregrounded), fire the prefetch here. onChange only catches
                    // state *transitions*, so a warm relaunch could otherwise miss it.
                    if case .signedIn(let user) = authService.authState {
                        seedBryceDemoDataIfNeeded(for: user, container: modelContainer)
                        completeBryceDemoWorkoutsThroughToday(for: user, container: modelContainer)
                        RunSyncService.shared.syncPendingRuns()
                        PreRunIntroPrefetcher.shared.warmUpIfNeeded(container: modelContainer)
                        Task { await pushManager.reregisterIfAuthorized() }
                    }
                }
                .onChange(of: authService.authState) { _, newState in
                    if case .signedIn(let user) = newState {
                        seedBryceDemoDataIfNeeded(for: user, container: modelContainer)
                        completeBryceDemoWorkoutsThroughToday(for: user, container: modelContainer)
                        RunSyncService.shared.syncPendingRuns()
                        PreRunIntroPrefetcher.shared.warmUpIfNeeded(container: modelContainer)
                        // Request push permission once after first sign-in.
                        Task { await pushManager.requestAuthorization() }
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active, case .signedIn = authService.authState {
                        PreRunIntroPrefetcher.shared.warmUpIfNeeded(container: modelContainer)
                        Task { await pushManager.reregisterIfAuthorized() }
                    }
                }
                // Handle stride:// URLs opened from external sources (universal links
                // in the future, or testing via Safari). Push-tap routing goes via
                // PushNotificationManager → DeepLinkRouter directly.
                .onOpenURL { url in
                    deepLinkRouter.handle(url: url)
                }
        }
        .modelContainer(modelContainer)
    }

    /// One-time preview dataset requested for the owner's Apple account. Plans are
    /// device-local today; seeded RunLogs use the normal authenticated sync path.
    private func seedBryceDemoDataIfNeeded(for user: UserResponse, container: ModelContainer) {
        guard user.email.lowercased() == "brycechoquer@me.com" else { return }
        let seedKey = "bryce_demo_half_marathon_seed_v1_\(user.id.lowercased())"
        guard !UserDefaults.standard.bool(forKey: seedKey) else { return }

        let context = ModelContext(container)
        do {
            let activePlans = try context.fetch(FetchDescriptor<TrainingPlan>(
                predicate: #Predicate { !$0.isArchived }
            ))
            guard activePlans.isEmpty else {
                UserDefaults.standard.set(true, forKey: seedKey)
                return
            }

            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
            let planStart = calendar.date(byAdding: .weekOfYear, value: -3, to: currentWeekStart)!
            let raceDate = calendar.date(byAdding: .weekOfYear, value: 9, to: currentWeekStart)!
            let plan = TrainingPlan(
                raceType: .halfMarathon,
                raceDate: raceDate,
                raceName: "Stride Half Marathon",
                goalTime: "1:50:00",
                currentWeeklyMileage: 28,
                longestRecentRun: 12,
                fitnessLevel: .intermediate,
                startDate: planStart,
                planMode: .recommended
            )
            context.insert(plan)

            let weeklyDistances: [[Double]] = [
                [5, 6, 5, 11], [5, 7, 5, 12], [6, 7, 5, 14],
                [6, 8, 5, 15], [6, 8, 6, 16], [7, 9, 6, 18],
                [6, 8, 5, 14], [7, 10, 6, 19], [6, 8, 5, 16],
                [6, 9, 5, 18], [5, 7, 4, 12], [4, 5, 3, 21.1]
            ]
            let titles = ["Easy Run", "Tempo Run", "Recovery Run", "Long Run"]
            let types: [WorkoutType] = [.easyRun, .tempoRun, .recovery, .longRun]
            let dayOffsets = [1, 3, 5, 6]

            for weekIndex in weeklyDistances.indices {
                let week = Week(
                    weekNumber: weekIndex + 1,
                    theme: weekIndex < 3 ? "Aerobic Foundation" : (weekIndex < 9 ? "Half Marathon Build" : "Race Preparation")
                )
                plan.weeks.append(week)
                let weekStart = calendar.date(byAdding: .weekOfYear, value: weekIndex, to: planStart)!

                for workoutIndex in weeklyDistances[weekIndex].indices {
                    let distance = weeklyDistances[weekIndex][workoutIndex]
                    let date = calendar.date(byAdding: .day, value: dayOffsets[workoutIndex], to: weekStart)!
                    let pace = types[workoutIndex] == .tempoRun ? 305.0 : (types[workoutIndex] == .longRun ? 345.0 : 335.0)
                    let workout = Workout(
                        date: date,
                        workoutType: types[workoutIndex],
                        title: weekIndex == 11 && workoutIndex == 3 ? "Half Marathon Race" : titles[workoutIndex],
                        details: types[workoutIndex] == .tempoRun ? "2 km easy, controlled tempo effort, then cool down." : "Keep the effort controlled and finish feeling strong.",
                        distanceKm: distance,
                        durationMinutes: Int(distance * pace / 60),
                        paceDescription: types[workoutIndex] == .tempoRun ? "4:55–5:15 /km" : "5:25–5:55 /km"
                    )
                    week.workouts.append(workout)

                    guard weekIndex < 3 else { continue }
                    let actualDistance = distance + [0.08, -0.04, 0.12, 0.18][workoutIndex]
                    let actualPace = pace + Double((weekIndex * 3 + workoutIndex) % 9 - 4)
                    let duration = actualDistance * actualPace
                    let splits = demoSplits(distanceKm: actualDistance, paceSeconds: actualPace)

                    workout.isCompleted = true
                    workout.completedAt = date
                    workout.actualDistanceKm = actualDistance
                    workout.actualDurationSeconds = duration
                    workout.actualAvgPaceSecPerKm = actualPace
                    workout.completionScore = 88 + ((weekIndex + workoutIndex) % 9)
                    workout.feedbackRating = 4
                    workout.kmSplitsJSON = splits

                    let run = RunLog(
                        distanceKm: actualDistance,
                        durationSeconds: duration,
                        avgPaceSecPerKm: actualPace,
                        kmSplitsJSON: splits,
                        feedbackRating: 4,
                        notes: workoutIndex == 3 ? "Comfortable long run with a steady finish." : nil,
                        dataSource: workoutIndex.isMultiple(of: 2) ? "gps" : "bluetooth_ftms",
                        treadmillBrand: workoutIndex.isMultiple(of: 2) ? nil : "Assault Runner",
                        plannedWorkoutId: workout.id,
                        plannedWorkoutTitle: workout.title,
                        plannedWorkoutTypeRaw: workout.workoutTypeRaw,
                        plannedDistanceKm: distance,
                        plannedDurationMinutes: workout.durationMinutes,
                        plannedPaceDescription: workout.paceDescription,
                        completionScore: workout.completionScore,
                        planName: plan.raceName,
                        weekNumber: week.weekNumber
                    )
                    run.completedAt = date
                    context.insert(run)
                }
            }

            try context.save()
            UserDefaults.standard.set(true, forKey: seedKey)
        } catch {
            print("Demo data seed failed: \(error.localizedDescription)")
        }
    }

    private func demoSplits(distanceKm: Double, paceSeconds: Double) -> String? {
        var cumulative = 0
        let splits = (1...Int(floor(distanceKm))).map { kilometer -> CodableKilometerSplit in
            let splitSeconds = max(240, Int(paceSeconds) + (kilometer % 5 - 2) * 3)
            cumulative += splitSeconds
            return CodableKilometerSplit(
                kilometer: kilometer,
                pace: String(format: "%d:%02d", splitSeconds / 60, splitSeconds % 60),
                time: String(format: "%d:%02d:%02d", cumulative / 3600, (cumulative % 3600) / 60, cumulative % 60),
                isFastest: false
            )
        }
        guard let data = try? JSONEncoder().encode(splits) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Keep the requested preview history internally consistent: every scheduled
    /// workout through today has both completion fields and one matching RunLog.
    private func completeBryceDemoWorkoutsThroughToday(for user: UserResponse, container: ModelContainer) {
        guard user.email.lowercased() == "brycechoquer@me.com" else { return }
        let completionKey = "bryce_demo_completed_through_2026_07_11_v1_\(user.id.lowercased())"
        guard !UserDefaults.standard.bool(forKey: completionKey) else { return }

        let context = ModelContext(container)
        do {
            let plans = try context.fetch(FetchDescriptor<TrainingPlan>(
                predicate: #Predicate { !$0.isArchived }
            ))
            guard let plan = plans.first(where: { $0.raceName == "Stride Half Marathon" }) else { return }

            let existingRuns = try context.fetch(FetchDescriptor<RunLog>())
            let loggedWorkoutIds = Set(existingRuns.compactMap(\.plannedWorkoutId))
            let endOfToday = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400)

            for week in plan.weeks {
                for workout in week.workouts where workout.date < endOfToday && workout.workoutType != .rest {
                    let plannedDistance = workout.distanceKm ?? 5
                    let pace = workout.workoutType == .tempoRun ? 305.0 : (workout.workoutType == .longRun ? 345.0 : 335.0)
                    let actualDistance = plannedDistance + 0.08
                    let actualPace = pace - Double((week.weekNumber + Calendar.current.component(.day, from: workout.date)) % 6)
                    let duration = actualDistance * actualPace
                    let splits = demoSplits(distanceKm: actualDistance, paceSeconds: actualPace)

                    workout.isCompleted = true
                    workout.completedAt = workout.date
                    workout.actualDistanceKm = actualDistance
                    workout.actualDurationSeconds = duration
                    workout.actualAvgPaceSecPerKm = actualPace
                    workout.completionScore = 92
                    workout.feedbackRating = 4
                    workout.kmSplitsJSON = splits

                    guard !loggedWorkoutIds.contains(workout.id) else { continue }
                    let run = RunLog(
                        distanceKm: actualDistance,
                        durationSeconds: duration,
                        avgPaceSecPerKm: actualPace,
                        kmSplitsJSON: splits,
                        feedbackRating: 4,
                        notes: "Completed as part of the preview training history.",
                        dataSource: workout.workoutType == .tempoRun ? "bluetooth_ftms" : "gps",
                        treadmillBrand: workout.workoutType == .tempoRun ? "Assault Runner" : nil,
                        plannedWorkoutId: workout.id,
                        plannedWorkoutTitle: workout.title,
                        plannedWorkoutTypeRaw: workout.workoutTypeRaw,
                        plannedDistanceKm: plannedDistance,
                        plannedDurationMinutes: workout.durationMinutes,
                        plannedPaceDescription: workout.paceDescription,
                        completionScore: workout.completionScore,
                        planName: plan.raceName,
                        weekNumber: week.weekNumber
                    )
                    run.completedAt = workout.date
                    context.insert(run)
                }
            }

            try context.save()
            UserDefaults.standard.set(true, forKey: completionKey)
        } catch {
            print("Demo completion update failed: \(error.localizedDescription)")
        }
    }
}
