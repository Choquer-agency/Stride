import SwiftUI
import SwiftData

struct StatsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<TrainingPlan> { $0.isArchived == false }, sort: \TrainingPlan.createdAt, order: .reverse) private var plans: [TrainingPlan]
    @Query(sort: \RunLog.completedAt, order: .reverse) private var runLogs: [RunLog]
    @Query(filter: #Predicate<Shoe> { $0.isRetired == false }, sort: \Shoe.name) private var shoes: [Shoe]
    @StateObject private var shoesViewModel = ShoesViewModel()
    @State private var selectedRun: RunLog?
    @Binding var selectedTab: MainTabView.Tab
    private var activePlan: TrainingPlan? { plans.first }
    private var validRunLogs: [RunLog] { runLogs.filter { $0.isValidForStats && $0.completedAt <= Date() } }

    var body: some View {
        let logs = validRunLogs
        StatsDesignedPage(runLogs: logs, plan: activePlan, shoes: shoes,
                          onSelectRun: { selectedRun = $0 },
                          onOpenProfile: { selectedTab = .profile })
        .background { StridePageBackdrop().ignoresSafeArea() }
        .sheet(item: $selectedRun) { run in
            RecordedRunReviewSheet(run: run, workout: linkedWorkout(for: run))
        }
        .task {
            if ProcessInfo.processInfo.arguments.contains("--runview-demo-stats") {
                if ProcessInfo.processInfo.arguments.contains("--stats-open-run") { selectedRun = logs.first { $0.plannedWorkoutType == .recovery } }
                return
            }
            shoesViewModel.syncFromServer(context: modelContext)
            await RunPullService.shared.reconcile(context: modelContext)
        }
        .refreshable { await RunPullService.shared.reconcile(context: modelContext) }
    }

    private func linkedWorkout(for run: RunLog) -> Workout? {
        guard let id = run.plannedWorkoutId else { return nil }
        return try? modelContext.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id })).first
    }
}

#Preview {
    StatsView(selectedTab: .constant(.stats))
        .modelContainer(for: [TrainingPlan.self, RunLog.self], inMemory: true)
}

#if DEBUG
/// Isolated analytics preview; no athlete records or plan are modified.
@MainActor
private final class StatsDashboardFixture: ObservableObject {
    let container: ModelContainer
    init() {
        container = try! ModelContainer(for: TrainingPlan.self, RunLog.self, Shoe.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let calendar = StatsTrainingData.calendar()
        let monday = StatsTrainingData.week(containing: Date()).start
        let start = calendar.date(byAdding: .weekOfYear, value: -10, to: monday)!
        let race = calendar.date(byAdding: .day, value: 167, to: start)!
        let plan = TrainingPlan(raceType: .marathon, raceDate: race, raceName: "Maui Marathon",
            currentWeeklyMileage: 60, longestRecentRun: 20, fitnessLevel: .intermediate, startDate: start)
        container.mainContext.insert(plan)
        let roadShoe = Shoe(name: "Vomero 18", isDefault: true, totalDistanceKm: 412)
        roadShoe.recommendedMaxKm = 650
        container.mainContext.insert(roadShoe)
        let speedShoe = Shoe(name: "Streakfly 2", totalDistanceKm: 164)
        speedShoe.recommendedMaxKm = 350
        container.mainContext.insert(speedShoe)
        for number in 1...24 {
            let week = Week(weekNumber: number)
            week.plan = plan
            let base = calendar.date(byAdding: .weekOfYear, value: number - 1, to: start)!
            let long = number == 11 ? 24.0 : number >= 22 ? 10.0 : min(32, Double(8 + number * 2))
            let prescriptions: [(Int, WorkoutType, String, Double)] = [
                (1, .intervals, "Cruise Intervals", 12), (2, .easyRun, "Easy Run", 6),
                (3, .longRun, "Medium-Long Run", 14), (5, .recovery, "Recovery Run", 4),
                (6, number == 24 ? .race : .longRun, number == 24 ? "Maui Marathon" : "Long Run", number == 24 ? 42.195 : long)]
            for (offset, type, title, distance) in prescriptions {
                let workout = Workout(date: calendar.date(byAdding: .day, value: offset, to: base)!,
                    workoutType: type, title: title, distanceKm: distance, paceDescription: "6:00–6:30/km")
                workout.week = week
                container.mainContext.insert(workout)
            }
            container.mainContext.insert(week)
        }
        for back in 0..<8 {
            let base = calendar.date(byAdding: .weekOfYear, value: -back, to: monday)!
            let activities: [(Int, Double, WorkoutType, String)] = [
                (1, 12.02, .intervals, "Cruise Intervals"), (2, 6, .easyRun, "Easy Run"),
                (3, 14, .longRun, "Medium-Long Run"), (5, 4, .recovery, "Recovery Run")]
            for (offset, distance, type, title) in activities {
                let when = calendar.date(byAdding: .hour, value: 10, to: calendar.date(byAdding: .day, value: offset, to: base)!)!
                guard when <= Date() else { continue }
                let bpm = type == .easyRun ? 142 + back * 2 : 150
                let log = RunLog(distanceKm: distance, durationSeconds: distance * 394,
                    avgPaceSecPerKm: 394, feedbackRating: max(0, 4 - back / 3),
                    avgHeartRate: bpm, plannedWorkoutTitle: title, plannedWorkoutTypeRaw: type.rawValue,
                    plannedDistanceKm: distance, plannedPaceDescription: "6:00–6:30/km", completionScore: 97)
                log.completedAt = when
                if type == .easyRun {
                    let samples = stride(from: 0.0, to: log.durationSeconds, by: 5).map { CodableHRSample(t: $0, bpm: bpm) }
                    log.hrSamplesJSON = String(data: try! JSONEncoder().encode(samples), encoding: .utf8)
                }
                container.mainContext.insert(log)
            }
        }
        try! container.mainContext.save()
    }
}

struct StatsDashboardPreview: View {
    @StateObject private var fixture = StatsDashboardFixture()
    var body: some View {
        GeometryReader { geometry in
            StatsView(selectedTab: .constant(.stats))
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    CustomTabBar(selectedTab: .constant(.stats), screenWidth: geometry.size.width)
                }
        }
        .modelContainer(fixture.container)
    }
}

struct ProfileDashboardPreview: View {
    @StateObject private var fixture = StatsDashboardFixture()
    var body: some View {
        GeometryReader { geometry in
            NavigationStack {
                ProfileView()
                    .environmentObject(AuthService.shared)
                    .environmentObject(BluetoothManager())
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                CustomTabBar(selectedTab: .constant(.profile), screenWidth: geometry.size.width)
            }
        }
        .modelContainer(fixture.container)
    }
}
#endif
