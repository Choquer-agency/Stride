import Foundation

// MARK: - Training Plan Request
struct TrainingPlanRequest: Codable {
    // Goal Information
    let raceType: String
    let raceDate: String
    let raceName: String?
    let goalTime: String?
    let customDistanceKm: Double?
    let terrainType: String?
    let elevationGainM: Int?

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
        case customDistanceKm = "custom_distance_km"
        case terrainType = "terrain_type"
        case elevationGainM = "elevation_gain_m"
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
    let customDistanceKm: Double?
    let startDate: String
    let currentPlanContent: String
    let editInstructions: String

    enum CodingKeys: String, CodingKey {
        case raceType = "race_type"
        case raceDate = "race_date"
        case raceName = "race_name"
        case goalTime = "goal_time"
        case customDistanceKm = "custom_distance_km"
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
    let customDistanceKm: Double?
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
        case customDistanceKm = "custom_distance_km"
        case currentWeeklyMileage = "current_weekly_mileage"
        case fitnessLevel = "fitness_level"
        case completedWorkouts = "completed_workouts"
        case weeksIntoPlan = "weeks_into_plan"
        case totalPlanWeeks = "total_plan_weeks"
        case currentPlanContent = "current_plan_content"
    }
}

// MARK: - Post-Run Coach Request
struct PostRunCoachRequest: Codable {
    let runDate: String
    let runType: String
    let totalDistanceKm: Double
    let totalTime: String
    let avgPace: String
    let kmSplits: [PostRunSplitData]
    let paceConsistencyPct: Double?
    let negativeSplit: Bool
    let avgHr: Int?
    let maxHr: Int?
    let avgCadence: Int?
    let elevationGain: Double?

    let prFlag: Bool
    let prDetail: String?
    let weeklyDistanceKm: Double?
    let weeklyGoalKm: Double?
    let streakDays: Int?
    let monthlyDistanceKm: Double?

    let lastSimilarRunPace: String?
    let lastSimilarRunDate: String?
    let trend: String?

    let tomorrowType: String?
    let tomorrowDistanceKm: Double?
    let tomorrowTargetPace: String?
    let tomorrowNotes: String?

    let athleteName: String
    let habitsToReinforce: String?
    let trainingBlock: String?
    let goalRace: String?

    let prerecordedAlertsDelivered: String?

    enum CodingKeys: String, CodingKey {
        case runDate = "run_date"
        case runType = "run_type"
        case totalDistanceKm = "total_distance_km"
        case totalTime = "total_time"
        case avgPace = "avg_pace"
        case kmSplits = "km_splits"
        case paceConsistencyPct = "pace_consistency_pct"
        case negativeSplit = "negative_split"
        case avgHr = "avg_hr"
        case maxHr = "max_hr"
        case avgCadence = "avg_cadence"
        case elevationGain = "elevation_gain"
        case prFlag = "pr_flag"
        case prDetail = "pr_detail"
        case weeklyDistanceKm = "weekly_distance_km"
        case weeklyGoalKm = "weekly_goal_km"
        case streakDays = "streak_days"
        case monthlyDistanceKm = "monthly_distance_km"
        case lastSimilarRunPace = "last_similar_run_pace"
        case lastSimilarRunDate = "last_similar_run_date"
        case trend
        case tomorrowType = "tomorrow_type"
        case tomorrowDistanceKm = "tomorrow_distance_km"
        case tomorrowTargetPace = "tomorrow_target_pace"
        case tomorrowNotes = "tomorrow_notes"
        case athleteName = "athlete_name"
        case habitsToReinforce = "habits_to_reinforce"
        case trainingBlock = "training_block"
        case goalRace = "goal_race"
        case prerecordedAlertsDelivered = "prerecorded_alerts_delivered"
    }
}

// MARK: - Pre-Run Coach
struct PreRunCoachRequest: Codable {
    let athleteName: String?
    let workoutType: String?
    let workoutTitle: String?
    let targetDistanceKm: Double?
    let targetDurationMinutes: Int?
    let targetPace: String?
    let isFreeRun: Bool
    let goalRace: String?
    let weeksToRace: Int?
    let timeOfDay: String?

    enum CodingKeys: String, CodingKey {
        case athleteName = "athlete_name"
        case workoutType = "workout_type"
        case workoutTitle = "workout_title"
        case targetDistanceKm = "target_distance_km"
        case targetDurationMinutes = "target_duration_minutes"
        case targetPace = "target_pace"
        case isFreeRun = "is_free_run"
        case goalRace = "goal_race"
        case weeksToRace = "weeks_to_race"
        case timeOfDay = "time_of_day"
    }
}

struct PreRunCoachResponse: Codable {
    let text: String
}

extension PreRunCoachRequest {
    /// Stable identity of the workout context for cache matching. If a prefetch
    /// was built with one signature and the real Start Run request has a
    /// different signature, the cache should be ignored (the intro Claude wrote
    /// wouldn't fit the actual workout).
    var cacheSignature: String {
        if isFreeRun {
            return "free_run"
        }
        let parts: [String] = [
            workoutType ?? "_",
            workoutTitle ?? "_",
            targetDistanceKm.map { String(format: "%.1f", $0) } ?? "_",
            targetDurationMinutes.map { String($0) } ?? "_",
            targetPace ?? "_",
        ]
        return parts.joined(separator: "|")
    }
}

struct PostRunSplitData: Codable {
    let kilometer: Int
    let pace: String
    let time: String
    let isFastest: Bool

    enum CodingKeys: String, CodingKey {
        case kilometer, pace, time
        case isFastest = "is_fastest"
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
