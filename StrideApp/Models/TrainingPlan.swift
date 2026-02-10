import Foundation
import SwiftData

@Model
final class TrainingPlan {
    // MARK: - Core Properties
    var id: UUID
    var createdAt: Date
    
    // MARK: - Goal Information
    var raceTypeRaw: String
    var raceDate: Date
    var raceName: String?
    var goalTime: String?
    
    // MARK: - Fitness Info (stored for reference)
    var currentWeeklyMileage: Int
    var longestRecentRun: Int
    var fitnessLevelRaw: String
    
    // MARK: - Plan Configuration
    var startDate: Date
    var planModeRaw: String?
    
    // MARK: - Raw Plan Content (from AI)
    var rawPlanContent: String?

    // MARK: - Archive Properties
    var isArchived: Bool = false
    var archivedAt: Date?
    var archiveReasonRaw: String?
    
    // MARK: - Relationships
    @Relationship(deleteRule: .cascade, inverse: \Week.plan)
    var weeks: [Week]
    
    // MARK: - Computed Properties
    var raceType: RaceType {
        get { RaceType(rawValue: raceTypeRaw) ?? .marathon }
        set { raceTypeRaw = newValue.rawValue }
    }
    
    var fitnessLevel: FitnessLevel {
        get { FitnessLevel(rawValue: fitnessLevelRaw) ?? .intermediate }
        set { fitnessLevelRaw = newValue.rawValue }
    }
    
    var planMode: PlanMode? {
        get { planModeRaw.flatMap { PlanMode(rawValue: $0) } }
        set { planModeRaw = newValue?.rawValue }
    }

    var archiveReason: ArchiveReason? {
        get { archiveReasonRaw.flatMap { ArchiveReason(rawValue: $0) } }
        set { archiveReasonRaw = newValue?.rawValue }
    }
    
    var sortedWeeks: [Week] {
        weeks.sorted { $0.weekNumber < $1.weekNumber }
    }
    
    var totalWeeks: Int {
        weeks.count
    }
    
    var completedWorkouts: Int {
        weeks.flatMap { $0.workouts }.filter { $0.isCompleted }.count
    }
    
    var totalWorkouts: Int {
        weeks.flatMap { $0.workouts }.filter { $0.workoutType != .rest }.count
    }
    
    var completionProgress: Double? {
        guard totalWorkouts > 0 else { return nil }
        return Double(completedWorkouts) / Double(totalWorkouts)
    }
    
    var daysUntilRace: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: raceDate).day ?? 0
    }
    
    var currentWeek: Week? {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        
        return weeks.first { week in
            guard let firstWorkout = week.sortedWorkouts.first,
                  let lastWorkout = week.sortedWorkouts.last else { return false }
            
            let weekStart = calendar.startOfDay(for: firstWorkout.date)
            let weekEnd = calendar.startOfDay(for: lastWorkout.date)
            
            return todayStart >= weekStart && todayStart <= weekEnd
        }
    }
    
    // MARK: - Initializer
    init(
        raceType: RaceType,
        raceDate: Date,
        raceName: String? = nil,
        goalTime: String? = nil,
        currentWeeklyMileage: Int,
        longestRecentRun: Int,
        fitnessLevel: FitnessLevel,
        startDate: Date,
        planMode: PlanMode? = nil
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.raceTypeRaw = raceType.rawValue
        self.raceDate = raceDate
        self.raceName = raceName
        self.goalTime = goalTime
        self.currentWeeklyMileage = currentWeeklyMileage
        self.longestRecentRun = longestRecentRun
        self.fitnessLevelRaw = fitnessLevel.rawValue
        self.startDate = startDate
        self.planModeRaw = planMode?.rawValue
        self.weeks = []
    }
}
