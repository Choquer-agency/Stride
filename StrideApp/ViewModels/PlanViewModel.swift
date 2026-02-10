import Foundation
import SwiftUI
import SwiftData

@MainActor
class PlanViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var expandedWeeks: Set<Int> = []
    @Published var selectedWorkout: Workout?
    @Published var showWorkoutDetail = false
    
    // MARK: - Dependencies
    let plan: TrainingPlan
    
    // MARK: - Initialization
    init(plan: TrainingPlan) {
        self.plan = plan
        
        // Auto-expand current week
        if let currentWeek = plan.currentWeek {
            expandedWeeks.insert(currentWeek.weekNumber)
        } else {
            // If no current week, expand first week
            if let firstWeek = plan.sortedWeeks.first {
                expandedWeeks.insert(firstWeek.weekNumber)
            }
        }
    }
    
    // MARK: - Week Management
    func isExpanded(_ week: Week) -> Bool {
        expandedWeeks.contains(week.weekNumber)
    }
    
    func toggleWeek(_ week: Week) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            if expandedWeeks.contains(week.weekNumber) {
                expandedWeeks.remove(week.weekNumber)
            } else {
                expandedWeeks.insert(week.weekNumber)
            }
        }
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    func expandAll() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            expandedWeeks = Set(plan.sortedWeeks.map { $0.weekNumber })
        }
    }
    
    func collapseAll() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            expandedWeeks.removeAll()
        }
    }
    
    // MARK: - Workout Management
    func selectWorkout(_ workout: Workout) {
        selectedWorkout = workout
        showWorkoutDetail = true
    }
    
    func toggleWorkoutCompletion(_ workout: Workout, context: ModelContext) {
        workout.toggleCompletion()
        
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(workout.isCompleted ? .success : .warning)
        
        // Save changes
        try? context.save()
    }
    
    // MARK: - Stats
    var overallProgress: Double {
        plan.completionProgress ?? 0
    }
    
    var totalDistance: Double {
        plan.sortedWeeks.reduce(0) { $0 + $1.totalDistance }
    }
    
    var completedWorkoutsCount: Int {
        plan.completedWorkouts
    }
    
    var remainingWorkoutsCount: Int {
        plan.totalWorkouts - plan.completedWorkouts
    }
}
