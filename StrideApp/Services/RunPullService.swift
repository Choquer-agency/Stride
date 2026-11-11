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

        // Reapply reported checkmarks after any plan rebuild, including older weeks.
        let planDescriptor = FetchDescriptor<TrainingPlan>(predicate: #Predicate { !$0.isArchived })
        let plans = (try? context.fetch(planDescriptor)) ?? []
        if plans.reduce(0, { $0 + CoachReportedCompletions.apply(to: $1) }) > 0 { try? context.save() }
        await reconcileStrengthSessions(context: context)
        guard let serverRuns = try? await APIService.shared.fetchServerRuns() else { return }
        var applied = Set(UserDefaults.standard.stringArray(forKey: appliedKey) ?? [])
        let calendar = Calendar.current
        let localLogs = (try? context.fetch(FetchDescriptor<RunLog>())) ?? []
        var changed = repairFailedRecordingCopies(serverRuns: serverRuns, localLogs: localLogs, calendar: calendar)

        for run in serverRuns {
            guard let runDate = run.completedAtDate else { continue }

            // Absorb corrections: a same-day local log with ~zero distance is a
            // dead tracking run (BLE failure) whose server row was fixed by the
            // coach — update it in place rather than duplicating it. Checked
            // BEFORE the applied-ids guard: the zero run's own id is usually
            // already in the ledger from the pull that deduped it. Idempotent —
            // once absorbed, no same-day zero log remains.
            // Never turn a failed recording into a second copy of a run already on this phone.
            let hasRealLocal = localLogs.contains { log in
                calendar.isDate(log.completedAt, inSameDayAs: runDate)
                    && abs(log.distanceKm - run.distanceKm) < 0.2
                    && log.distanceKm >= 0.2
            }
            if run.distanceKm >= 0.2, !hasRealLocal,
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

            // Value healing: same run (same day, same distance) but the server's
            // duration/pace was corrected by the coach — server wins.
            if let stale = localLogs.first(where: { log in
                calendar.isDate(log.completedAt, inSameDayAs: runDate)
                    && abs(log.distanceKm - run.distanceKm) < 0.2
                    && abs(log.durationSeconds - run.durationSeconds) > 60
            }) {
                stale.distanceKm = run.distanceKm
                stale.kmSplitsJSON = run.kmSplitsJson
                stale.plannedWorkoutTitle = run.plannedWorkoutTitle ?? stale.plannedWorkoutTitle
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
                shoeId: run.shoeId.flatMap(UUID.init(uuidString:)),
                shoeName: run.shoeId.flatMap { id in
                    ((try? context.fetch(FetchDescriptor<Shoe>())) ?? []).first { $0.id.uuidString.lowercased() == id.lowercased() }?.name
                },
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

        // Timestamp healing, one-to-one: every server run first claims its
        // same-day local log; only logs NO server run claims may be moved to a
        // pending run's date. Handles coach date-corrections without the naive
        // failure mode (consecutive same-distance days dragging each other's
        // logs onto the wrong date).
        if reconcileTimestamps(serverRuns: serverRuns, localLogs: localLogs,
                               context: context, calendar: calendar) {
            changed = true
        }

        // Self-heal: any local run history without its planned-workout checkmark
        // (covers timezone edge cases and runs pulled before this pass existed).
        reconcileCompletions(context: context, calendar: calendar)

        // Shoe-usage heal: an outdoor (GPS) run logged against an indoor shoe
        // that has an outdoor same-name twin belongs on the outdoor pair —
        // move the log and its mileage. Idempotent; runs after Bryce tags
        // shoe usage in Settings.
        reassignOutdoorRunShoes(context: context, serverRuns: serverRuns)
        if reconcileServerShoes(serverRuns: serverRuns, context: context) { changed = true }

        // Future-completion heal: a workout dated tomorrow or later cannot
        // have been done — reset it (cleans up the ±1-day matching bug).
        unCompleteFutureWorkouts(context: context, calendar: calendar)

        // Phantom-completion heal: a runnable workout marked complete with no
        // real distance AND no server run on that day was completed by a UI
        // bug, not a run — reset it so the athlete can actually run it.
        unCompletePhantomRuns(serverRuns: serverRuns, context: context, calendar: calendar)

        if repairBryceNovemberSplitRun(context: context, calendar: calendar) { changed = true }
        if repairBryceNovemberRunShoe(context: context) { changed = true }

        if changed { try? context.save() }
        UserDefaults.standard.set(Array(applied), forKey: appliedKey)
    }

    /// One-time phone repair for Bryce's two Maui GPS segments. The server
    /// shoe assignment and mileage were corrected independently; only the
    /// local history label needs healing on older app builds.
    private func repairBryceNovemberRunShoe(context: ModelContext) -> Bool {
        guard AuthService.shared.currentUserID == "95bab56e-316e-418b-8abf-4b909411f64a" else { return false }
        let target = UUID(uuidString: "ac67282a-5ac2-4814-81eb-3a4ba8c52c0b")!
        let ids = Set([
            UUID(uuidString: "a83648fc-1cb7-4ed5-86c3-fbf865ceedd4")!,
            UUID(uuidString: "56abb07a-9e58-42b1-beb1-7d480922ff0a")!
        ])
        let logs = ((try? context.fetch(FetchDescriptor<RunLog>())) ?? [])
            .filter { ids.contains($0.id) && $0.dataSource == "gps" }
        var changed = false
        for log in logs where log.shoeId != target || log.shoeName != "Nike Zoom Fly 6" {
            log.shoeId = target
            log.shoeName = "Nike Zoom Fly 6"
            changed = true
        }
        return changed
    }

    /// Exact server run IDs carry later shoe corrections into local history.
    /// Shoe mileage itself is refreshed from the server by ShoesViewModel.
    private func reconcileServerShoes(serverRuns: [ServerRunDTO], context: ModelContext) -> Bool {
        let logs = (try? context.fetch(FetchDescriptor<RunLog>())) ?? []
        let shoes = (try? context.fetch(FetchDescriptor<Shoe>())) ?? []
        let byID = Dictionary(uniqueKeysWithValues: logs.map { ($0.id, $0) })
        var changed = false
        for run in serverRuns {
            guard let runID = UUID(uuidString: run.id),
                  let shoeID = run.shoeId.flatMap(UUID.init(uuidString:)),
                  let log = byID[runID],
                  log.shoeId != shoeID || log.shoeName == nil else { continue }
            log.shoeId = shoeID
            log.shoeName = shoes.first { $0.id == shoeID }?.name ?? log.shoeName
            changed = true
        }
        return changed
    }

    /// One-time recovery of Bryce's 5 Nov outdoor run: the two original GPS
    /// recordings remain separate history items, while the planned 16 km card
    /// receives their combined measured distance. Exact IDs prevent any other
    /// athlete or date from being touched. Re-running is idempotent.
    private func repairBryceNovemberSplitRun(context: ModelContext, calendar: Calendar) -> Bool {
        guard AuthService.shared.currentUserID == "95bab56e-316e-418b-8abf-4b909411f64a" else { return false }
        let segmentIDs = Set([
            UUID(uuidString: "a83648fc-1cb7-4ed5-86c3-fbf865ceedd4")!,
            UUID(uuidString: "56abb07a-9e58-42b1-beb1-7d480922ff0a")!
        ])
        let logs = ((try? context.fetch(FetchDescriptor<RunLog>())) ?? []).filter { segmentIDs.contains($0.id) }
        guard logs.count == 2, logs.allSatisfy({ $0.dataSource == "gps" && $0.distanceKm > 0.2 }) else { return false }
        var components = DateComponents()
        components.year = 2026; components.month = 11; components.day = 5
        guard let day = calendar.date(from: components),
              logs.allSatisfy({ calendar.isDate($0.completedAt, inSameDayAs: day) }),
              let plan = ((try? context.fetch(FetchDescriptor<TrainingPlan>(predicate: #Predicate { !$0.isArchived }))) ?? []).first else { return false }
        let workouts: [Workout] = plan.weeks.flatMap { $0.workouts }
        let matches = workouts.filter { workout in
            guard workout.title == "Medium-Long Run" else { return false }
            guard calendar.isDate(workout.date, inSameDayAs: day) else { return false }
            let target: Double = workout.distanceKm ?? 0
            return abs(target - 16.0) < 0.1
        }
        guard matches.count == 1, let workout = matches.first else { return false }
        let distance = logs.reduce(0) { $0 + $1.distanceKm }
        let duration = logs.reduce(0) { $0 + $1.durationSeconds }
        guard distance > 14 && distance < 16.5, duration > 3000 else { return false }
        if workout.isCompleted && abs((workout.actualDistanceKm ?? 0) - distance) < 0.001
            && logs.allSatisfy({ $0.plannedWorkoutId == workout.id }) { return false }
        for log in logs {
            log.plannedWorkoutId = workout.id
            log.plannedWorkoutTitle = workout.title
            log.plannedWorkoutTypeRaw = workout.workoutTypeRaw
            log.plannedDistanceKm = 16
        }
        workout.isCompleted = true
        workout.completedAt = logs.map(\.completedAt).max()
        workout.actualDistanceKm = distance
        workout.actualDurationSeconds = duration
        workout.actualAvgPaceSecPerKm = duration / distance
        workout.notes = "Two GPS segments combined from November 5; original recordings retained."
        return true
    }

    /// Older pulls copied a real run onto an unrelated failed same-day recording.
    /// Repair only proven copies: the failed recording's UUID exists on the server,
    /// and both a real server run and another local log corroborate the copied values.
    private func repairFailedRecordingCopies(
        serverRuns: [ServerRunDTO], localLogs: [RunLog], calendar: Calendar
    ) -> Bool {
        var changed = false
        for failed in serverRuns where failed.distanceKm < 0.2 {
            guard let date = failed.completedAtDate,
                  let artifact = localLogs.first(where: {
                      $0.id.uuidString.lowercased() == failed.id.lowercased() && $0.distanceKm >= 0.2
                  }),
                  serverRuns.contains(where: { real in
                      guard real.distanceKm >= 0.2, let realDate = real.completedAtDate else { return false }
                      return calendar.isDate(date, inSameDayAs: realDate)
                          && abs(real.distanceKm - artifact.distanceKm) < 0.01
                          && abs(real.durationSeconds - artifact.durationSeconds) < 1
                  }),
                  localLogs.contains(where: { real in
                      real.id != artifact.id && calendar.isDate(real.completedAt, inSameDayAs: date)
                          && abs(real.distanceKm - artifact.distanceKm) < 0.01
                          && abs(real.durationSeconds - artifact.durationSeconds) < 1
                  }) else { continue }
            artifact.distanceKm = failed.distanceKm
            artifact.durationSeconds = failed.durationSeconds
            artifact.avgPaceSecPerKm = failed.avgPaceSecPerKm
            artifact.kmSplitsJSON = failed.kmSplitsJson
            artifact.completionScore = failed.completionScore
            artifact.plannedWorkoutTitle = failed.plannedWorkoutTitle
            artifact.syncedToServer = true
            changed = true
        }
        return changed
    }

    /// Quick strength logs carry no fabricated exercise detail; they only check off a gym day.
    private func reconcileStrengthSessions(context: ModelContext) async {
        guard let sessions = try? await APIService.shared.getStrengthSessions(), !sessions.isEmpty else { return }
        let descriptor = FetchDescriptor<TrainingPlan>(predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        guard let plan = (try? context.fetch(descriptor))?.first else { return }
        let calendar = Calendar.current
        let workouts = plan.weeks.flatMap { $0.workouts }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        var changed = false
        for session in sessions {
            guard let date = formatter.date(from: session.date) else { continue }
            // No title/workout identifier is exposed by this API. Only match an unambiguous gym day.
            let matches = workouts.filter { $0.workoutType == .gym && calendar.isDate($0.date, inSameDayAs: date) }
            guard matches.count == 1, let workout = matches.first, !workout.isCompleted else { continue }
            workout.isCompleted = true
            workout.completedAt = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)
            if let notes = session.notes { workout.notes = notes }
            if let minutes = session.durationMinutes { workout.actualDurationSeconds = Double(minutes * 60) }
            changed = true
        }
        if changed { try? context.save() }
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
        let flexible = plan.isFlexibleSchedule
        let hasCoachCompletions = workouts.contains { $0.isCoachConfirmedCompletion }

        var didChange = false
        // Flexible week: every real run counts toward the week's sessions, so
        // free runs are candidates too (the regular filter above excludes them).
        let candidatesLogs: [RunLog] = flexible
            ? ((try? context.fetch(FetchDescriptor<RunLog>())) ?? [])
                .filter { ($0.completedAt >= cutoff || hasCoachCompletions) && $0.distanceKm >= 0.2 }
            : logs
        for log in candidatesLogs {
            // Already reconciled — never re-match. (Without this, the ±1-day
            // timezone tolerance re-fired on every pass and checked off
            // TOMORROW's same-titled workout.)
            if log.plannedWorkoutId != nil { continue }
            var match = bestWorkoutMatch(for: log.completedAt, title: log.plannedWorkoutTitle,
                                         in: workouts, calendar: calendar)
            if match == nil, flexible {
                match = flexibleWeekMatch(for: log.completedAt, distanceKm: log.distanceKm,
                                          in: plan, calendar: calendar)
            }
            guard let workout = match else { continue }
            if flexible, !calendar.isDate(workout.date, inSameDayAs: log.completedAt) {
                workout.date = log.completedAt   // session moves to the day it was done
            }
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

    /// One-to-one timestamp reconciliation. Pass 1: each server run claims an
    /// unclaimed local log on its own calendar day (distance-matched). Pass 2:
    /// server runs left without a claim take an unclaimed distance-matched log
    /// within ±72 h and move it to the server's (authoritative) time.
    private func reconcileTimestamps(
        serverRuns: [ServerRunDTO],
        localLogs: [RunLog],
        context: ModelContext,
        calendar: Calendar
    ) -> Bool {
        var claimed = Set<ObjectIdentifier>()
        var unmatched: [(ServerRunDTO, Date)] = []

        for run in serverRuns {
            guard let runDate = run.completedAtDate else { continue }
            if let match = localLogs.first(where: { log in
                !claimed.contains(ObjectIdentifier(log))
                    && calendar.isDate(log.completedAt, inSameDayAs: runDate)
                    && abs(log.distanceKm - run.distanceKm) < 0.2
            }) {
                claimed.insert(ObjectIdentifier(match))
            } else {
                unmatched.append((run, runDate))
            }
        }

        var changed = false
        for (run, runDate) in unmatched {
            guard let misdated = localLogs.first(where: { log in
                !claimed.contains(ObjectIdentifier(log))
                    && abs(log.completedAt.timeIntervalSince(runDate)) < 72 * 3600
                    && abs(log.distanceKm - run.distanceKm) < 0.2
            }) else { continue }
            claimed.insert(ObjectIdentifier(misdated))
            misdated.completedAt = runDate
            if let workoutId = misdated.plannedWorkoutId {
                refreshWorkoutActuals(workoutId: workoutId, from: misdated, context: context)
            }
            changed = true
        }
        return changed
    }

    /// Move GPS runs from indoor shoes to their outdoor same-name twin.
    private func reassignOutdoorRunShoes(context: ModelContext, serverRuns: [ServerRunDTO]) {
        guard let shoes = try? context.fetch(FetchDescriptor<Shoe>()), shoes.count > 1 else { return }
        let serverAssigned = Set(serverRuns.compactMap { run -> UUID? in
            guard run.shoeId != nil else { return nil }
            return UUID(uuidString: run.id)
        })
        let logs = ((try? context.fetch(FetchDescriptor<RunLog>())) ?? [])
            .filter { $0.dataSource == "gps" && $0.shoeId != nil && !serverAssigned.contains($0.id) }
        var changed = false
        for log in logs {
            guard let current = shoes.first(where: { $0.id == log.shoeId }),
                  current.usage == .indoor,
                  let twin = shoes.first(where: {
                      $0.id != current.id && $0.usage == .outdoor
                          && $0.name.lowercased() == current.name.lowercased()
                  }) else { continue }
            log.shoeId = twin.id
            log.shoeName = twin.name
            current.totalDistanceKm = max(0, current.totalDistanceKm - log.distanceKm)
            twin.totalDistanceKm += log.distanceKm
            changed = true
        }
        if changed { try? context.save() }
    }

    /// Reset workouts marked complete whose scheduled date is in the future.
    private func unCompleteFutureWorkouts(context: ModelContext, calendar: Calendar) {
        let startOfTomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        let descriptor = FetchDescriptor<TrainingPlan>(
            predicate: #Predicate<TrainingPlan> { !$0.isArchived },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let plan = (try? context.fetch(descriptor))?.first else { return }
        var changed = false
        for workout in plan.weeks.flatMap({ $0.workouts })
        where workout.isCompleted && workout.date >= startOfTomorrow {
            workout.isCompleted = false
            workout.completedAt = nil
            workout.completionScore = nil
            workout.actualDistanceKm = nil
            workout.actualDurationSeconds = nil
            workout.actualAvgPaceSecPerKm = nil
            changed = true
        }
        if changed { try? context.save() }
    }

    /// Reset runnable workouts that were "completed" without any run behind them.
    private func unCompletePhantomRuns(serverRuns: [ServerRunDTO], context: ModelContext, calendar: Calendar) {
        let descriptor = FetchDescriptor<TrainingPlan>(
            predicate: #Predicate<TrainingPlan> { !$0.isArchived },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let plan = (try? context.fetch(descriptor))?.first else { return }
        var changed = false
        for workout in plan.weeks.flatMap({ $0.workouts }) {
            guard workout.isCompleted,
                  !workout.isCoachConfirmedCompletion,
                  workout.workoutType.isRunnable,
                  (workout.actualDistanceKm ?? 0) < 0.2 else { continue }
            let hasServerRun = serverRuns.contains { run in
                guard let runDate = run.completedAtDate else { return false }
                return calendar.isDate(runDate, inSameDayAs: workout.date)
            }
            if !hasServerRun {
                workout.isCompleted = false
                workout.completedAt = nil
                workout.completionScore = nil
                changed = true
            }
        }
        if changed { try? context.save() }
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
                    && (!workout.isCompleted || (workout.isCoachConfirmedCompletion && workout.actualDistanceKm == nil))
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

    /// Flexible week: an off-schedule run claims the open session of its
    /// Monday–Sunday week whose planned distance is closest to what was run.
    private func flexibleWeekMatch(
        for date: Date,
        distanceKm: Double,
        in plan: TrainingPlan,
        calendar: Calendar
    ) -> Workout? {
        let day = calendar.startOfDay(for: date)
        guard let week = plan.weeks.first(where: { week in
            guard let start = week.mondayStart,
                  let end = calendar.date(byAdding: .day, value: 6, to: start) else { return false }
            return day >= start && day <= end
        }) else { return nil }
        let open = week.sortedWorkouts.filter { workout in
            (!workout.isCompleted || (workout.isCoachConfirmedCompletion && workout.actualDistanceKm == nil))
                && workout.workoutType != .rest
                && workout.workoutType != .gym
                && workout.workoutType != .crossTraining
                && workout.workoutType != .mobility
        }
        return open.min { a, b in
            abs((a.distanceKm ?? 0) - distanceKm) < abs((b.distanceKm ?? 0) - distanceKm)
        }
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

        let workouts = plan.weeks.flatMap { $0.workouts }
        let candidates = workouts.filter { workout in
            guard calendar.isDate(workout.date, inSameDayAs: runDate) else { return false }
            switch workout.workoutType {
            case .rest, .gym, .crossTraining, .mobility: return false
            default: break
            }
            if !workout.isCompleted { return true }
            return workout.isCoachConfirmedCompletion && workout.actualDistanceKm == nil
        }
        // Prefer a title match when the server run is tied to a specific session
        var matched = candidates.first { $0.title == run.plannedWorkoutTitle } ?? candidates.first
        if matched == nil, plan.isFlexibleSchedule, run.distanceKm >= 0.2 {
            matched = flexibleWeekMatch(for: runDate, distanceKm: run.distanceKm, in: plan, calendar: calendar)
            if let m = matched, !calendar.isDate(m.date, inSameDayAs: runDate) { m.date = runDate }
        }
        guard let workout = matched else { return }

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
