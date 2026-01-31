import Foundation
import Combine

/// Manages the active training goal and provides UI-ready state
@MainActor
class GoalManager: ObservableObject {
    @Published private(set) var activeGoal: Goal?
    
    private let storageManager: StorageManager
    
    init(storageManager: StorageManager) {
        self.storageManager = storageManager
        loadActiveGoal()
    }
    
    // MARK: - Public Methods
    
    /// Load the active goal from storage
    func loadActiveGoal() {
        print("📌 Loading active goal from storage...")
        
        guard let activeId = storageManager.loadActiveGoalId() else {
            activeGoal = nil
            print("📌 No active goal ID found in storage")
            return
        }
        
        print("📌 Found active goal ID: \(activeId)")
        
        guard let goal = storageManager.loadGoal(id: activeId) else {
            activeGoal = nil
            print("⚠️ Active goal ID exists but goal data not found - storage may be corrupted")
            // Attempt to clear corrupted state
            try? storageManager.setActiveGoal(id: nil)
            return
        }
        
        activeGoal = goal
        print("📌 Successfully loaded active goal: \(goal.displayName)")
    }
    
    /// Set a new goal (deactivates any existing goal)
    func setGoal(_ goal: Goal) async throws {
        // Ensure only one active goal
        var newGoal = goal
        newGoal.isActive = true
        
        // Save the goal
        try storageManager.saveGoal(newGoal)
        
        // Set as active
        try storageManager.setActiveGoal(id: newGoal.id)
        
        // Update published property
        activeGoal = newGoal
        
        print("🎯 Set new goal: \(newGoal.displayName)")
    }
    
    /// Update an existing goal
    func updateGoal(_ goal: Goal) async throws {
        // Validate it's the active goal
        guard goal.id == activeGoal?.id else {
            throw GoalError.notActiveGoal
        }
        
        // Save updated goal
        try storageManager.saveGoal(goal)
        
        // Update published property
        activeGoal = goal
        
        print("🎯 Updated goal: \(goal.displayName)")
    }
    
    /// Update only the target time of the active goal
    func updateGoalTargetTime(_ newTargetTime: TimeInterval) async throws {
        guard var goal = activeGoal else {
            throw GoalError.noActiveGoal
        }
        
        // Update target time
        goal = Goal(
            id: goal.id,
            type: goal.type,
            targetTime: newTargetTime,
            eventDate: goal.eventDate,
            createdAt: goal.createdAt,
            isActive: goal.isActive,
            title: goal.title,
            notes: goal.notes,
            raceDistance: goal.raceDistance,
            customDistanceKm: goal.customDistanceKm,
            baselineStatus: goal.baselineStatus,
            baselineAssessmentId: goal.baselineAssessmentId,
            trainingPaces: goal.trainingPaces,
            estimatedVDOT: goal.estimatedVDOT
        )
        
        try await updateGoal(goal)
        
        print("🎯 Updated goal target time to: \(goal.formattedTargetTime ?? "N/A")")
    }
    
    /// Deactivate the current goal (soft delete - keeps in storage)
    func deactivateGoal() async throws {
        guard activeGoal != nil else {
            throw GoalError.noActiveGoal
        }
        
        // Clear active goal
        try storageManager.setActiveGoal(id: nil)
        
        // Update published property
        activeGoal = nil
        
        print("🎯 Deactivated goal")
    }
    
    /// Delete the current goal entirely
    func deleteGoal() async throws {
        guard let goal = activeGoal else {
            throw GoalError.noActiveGoal
        }
        
        // Delete from storage
        try storageManager.deleteGoal(id: goal.id)
        
        // Update published property
        activeGoal = nil
        
        print("🎯 Deleted goal: \(goal.displayName)")
    }
    
    // MARK: - Helper Properties
    
    /// Whether there is an active goal
    var hasActiveGoal: Bool {
        return activeGoal != nil
    }
    
    /// Days remaining until goal (if active)
    var daysRemaining: Int? {
        return activeGoal?.daysRemaining
    }
    
    /// Weeks remaining until goal (if active)
    var weeksRemaining: Int? {
        return activeGoal?.weeksRemaining
    }
    
    // MARK: - Baseline Integration (Future)
    
    /// Update goal with baseline assessment results
    /// This method will be used when baseline assessment is completed for a goal
    func updateGoalWithBaseline(assessmentId: UUID, vdot: Double, trainingPaces: TrainingPaces) async throws {
        guard var goal = activeGoal else {
            throw GoalError.noActiveGoal
        }
        
        goal.baselineAssessmentId = assessmentId
        goal.estimatedVDOT = vdot
        goal.trainingPaces = trainingPaces
        goal.baselineStatus = .sufficient
        
        try await updateGoal(goal)
        
        print("🎯 Updated goal with baseline: VDOT \(vdot)")
    }
    
    /// Check if goal needs baseline assessment
    /// This method will be called when a goal is created or becomes active
    func checkBaselineRequirement(workouts: [WorkoutSession]) -> Bool {
        guard let goal = activeGoal else { return false }
        return goal.needsBaselineAssessment
    }
}

// MARK: - Error Types

enum GoalError: LocalizedError {
    case noActiveGoal
    case notActiveGoal
    case validationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noActiveGoal:
            return "No active goal"
        case .notActiveGoal:
            return "Goal is not the active goal"
        case .validationFailed(let message):
            return message
        }
    }
}
