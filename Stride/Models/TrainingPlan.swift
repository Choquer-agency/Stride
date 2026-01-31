import Foundation

/// Complete training plan from today to event date
struct TrainingPlan: Codable, Identifiable {
    let id: UUID
    let goalId: UUID
    let createdAt: Date
    var lastModified: Date
    let startDate: Date
    let eventDate: Date
    
    // Plan metadata
    let generationMethod: GenerationMethod
    let totalWeeks: Int
    let weeklyRunDays: Int
    let weeklyGymDays: Int
    let availability: TrainingAvailability  // Snapshot at generation time
    
    // Generation context for explainability (optional for backward compatibility)
    var generationContext: PlanGenerationContext?
    
    // Goal feasibility assessment (from AI generation)
    var goalFeasibility: GoalFeasibility?
    
    // Phases for periodization
    let phases: [TrainingPhase]
    
    // All workouts organized by week
    var weeks: [WeekPlan]
    
    enum GenerationMethod: String, Codable {
        case ruleBased = "rule_based"
        case llmGenerated = "llm_generated"
        case hybrid = "hybrid"
        
        var displayName: String {
            switch self {
            case .ruleBased: return "Rule-Based"
            case .llmGenerated: return "AI Generated"
            case .hybrid: return "AI Enhanced"
            }
        }
    }
    
    // MARK: - Initializer
    
    init(
        id: UUID = UUID(),
        goalId: UUID,
        createdAt: Date = Date(),
        lastModified: Date = Date(),
        startDate: Date,
        eventDate: Date,
        generationMethod: GenerationMethod,
        totalWeeks: Int,
        weeklyRunDays: Int,
        weeklyGymDays: Int,
        availability: TrainingAvailability,
        phases: [TrainingPhase],
        weeks: [WeekPlan],
        generationContext: PlanGenerationContext? = nil,
        goalFeasibility: GoalFeasibility? = nil
    ) {
        self.id = id
        self.goalId = goalId
        self.createdAt = createdAt
        self.lastModified = lastModified
        self.startDate = startDate
        self.eventDate = eventDate
        self.generationMethod = generationMethod
        self.totalWeeks = totalWeeks
        self.weeklyRunDays = weeklyRunDays
        self.weeklyGymDays = weeklyGymDays
        self.availability = availability
        self.phases = phases
        self.weeks = weeks
        self.generationContext = generationContext
        self.goalFeasibility = goalFeasibility
    }
    
    // MARK: - Computed Properties
    
    /// All workouts in the plan
    var allWorkouts: [PlannedWorkout] {
        return weeks.flatMap { $0.workouts }
    }
    
    /// Total planned distance in km
    var totalPlannedKm: Double {
        return weeks.map { $0.totalDistance }.reduce(0, +)
    }
    
    /// Current week (based on today's date)
    var currentWeek: WeekPlan? {
        let today = Date()
        return weeks.first { week in
            week.startDate <= today && week.endDate >= today
        }
    }
    
    /// Today's workout (if any) - excludes rest days
    var todaysWorkout: PlannedWorkout? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        return allWorkouts.first { workout in
            calendar.isDate(workout.date, inSameDayAs: today) && workout.type != .rest
        }
    }
    
    /// Completed workouts count (excludes rest days)
    var completedWorkoutsCount: Int {
        return allWorkouts.filter { $0.completed && $0.type != .rest }.count
    }
    
    /// Total workouts count (excludes rest days)
    var totalWorkoutsCount: Int {
        return allWorkouts.filter { $0.type != .rest }.count
    }
    
    /// Completion percentage
    var completionPercentage: Double {
        guard totalWorkoutsCount > 0 else { return 0 }
        return Double(completedWorkoutsCount) / Double(totalWorkoutsCount) * 100.0
    }
    
    /// Current phase
    var currentPhase: TrainingPhase? {
        guard let currentWeek = currentWeek else { return nil }
        return phases.first { $0.weekRange.contains(currentWeek.weekNumber) }
    }
}

