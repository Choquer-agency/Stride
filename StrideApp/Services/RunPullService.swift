import Foundation
import SwiftData

/// Server → phone run bridge.
///
/// Runs normally flow phone → server (RunSyncService). This service closes the
/// loop: runs that exist server-side but not locally — logged manually by the
/// coach, corrected, or recovered after a tracking failure — are pulled down,
/// written into RunLog (so Stats counts them), and matched to the planned
/// workout on that calendar day (so the plan shows the checkmark).
@MainActor
final class RunPullService {
    static let shared = RunPullService()

    private var inFlight = false
    private let appliedKey = "run_pull_applied_server_ids"

    private init() {}

    func reconcile(context: ModelContext) async {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        guard let serverRuns = try? await APIService.shared.fetchServerRuns() else { return }
        var applied = Set(UserDefaults.standard.stringArray(forKey: appliedKey) ?? [])
        let calendar = Calendar.current
        let localLogs = (try? context.fetch(FetchDescriptor<RunLog>())) ?? []
        var changed = false

        for run in serverRuns {
            guard !applied.contains(run.id), let runDate = run.completedAtDate else { continue }

            // Dedupe against runs that originated on this phone (or were
            // already pulled before the applied-ids ledger existed).
            let alreadyLocal = localLogs.contains { log in
                calendar.isDate(log.completedAt, inSameDayAs: runDate)
                    && abs(log.distanceKm - run.distanceKm) < 0.2
            }
            if alreadyLocal {
                applied.insert(run.id)
                continue
            }

            // 1. Local run history (Stats reads this)
            let log = RunLog(
                distanceKm: run.distanceKm,
                durationSeconds: run.durationSeconds,
                avgPaceSecPerKm: run.avgPaceSecPerKm,
                kmSplitsJSON: run.kmSplitsJson,
                feedbackRating: run.feedbackRating,
                notes: run.notes,
                dataSource: run.dataSource,
                treadmillBrand: run.treadmillBrand,
                plannedWorkoutTitle: run.plannedWorkoutTitle,
                plannedWorkoutTypeRaw: run.plannedWorkoutType,
                plannedDistanceKm: run.plannedDistanceKm,
                completionScore: run.completionScore,
                planName: run.planName,
                weekNumber: run.weekNumber
            )
            log.completedAt = runDate
            log.syncedToServer = true   // it came FROM the server — never re-push
            context.insert(log)

            // 2. Check off the matching planned workout
            markPlannedWorkoutComplete(for: run, on: runDate, context: context, calendar: calendar)

            applied.insert(run.id)
            changed = true
        }

        if changed { try? context.save() }
        UserDefaults.standard.set(Array(applied), forKey: appliedKey)
    }

    private func markPlannedWorkoutComplete(
        for run: ServerRunDTO,
        on runDate: Date,
        context: ModelContext,
        calendar: Calendar
    ) {
        let descriptor = FetchDescriptor<TrainingPlan>(
            predicate: #Predicate<TrainingPlan> { !$0.isArchived },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let plan = (try? context.fetch(descriptor))?.first else { return }

        let candidates = plan.weeks
            .flatMap { $0.workouts }
            .filter { workout in
                calendar.isDate(workout.date, inSameDayAs: runDate)
                    && !workout.isCompleted
                    && workout.workoutType != .rest
                    && workout.workoutType != .gym
                    && workout.workoutType != .crossTraining
                    && workout.workoutType != .mobility
            }
        // Prefer a title match when the server run is tied to a specific session
        let workout = candidates.first { $0.title == run.plannedWorkoutTitle } ?? candidates.first
        guard let workout else { return }

        workout.isCompleted = true
        workout.completedAt = runDate
        workout.actualDistanceKm = run.distanceKm
        workout.actualDurationSeconds = run.durationSeconds
        workout.actualAvgPaceSecPerKm = run.avgPaceSecPerKm
        workout.completionScore = run.completionScore
        if let splits = run.kmSplitsJson { workout.kmSplitsJSON = splits }
        if let rating = run.feedbackRating { workout.feedbackRating = rating }
    }
}
