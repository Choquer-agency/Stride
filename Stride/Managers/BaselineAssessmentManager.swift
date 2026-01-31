import Foundation
import Combine

/// Manages baseline fitness assessments and determines when they are required
@MainActor
class BaselineAssessmentManager: ObservableObject {
    @Published private(set) var currentAssessment: BaselineAssessment?
    @Published var assessmentRequired: Bool = false
    @Published var requirementReason: String = ""
    
    private let storageManager: StorageManager
    private let hrZonesManager: HeartRateZonesManager
    
    init(storageManager: StorageManager, hrZonesManager: HeartRateZonesManager) {
        self.storageManager = storageManager
        self.hrZonesManager = hrZonesManager
        loadLatestAssessment()
    }
    
    // MARK: - Public Methods
    
    /// Load the most recent baseline assessment
    func loadLatestAssessment() {
        currentAssessment = storageManager.loadLatestBaselineAssessment()
        if let assessment = currentAssessment {
            print("📊 Loaded baseline assessment: VDOT \(assessment.vdot)")
        }
    }
    
    /// Check if baseline needed for goal (STRICT requirements)
    /// - Parameters:
    ///   - goal: The training goal to evaluate
    ///   - workouts: User's workout history
    /// - Returns: True if baseline assessment is required
    func evaluateBaselineRequirement(goal: Goal, workouts: [WorkoutSession]) -> Bool {
        // Check if we already have a recent baseline assessment
        if let assessment = currentAssessment {
            let daysSinceAssessment = Calendar.current.dateComponents([.day], from: assessment.assessmentDate, to: Date()).day ?? 0
            
            // If assessment is less than 90 days old, consider it sufficient
            if daysSinceAssessment < 90 {
                assessmentRequired = false
                requirementReason = ""
                return false
            }
        }
        
        // Look for race-quality effort in recent workout history
        if let bestEffort = VDOTCalculator.findBestRaceEffort(from: workouts) {
            // Check if effort is relevant to goal distance
            let goalDistance = goal.distanceKm ?? 0
            let effortDistance = bestEffort.totalDistanceKm
            
            // Effort should be within ±50% of goal distance
            let minDistance = goalDistance * 0.5
            let maxDistance = goalDistance * 1.5
            
            if effortDistance >= minDistance && effortDistance <= maxDistance {
                // We have a qualifying effort - can auto-calculate
                assessmentRequired = false
                requirementReason = ""
                return false
            }
        }
        
        // No qualifying effort found - require baseline test
        assessmentRequired = true
        requirementReason = """
        To create a realistic training plan, Stride needs to know your current fitness level.
        
        This unlocks:
        • Personalized training paces
        • Accurate race predictions
        • Weekly plan adjustments
        
        It takes 20-40 minutes depending on test distance.
        """
        
        return true
    }
    
    /// Create assessment from manual race result input
    /// - Parameters:
    ///   - distance: Race distance in kilometers
    ///   - time: Time to complete the race
    ///   - goalDistance: Optional goal distance for race pace calculation
    /// - Returns: Created baseline assessment
    func createFromRaceResult(distance: Double, time: TimeInterval, goalDistance: Double?) async throws -> BaselineAssessment {
        // Calculate VDOT from race performance
        let vdot = VDOTCalculator.calculateVDOT(distanceKm: distance, timeSeconds: time)
        
        // Calculate training paces
        let trainingPaces = VDOTCalculator.calculateTrainingPaces(vdot: vdot, goalDistanceKm: goalDistance)
        
        // Create assessment
        let assessment = BaselineAssessment(
            method: .recentRace,
            vdot: vdot,
            trainingPaces: trainingPaces,
            testDistanceKm: distance,
            testTimeSeconds: time
        )
        
        // Save assessment
        try storageManager.saveBaselineAssessment(assessment)
        
        // Update current assessment
        currentAssessment = assessment
        
        // Update HR zones based on VDOT
        updateHeartRateZones(vdot: vdot)
        
        print("📊 Created baseline from race result: VDOT \(vdot)")
        
        return assessment
    }
    
    /// Create assessment from time trial result
    /// - Parameters:
    ///   - distance: Time trial distance in kilometers
    ///   - time: Time to complete the time trial
    ///   - goalDistance: Optional goal distance for race pace calculation
    /// - Returns: Created baseline assessment
    func createFromTimeTrial(distance: Double, time: TimeInterval, goalDistance: Double?) async throws -> BaselineAssessment {
        // Calculate VDOT from time trial performance
        let vdot = VDOTCalculator.calculateVDOT(distanceKm: distance, timeSeconds: time)
        
        // Calculate training paces
        let trainingPaces = VDOTCalculator.calculateTrainingPaces(vdot: vdot, goalDistanceKm: goalDistance)
        
        // Create assessment
        let assessment = BaselineAssessment(
            method: .timeTrial,
            vdot: vdot,
            trainingPaces: trainingPaces,
            testDistanceKm: distance,
            testTimeSeconds: time
        )
        
        // Save assessment
        try storageManager.saveBaselineAssessment(assessment)
        
        // Update current assessment
        currentAssessment = assessment
        
        // Update HR zones based on VDOT
        updateHeartRateZones(vdot: vdot)
        
        print("📊 Created baseline from time trial: VDOT \(vdot)")
        
        return assessment
    }
    
