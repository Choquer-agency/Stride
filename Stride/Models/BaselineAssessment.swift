import Foundation

/// Represents a user's fitness baseline assessment
struct BaselineAssessment: Codable, Identifiable {
    let id: UUID
    let assessmentDate: Date
    let method: AssessmentMethod
    let vdot: Double
    let trainingPaces: TrainingPaces
    
    // Test details (for guided tests and manual inputs)
    var testDistanceKm: Double?
    var testTimeSeconds: Double?
    
    enum AssessmentMethod: String, Codable {
        case recentRace      // Manual race result input
        case timeTrial       // Manual time trial result
        case guidedTest      // In-app guided baseline test
        case garminSync      // Future: Garmin data import
        case autoCalculated  // Detected from workout history
        
        var displayName: String {
            switch self {
            case .recentRace:
                return "Recent Race"
            case .timeTrial:
                return "Time Trial"
            case .guidedTest:
                return "Guided Test"
            case .garminSync:
                return "Garmin Sync"
            case .autoCalculated:
                return "Auto-calculated"
            }
        }
    }
    
    init(
        id: UUID = UUID(),
        assessmentDate: Date = Date(),
        method: AssessmentMethod,
        vdot: Double,
        trainingPaces: TrainingPaces,
        testDistanceKm: Double? = nil,
        testTimeSeconds: Double? = nil
    ) {
        self.id = id
        self.assessmentDate = assessmentDate
        self.method = method
        self.vdot = vdot
        self.trainingPaces = trainingPaces
        self.testDistanceKm = testDistanceKm
        self.testTimeSeconds = testTimeSeconds
    }
    
    /// Formatted test performance for display
    var testPerformanceDescription: String? {
        guard let distance = testDistanceKm, let time = testTimeSeconds else {
            return nil
        }
        
        let distanceStr = String(format: "%.1f km", distance)
        let timeStr = time.toTimeString()
        return "\(distanceStr) in \(timeStr)"
    }
}

/// Training pace zones calculated from VDOT
struct TrainingPaces: Codable {
    // Easy/Recovery runs (range)
    let easy: PaceRange
    
    // Long run pace (slightly faster than easy, range)
    let longRun: PaceRange
    
    // Core training paces (VDOT-derived, single values)
    let threshold: Double       // Tempo runs, cruise intervals (sec/km)
    let interval: Double        // VO2max work (sec/km)
    let repetition: Double      // Speed work (sec/km)
    
    // Goal race pace (conditional, based on user's goal)
    let racePace: Double?       // Only set if goal distance exists (sec/km)
    
    init(
        easy: PaceRange,
        longRun: PaceRange,
        threshold: Double,
        interval: Double,
        repetition: Double,
        racePace: Double? = nil
    ) {
        self.easy = easy
        self.longRun = longRun
        self.threshold = threshold
        self.interval = interval
        self.repetition = repetition
        self.racePace = racePace
    }
    
    /// User-friendly explanation of when to use each pace
    var displayDescription: String {
        return """
        Easy: Recovery runs, easy days
        Long Run: Sunday long runs, aerobic building
        Threshold: Tempo runs, cruise intervals, comfortably hard
        Interval: VO2max work, hard 3-5min efforts
        Repetition: Speed work, short fast reps
        """
    }
}

/// Pace range with min and max values
struct PaceRange: Codable {
    let min: Double  // seconds per km
    let max: Double  // seconds per km
    
    init(min: Double, max: Double) {
        self.min = min
        self.max = max
    }
    
    /// Display range as "min/km - max/km"
    var displayRange: String {
        return "\(min.toPaceString()) - \(max.toPaceString())"
    }
    
    /// Midpoint of the range
    var midpoint: Double {
        return (min + max) / 2.0
    }
}

/// User feedback on training paces (for future adaptive adjustments)
struct PaceFeedback: Codable {
    let assessmentId: UUID
    let feedbackDate: Date
    let rating: FeedbackRating
    let notes: String?
    
    enum FeedbackRating: String, Codable {
        case tooEasy = "too_easy"
        case justRight = "just_right"
        case tooHard = "too_hard"
        
        var displayName: String {
            switch self {
            case .tooEasy:
                return "Too Easy"
            case .justRight:
                return "Just Right"
            case .tooHard:
                return "Too Hard"
            }
        }
    }
    
    init(
        assessmentId: UUID,
        feedbackDate: Date = Date(),
        rating: FeedbackRating,
        notes: String? = nil
    ) {
        self.assessmentId = assessmentId
        self.feedbackDate = feedbackDate
        self.rating = rating
        self.notes = notes
    }
}