/// Weekly training plan structure
struct WeekPlan: Codable, Identifiable {
    let id: UUID
    let weekNumber: Int
    let startDate: Date
    let endDate: Date
    let phase: TrainingPhase
    let targetWeeklyKm: Double
    var workouts: [PlannedWorkout]
    
    // MARK: - Initializer
    
    init(
        id: UUID = UUID(),
        weekNumber: Int,
        startDate: Date,
        endDate: Date,
        phase: TrainingPhase,
        targetWeeklyKm: Double,
        workouts: [PlannedWorkout]
    ) {
        self.id = id
        self.weekNumber = weekNumber
        self.startDate = startDate
        self.endDate = endDate
        self.phase = phase
        self.targetWeeklyKm = targetWeeklyKm
        self.workouts = workouts
    }
    
    // MARK: - Computed Properties
    
    /// Total distance for this week (from workouts)
    var totalDistance: Double {
        return workouts.compactMap { $0.targetDistanceKm }.reduce(0, +)
    }
    
    /// Number of run workouts this week
    var runWorkoutsCount: Int {
        return workouts.filter { $0.isRunWorkout }.count
    }
    
    /// Number of completed workouts
    var completedCount: Int {
        return workouts.filter { $0.completed }.count
    }
    
    /// Whether this week is in the past
    var isPast: Bool {
        return endDate < Date()
    }
    
    /// Whether this week is current
    var isCurrent: Bool {
        let today = Date()
        return startDate <= today && endDate >= today
    }
    
    /// Whether this week is in the future
    var isFuture: Bool {
        return startDate > Date()
    }
}

/// Training phase with periodization
struct TrainingPhase: Codable, Equatable {
    let name: String
    let weekRange: ClosedRange<Int>
    let focus: String
    let description: String
    
    init(name: String, weekRange: ClosedRange<Int>, focus: String, description: String) {
        self.name = name
        self.weekRange = weekRange
        self.focus = focus
        self.description = description
    }
    
    // MARK: - Predefined Phases
    
    static func baseBuilding(weeks: ClosedRange<Int>) -> TrainingPhase {
        return TrainingPhase(
            name: "Base Building",
            weekRange: weeks,
            focus: "Aerobic Foundation",
            description: "Focus on easy-paced running to build endurance and establish a solid aerobic base."
        )
    }
    
    static func buildUp(weeks: ClosedRange<Int>) -> TrainingPhase {
        return TrainingPhase(
            name: "Build Up",
            weekRange: weeks,
            focus: "Volume & Intensity",
            description: "Increase weekly mileage and introduce tempo runs and intervals to build fitness."
        )
    }
    
    static func peakTraining(weeks: ClosedRange<Int>) -> TrainingPhase {
        return TrainingPhase(
            name: "Peak Training",
            weekRange: weeks,
            focus: "Race-Specific Work",
            description: "Maximum training load with race-pace work and goal-specific workouts."
        )
    }
    
    static func taper(weeks: ClosedRange<Int>) -> TrainingPhase {
        return TrainingPhase(
            name: "Taper",
            weekRange: weeks,
            focus: "Recovery & Sharpening",
            description: "Reduce volume while maintaining intensity to arrive at the race fresh and strong."
        )
    }
    
    // MARK: - Codable for ClosedRange
    
    enum CodingKeys: String, CodingKey {
        case name, focus, description
        case weekRangeLowerBound
        case weekRangeUpperBound
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        focus = try container.decode(String.self, forKey: .focus)
        description = try container.decode(String.self, forKey: .description)
        
        let lowerBound = try container.decode(Int.self, forKey: .weekRangeLowerBound)
        let upperBound = try container.decode(Int.self, forKey: .weekRangeUpperBound)
        weekRange = lowerBound...upperBound
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(focus, forKey: .focus)
        try container.encode(description, forKey: .description)
        try container.encode(weekRange.lowerBound, forKey: .weekRangeLowerBound)
        try container.encode(weekRange.upperBound, forKey: .weekRangeUpperBound)
    }
}
