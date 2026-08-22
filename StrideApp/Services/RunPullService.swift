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
            guard let runDate = run.completedAtDate else { continue }

            // Absorb corrections: a same-day local log with ~zero distance is a
            // dead tracking run (BLE failure) whose server row was fixed by the
            // coach — update it in place rather than duplicating it. Checked
            // BEFORE the applied-ids guard: the zero run's own id is usually
            // already in the ledger from the pull that deduped it. Idempotent —
            // once absorbed, no same-day zero log remains.
            if run.distanceKm >= 0.2,
               let dead = localLogs.first(where: { log in
                   calendar.isDate(log.completedAt, inSameDayAs: runDate) && log.distanceKm < 0.2
               }) {
                dead.distanceKm = run.distanceKm
                dead.durationSeconds = run.durationSeconds
                dead.avgPaceSecPerKm = run.avgPaceSecPerKm
                dead.completionScore = run.completionScore
                dead.kmSplitsJSON = run.kmSplitsJson ?? dead.kmSplitsJSON
                if dead.plannedWorkoutTitle == nil { dead.plannedWorkoutTitle = run.plannedWorkoutTitle }
                dead.syncedToServer = true
                // The zero run may already have checked off its workout with
                // zero actuals — refresh them.
                if let workoutId = dead.plannedWorkoutId {
                    refreshWorkoutActuals(workoutId: workoutId, from: dead, context: context)
                }
                applied.insert(run.id)
                changed = true
                continue
            }

            // Timestamp healing: the server is authoritative for WHEN a run
            // happened (coach corrections). The same run — distance match
            // within ±36 h — sitting on a different calendar day locally gets
            // moved to the server time. Also before the ledger guard: the run
            // may have been applied back when its timestamp was still wrong.
            if let misdated = localLogs.first(where: { log in
                abs(log.completedAt.timeIntervalSince(runDate)) < 36 * 3600
                    && !calendar.isDate(log.completedAt, inSameDayAs: runDate)
                    && abs(log.distanceKm - run.distanceKm) < 0.2
            }) {
                misdated.completedAt = runDate
                if let workoutId = misdated.plannedWorkoutId {
                    refreshWorkoutActuals(workoutId: workoutId, from: misdated, context: context)
                }
                applied.insert(run.id)
                changed = true
                continue
            }

            // Value healing: same run (same day, same distance) but the server's
            // duration/pace was corrected by the coach — server wins.
            if let stale = localLogs.first(where: { log in
                calendar.isDate(log.completedAt, inSameDayAs: runDate)
                    && abs(log.distanceKm - run.distanceKm) < 0.2
                    && abs(log.durationSeconds - run.durationSeconds) > 60
            }) {
                stale.durationSeconds = run.durationSeconds
                stale.avgPaceSecPerKm = run.avgPaceSecPerKm
                stale.completionScore = run.completionScore
                if let workoutId = stale.plannedWorkoutId {
                    refreshWorkoutActuals(workoutId: workoutId, from: stale, context: context)
                }
                applied.insert(run.id)
                changed = true
                continue
            }

            guard !applied.contains(run.id) else { continue }

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

        // Self-heal: any local run history without its planned-workout checkmark
        // (covers timezone edge cases and runs pulled before this pass existed).
        reconcileCompletions(context: context, calendar: calendar)

        if changed { try? context.save() }
        UserDefaults.standard.set(Array(applied), forKey: appliedKey)
    }

    /// Match every recent RunLog to an uncompleted planned workout on the same
    /// (or adjacent — timezone tolerance) calendar day and check it off.
    private func reconcileCompletions(context: ModelContext, calendar: Calendar) {
        let cutoff = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        // A planned run is one carrying either a local workout link OR a planned
        // title (server-pulled runs have the title but no local workout UUID —
        // isFreeRun alone wrongly excludes them).
        let logs = ((try? context.fetch(FetchDescriptor<RunLog>())) ?? [])
            .filter { $0.completedAt >= cutoff && ($0.plannedWorkoutTitle != nil || !$0.isFreeRun) }

        let planDescriptor = FetchDescriptor<TrainingPlan>(
            predicate: #Predicate<TrainingPlan> { !$0.isArchived },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let plan = (try? context.fetch(planDescriptor))?.first else { return }
        let workouts = plan.weeks.flatMap { $0.workouts }

        var didChange = false
        for log in logs {
            let match = bestWorkoutMatch(for: log.completedAt, title: log.plannedWorkoutTitle,
                                         in: workouts, calendar: calendar)
            guard let workout = match else { continue }
            log.plannedWorkoutId = workout.id   // back-link so this log stops reading as a free run
            workout.isCompleted = true
            workout.completedAt = log.completedAt
            workout.actualDistanceKm = log.distanceKm
            workout.actualDurationSeconds = log.durationSeconds
            workout.actualAvgPaceSecPerKm = log.avgPaceSecPerKm
            workout.completionScore = log.completionScore
            if let splits = log.kmSplitsJSON { workout.kmSplitsJSON = splits }
            if let rating = log.feedbackRating { workout.feedbackRating = rating }
            didChange = true
        }
        if didChange { try? context.save() }
    }

    /// Overwrite a completed workout's actuals after its RunLog was corrected.
    private func refreshWorkoutActuals(workoutId: UUID, from log: RunLog, context: ModelContext) {
        let descriptor = FetchDescriptor<TrainingPlan>(
            predicate: #Predicate<TrainingPlan> { !$0.isArchived },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let plan = (try? context.fetch(descriptor))?.first,
              let workout = plan.weeks.flatMap({ $0.workouts }).first(where: { $0.id == workoutId })
        else { return }
        workout.isCompleted = true
        workout.completedAt = log.completedAt
        workout.actualDistanceKm = log.distanceKm
        workout.actualDurationSeconds = log.durationSeconds
        workout.actualAvgPaceSecPerKm = log.avgPaceSecPerKm
        workout.completionScore = log.completionScore
    }

    private func bestWorkoutMatch(
        for date: Date,
        title: String?,
        in workouts: [Workout],
        calendar: Calendar
    ) -> Workout? {
        func candidates(dayOffset: Int) -> [Workout] {
            guard let target = calendar.date(byAdding: .day, value: dayOffset, to: date) else { return [] }
            return workouts.filter { workout in
                calendar.isDate(workout.date, inSameDayAs: target)
                    && !workout.isCompleted
                    && workout.workoutType != .rest
                    && workout.workoutType != .gym
                    && workout.workoutType != .crossTraining
                    && workout.workoutType != .mobility
            }
        }
        // Same day first; then ±1 day for UTC/local drift, preferring title matches
        for offset in [0, 1, -1] {
            let pool = candidates(dayOffset: offset)
            if let titled = pool.first(where: { $0.title == title }) { return titled }
            if offset == 0, let any = pool.first { return any }
        }
        return nil
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
