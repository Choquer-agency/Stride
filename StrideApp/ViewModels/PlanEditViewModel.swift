import Foundation
import SwiftUI
import SwiftData

@MainActor
class PlanEditViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var editInstructions: String = ""
    @Published var streamingContent: String = ""
    @Published var isGenerating = false
    @Published var isComplete = false
    @Published var error: String?
    @Published var showError = false

    // MARK: - Dependencies
    let plan: TrainingPlan
    private let apiService = APIService.shared

    // MARK: - Initialization
    init(plan: TrainingPlan) {
        self.plan = plan
    }

    // MARK: - Validation
    var canSubmit: Bool {
        !editInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating
    }

    // MARK: - Edit Plan
    func submitEdit(context: ModelContext) async {
        guard canSubmit else { return }

        isGenerating = true
        streamingContent = ""
        error = nil
        isComplete = false

        let request = APIService.buildEditRequest(from: plan, editInstructions: editInstructions)

        await apiService.editPlan(
            request: request,
            onChunk: { [weak self] chunk in
                self?.streamingContent += chunk
            },
            onComplete: { [weak self] fullContent in
                guard let self = self else { return }
                self.processEditedPlan(content: fullContent, context: context)
            },
            onError: { [weak self] error in
                self?.error = error.localizedDescription
                self?.showError = true
                self?.isGenerating = false
            }
        )
    }

    // MARK: - Process Edited Plan
    private func processEditedPlan(content: String, context: ModelContext) {
        PlanLogger.logRawContent(content)

        let parsedWeeks = PlanParser.parse(
            content: content,
            startDate: plan.startDate,
            raceDate: plan.raceDate
        )

        PlanLogger.logParsedWeeks(parsedWeeks, startDate: plan.startDate, raceDate: plan.raceDate)

        // Remove old weeks (cascade deletes workouts)
        for week in plan.weeks {
            context.delete(week)
        }
        plan.weeks.removeAll()

        // Insert new weeks from edited plan
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
                week.workouts.append(workout)
            }

            plan.weeks.append(week)
        }

        // Update raw content
        plan.rawPlanContent = content

        try? context.save()

        PlanLogger.logPlan(plan)

        isGenerating = false
        isComplete = true
    }
}
