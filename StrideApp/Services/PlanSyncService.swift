import Foundation
import SwiftData
import SwiftUI

/// Keeps the device's active plan and the server's plan store reconciled.
///
/// - **Backfill**: if the server has no copy of the active local plan (plans
///   created before server-side persistence), upload it.
/// - **Pull**: if the server holds *newer* content than the device last
///   applied (a coach edit made server-side), publish it so PlanView can offer
///   "Your coach updated your plan → Apply".
///
/// Plans generated/edited on-device are persisted server-side by the backend
/// at generation time, so in the steady state contents match and this no-ops.
@MainActor
final class PlanSyncService: ObservableObject {
    static let shared = PlanSyncService()

    /// Server plan content awaiting the athlete's approval to apply locally.
    @Published var pendingServerPlan: RemotePlanDTO?

    private let lastAppliedKey = "plan_sync_last_applied_updated_at"
    private var inFlight = false

    private init() {}

    // MARK: - Reconcile

    func reconcile(context: ModelContext) async {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        guard let localPlan = activeLocalPlan(context: context) else { return }
        guard let remote = try? await APIService.shared.fetchRemotePlan() else { return }

        if !remote.exists {
            // Server has never seen a plan for this user — backfill.
            await backfill(localPlan)
            return
        }

        guard let remoteContent = remote.rawPlanContent else { return }

        if remoteContent == localPlan.rawPlanContent {
            // In sync — remember the server timestamp so future edits register as newer.
            if let ts = remote.updatedAt { UserDefaults.standard.set(ts, forKey: lastAppliedKey) }
            pendingServerPlan = nil
            return
        }

        // Content differs. Only offer the server version when it's genuinely
        // newer than what this device last applied — otherwise the device holds
        // newer content (e.g. edited offline) and we push instead.
        let lastApplied = UserDefaults.standard.string(forKey: lastAppliedKey) ?? ""
        if let ts = remote.updatedAt, ts > lastApplied {
            pendingServerPlan = remote
        } else {
            await backfill(localPlan)
        }
    }

    private func backfill(_ plan: TrainingPlan) async {
        guard let content = plan.rawPlanContent, !content.isEmpty else { return }
        let result = try? await APIService.shared.syncPlanToServer(
            clientPlanId: plan.id.uuidString,
            rawPlanContent: content,
            raceType: plan.raceTypeRaw,
            raceDate: plan.raceDate,
            raceName: plan.raceName,
            goalTime: plan.goalTime,
            customDistanceKm: plan.customDistanceKm,
            startDate: plan.startDate
        )
        if let ts = result?.updatedAt {
            UserDefaults.standard.set(ts, forKey: lastAppliedKey)
        }
    }

    // MARK: - Apply a server-side edit

    /// Rebuild the local plan from server content, preserving completed-workout
    /// data by calendar date (same approach as PlanEditViewModel.processEditedPlan).
    func applyPendingServerPlan(context: ModelContext) {
        guard let remote = pendingServerPlan,
              let content = remote.rawPlanContent,
              let plan = activeLocalPlan(context: context) else { return }

        let parsedWeeks = PlanParser.parse(
            content: content,
            startDate: plan.startDate,
            raceDate: plan.raceDate,
            appendRaceDay: !plan.isHabitBlock
        )
        guard !parsedWeeks.isEmpty else {
            // Unparseable server content — refuse to wipe the local plan.
            pendingServerPlan = nil
            return
        }

        let calendar = Calendar.current
        var completionData: [DateComponents: Workout] = [:]
        for week in plan.weeks {
            for workout in week.workouts where workout.isCompleted {
                let key = calendar.dateComponents([.year, .month, .day], from: workout.date)
                completionData[key] = workout
            }
        }

        for week in plan.weeks {
            context.delete(week)
        }
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

        plan.rawPlanContent = content
        try? context.save()

        if let ts = remote.updatedAt {
            UserDefaults.standard.set(ts, forKey: lastAppliedKey)
        }
        pendingServerPlan = nil
    }

    func dismissPendingServerPlan() {
        // Remember the dismissed version so we don't re-prompt every foreground.
        if let ts = pendingServerPlan?.updatedAt {
            UserDefaults.standard.set(ts, forKey: lastAppliedKey)
        }
        pendingServerPlan = nil
    }

    // MARK: - Helpers

    private func activeLocalPlan(context: ModelContext) -> TrainingPlan? {
        let descriptor = FetchDescriptor<TrainingPlan>(
            predicate: #Predicate<TrainingPlan> { !$0.isArchived },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor))?.first
    }
}
