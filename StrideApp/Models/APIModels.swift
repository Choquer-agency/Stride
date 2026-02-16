import Foundation

// MARK: - Training Plan Request
struct TrainingPlanRequest: Codable {
    // Goal Information
    let raceType: String
    let raceDate: String
    let raceName: String?
    let goalTime: String?
    
    // Current Fitness
    let currentWeeklyMileage: Int
    let longestRecentRun: Int
    let recentRaceTimes: String?
    let recentRuns: String?
    let fitnessLevel: String
    
    // Schedule Constraints
    let startDate: String
    let restDays: [String]
    let longRunDay: String
    let doubleDaysAllowed: Bool
    let crossTrainingDays: [String]?
    let runningDaysPerWeek: Int
    let gymDaysPerWeek: Int
    
    // Running History
    let yearsRunning: Int
    let previousInjuries: String?
    let previousExperience: String?
    
    // Plan Mode (after conflict resolution)
    let planMode: String?
    let recommendedGoalTime: String?
    
    enum CodingKeys: String, CodingKey {
        case raceType = "race_type"
        case raceDate = "race_date"
        case raceName = "race_name"
        case goalTime = "goal_time"
        case currentWeeklyMileage = "current_weekly_mileage"
        case longestRecentRun = "longest_recent_run"
        case recentRaceTimes = "recent_race_times"
        case recentRuns = "recent_runs"
        case fitnessLevel = "fitness_level"
        case startDate = "start_date"
        case restDays = "rest_days"
        case longRunDay = "long_run_day"
        case doubleDaysAllowed = "double_days_allowed"
        case crossTrainingDays = "cross_training_days"
        case runningDaysPerWeek = "running_days_per_week"
        case gymDaysPerWeek = "gym_days_per_week"
        case yearsRunning = "years_running"
        case previousInjuries = "previous_injuries"
        case previousExperience = "previous_experience"
        case planMode = "plan_mode"
        case recommendedGoalTime = "recommended_goal_time"
    }
}

// MARK: - Conflict Analysis Response
struct ConflictAnalysisResponse: Codable {
    let hasConflicts: Bool
    let conflicts: [DetectedConflict]
    let originalGoalTime: String?
    let recommendedGoalTime: String?
    let recommendationSummary: String?
    
    enum CodingKeys: String, CodingKey {
        case hasConflicts = "has_conflicts"
        case conflicts
        case originalGoalTime = "original_goal_time"
        case recommendedGoalTime = "recommended_goal_time"
        case recommendationSummary = "recommendation_summary"
    }
}

// MARK: - Detected Conflict
struct DetectedConflict: Codable, Identifiable {
    var id: String { title }
    
    let conflictType: String
    let riskLevel: String
    let title: String
    let description: String
    let recommendation: String
    
    enum CodingKeys: String, CodingKey {
        case conflictType = "conflict_type"
        case riskLevel = "risk_level"
        case title
        case description
        case recommendation
    }
    
    var riskLevelEnum: RiskLevel {
        RiskLevel(rawValue: riskLevel) ?? .medium
    }
    
    var conflictTypeEnum: ConflictType {
        ConflictType(rawValue: conflictType) ?? .goalVsFitness
    }
}

// MARK: - Plan Edit Request
struct PlanEditRequest: Codable {
    let raceType: String
    let raceDate: String
    let raceName: String?
    let goalTime: String?
    let startDate: String
    let currentPlanContent: String
    let editInstructions: String

    enum CodingKeys: String, CodingKey {
        case raceType = "race_type"
        case raceDate = "race_date"
        case raceName = "race_name"
        case goalTime = "goal_time"
        case startDate = "start_date"
        case currentPlanContent = "current_plan_content"
        case editInstructions = "edit_instructions"
    }
}

// MARK: - Completed Workout Data (for performance analysis)
struct CompletedWorkoutData: Codable {
    let date: String
    let workoutType: String
    let plannedDistanceKm: Double?
    let actualDistanceKm: Double?
    let plannedPaceDescription: String?
    let actualAvgPaceSecPerKm: Double?
    let completionScore: Int?
    let feedbackRating: Int?

    enum CodingKeys: String, CodingKey {
        case date
        case workoutType = "workout_type"
        case plannedDistanceKm = "planned_distance_km"
        case actualDistanceKm = "actual_distance_km"
        case plannedPaceDescription = "planned_pace_description"
        case actualAvgPaceSecPerKm = "actual_avg_pace_sec_per_km"
        case completionScore = "completion_score"
        case feedbackRating = "feedback_rating"
    }
}

// MARK: - Performance Analysis Request
struct PerformanceAnalysisRequest: Codable {
    let raceType: String
    let raceDate: String
    let startDate: String
    let goalTime: String?
    let currentWeeklyMileage: Int
    let fitnessLevel: String
    let completedWorkouts: [CompletedWorkoutData]
    let weeksIntoPlan: Int
    let totalPlanWeeks: Int
    let currentPlanContent: String

    enum CodingKeys: String, CodingKey {
        case raceType = "race_type"
        case raceDate = "race_date"
        case startDate = "start_date"
        case goalTime = "goal_time"
        case currentWeeklyMileage = "current_weekly_mileage"
        case fitnessLevel = "fitness_level"
        case completedWorkouts = "completed_workouts"
        case weeksIntoPlan = "weeks_into_plan"
        case totalPlanWeeks = "total_plan_weeks"
        case currentPlanContent = "current_plan_content"
    }
}

// MARK: - Stream Chunk
struct StreamChunk: Codable {
    let content: String?
    let done: Bool?
    let error: String?
}

// MARK: - API Error
struct APIError: Codable {
    let detail: String
}