    /// Create assessment from guided test workout
    /// - Parameters:
    ///   - session: Completed workout session from guided test
    ///   - goalDistance: Optional goal distance for race pace calculation
    /// - Returns: Created baseline assessment
    func createFromTestWorkout(session: WorkoutSession, goalDistance: Double?) async throws -> BaselineAssessment {
        // Calculate VDOT from workout performance
        let vdot = VDOTCalculator.calculateVDOT(
            distanceKm: session.totalDistanceKm,
            timeSeconds: session.durationSeconds
        )
        
        // Calculate training paces
        let trainingPaces = VDOTCalculator.calculateTrainingPaces(vdot: vdot, goalDistanceKm: goalDistance)
        
        // Create assessment
        let assessment = BaselineAssessment(
            method: .guidedTest,
            vdot: vdot,
            trainingPaces: trainingPaces,
            testDistanceKm: session.totalDistanceKm,
            testTimeSeconds: session.durationSeconds
        )
        
        // ✅ SAVE THE WORKOUT SESSION FIRST (Fix: baseline test workouts were never saved)
        storageManager.saveWorkout(session)
        print("✅ Saved workout session: \(session.id)")
        
        // Save assessment
        try storageManager.saveBaselineAssessment(assessment)
        
        // Update current assessment
        currentAssessment = assessment
        
        // Update HR zones based on VDOT
        updateHeartRateZones(vdot: vdot)
        
        print("📊 Created baseline from guided test: VDOT \(vdot)")
        
        return assessment
    }
    
    /// Auto-create assessment from detected race-quality workout
    /// - Parameters:
    ///   - session: Workout session that qualifies as race effort
    ///   - goalDistance: Optional goal distance for race pace calculation
    /// - Returns: Created baseline assessment, or nil if workout doesn't qualify
    func createFromWorkout(session: WorkoutSession, goalDistance: Double?) async throws -> BaselineAssessment? {
        // Verify workout qualifies as race effort
        guard VDOTCalculator.isRaceQualityEffort(workout: session) else {
            print("⚠️ Workout does not qualify as race effort")
            return nil
        }
        
        // Calculate VDOT from workout performance
        let vdot = VDOTCalculator.calculateVDOT(
            distanceKm: session.totalDistanceKm,
            timeSeconds: session.durationSeconds
        )
        
        // Calculate training paces
        let trainingPaces = VDOTCalculator.calculateTrainingPaces(vdot: vdot, goalDistanceKm: goalDistance)
        
        // Create assessment
        let assessment = BaselineAssessment(
            method: .autoCalculated,
            vdot: vdot,
            trainingPaces: trainingPaces,
            testDistanceKm: session.totalDistanceKm,
            testTimeSeconds: session.durationSeconds
        )
        
        // Save assessment
        try storageManager.saveBaselineAssessment(assessment)
        
        // Update current assessment
        currentAssessment = assessment
        
        // Update HR zones based on VDOT
        updateHeartRateZones(vdot: vdot)
        
        print("📊 Auto-created baseline from workout: VDOT \(vdot)")
        
        return assessment
    }
    
    /// Provide race time predictions for user feedback
    /// - Parameter vdot: VDOT value to predict from
    /// - Returns: Dictionary of race names to predicted times
    func predictRaceTimes(vdot: Double) -> [String: TimeInterval] {
        return VDOTCalculator.predictRaceTimes(vdot: vdot)
    }
    
    /// Update HR zones based on VDOT (pace-derived, not VO2-derived)
    /// - Parameter vdot: VDOT value to calculate zones from
    func updateHeartRateZones(vdot: Double) {
        // For now, we'll estimate max HR based on VDOT
        // This is a simplified approach - in future could be more sophisticated
        
        // VDOT roughly correlates to fitness level
        // Higher VDOT = potentially higher max HR relative to age-predicted
        
        // We'll use the existing age-based calculation but potentially adjust
        // For v1, we'll keep it simple and not modify HR zones
        // HR zones remain pace-derived through the existing HeartRateZonesManager
        
        print("📊 HR zones remain based on existing age/HRR calculation")
    }
    
    /// Save pace feedback for current assessment
    /// - Parameters:
    ///   - rating: User's feedback rating
    ///   - notes: Optional notes about the paces
    func savePaceFeedback(rating: PaceFeedback.FeedbackRating, notes: String?) async throws {
        guard let assessment = currentAssessment else {
            throw BaselineError.noCurrentAssessment
        }
        
        let feedback = PaceFeedback(
            assessmentId: assessment.id,
            rating: rating,
            notes: notes
        )
        
        try storageManager.savePaceFeedback(assessmentId: assessment.id, feedback: feedback)
        
        print("📊 Saved pace feedback: \(rating.displayName)")
    }
    
    /// Delete a baseline assessment
    /// - Parameter id: Assessment ID to delete
    func deleteAssessment(id: UUID) async throws {
        try storageManager.deleteBaselineAssessment(id: id)
        
        // If we deleted the current assessment, reload latest
        if currentAssessment?.id == id {
            loadLatestAssessment()
        }
    }
    
    /// Get all baseline assessments (for history view)
    func getAllAssessments() -> [BaselineAssessment] {
        return storageManager.loadAllBaselineAssessments()
    }
}

// MARK: - Error Types

enum BaselineError: LocalizedError {
    case noCurrentAssessment
    case invalidWorkout
    case calculationFailed
    
    var errorDescription: String? {
        switch self {
        case .noCurrentAssessment:
            return "No current baseline assessment"
        case .invalidWorkout:
            return "Workout does not qualify for baseline calculation"
        case .calculationFailed:
            return "Failed to calculate baseline fitness"
        }
    }
}
