import Foundation
import SwiftData

@Model
final class Week {
    // MARK: - Properties
    var id: UUID
    var weekNumber: Int
    var theme: String?  // e.g., "Base Building", "Peak Week", "Taper"
    var notes: String?
    
    // MARK: - Relationships
    var plan: TrainingPlan?
    
    @Relationship(deleteRule: .cascade, inverse: \Workout.week)
    var workouts: [Workout]
    
    // MARK: - Computed Properties
    var sortedWorkouts: [Workout] {
        workouts.sorted { $0.date < $1.date }
    }
    
    var dateRange: String {
        guard let first = sortedWorkouts.first?.date,
              let last = sortedWorkouts.last?.date else {
            return ""
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        
        return "\(formatter.string(from: first)) - \(formatter.string(from: last))"
    }
    
    var totalDistance: Double {
        workouts.reduce(0) { $0 + ($1.distanceKm ?? 0) }
    }
    
    var completedWorkouts: Int {
        workouts.filter { $0.isCompleted }.count
    }
    
    var activeWorkouts: Int {
        workouts.filter { $0.workoutType != .rest }.count
    }
    
    var completionProgress: Double {
        guard activeWorkouts > 0 else { return 0 }
        let completedActive = workouts.filter { $0.isCompleted && $0.workoutType != .rest }.count
        return Double(completedActive) / Double(activeWorkouts)
    }
    
    var isCurrentWeek: Bool {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        guard let first = sortedWorkouts.first?.date,
              let last = sortedWorkouts.last?.date else { return false }
        let weekStart = calendar.startOfDay(for: first)
        let weekEnd = calendar.startOfDay(for: last)
        return todayStart >= weekStart && todayStart <= weekEnd
    }
    
    var isPastWeek: Bool {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        guard let last = sortedWorkouts.last?.date else { return false }
        return todayStart > calendar.startOfDay(for: last)
    }
    
    var isRaceWeek: Bool {
        workouts.contains { $0.workoutType == .race }
    }
    
    /// Long run = longest run in a given week (not hardcoded to Sunday)
    var longRun: Workout? {
        workouts
            .filter { $0.workoutType != .rest && $0.workoutType != .gym && $0.workoutType != .crossTraining }
            .max(by: { ($0.distanceKm ?? 0) < ($1.distanceKm ?? 0) })
    }
    
    var longRunDistance: Double {
        longRun?.distanceKm ?? 0
    }
    
    // MARK: - Initializer
    init(weekNumber: Int, theme: String? = nil, notes: String? = nil) {
        self.id = UUID()
        self.weekNumber = weekNumber
        self.theme = theme
        self.notes = notes
        self.workouts = []
    }
}
