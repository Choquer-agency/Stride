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
        // Plan workout dates are stored as UTC instants for their scheduled
        // calendar day. Travelling west must not move a Monday to Sunday.
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        
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
    
    /// Monday 00:00 of the calendar week this training week occupies.
    /// Anchored to the Monday containing the earliest workout — not to the
    /// first/last workout dates themselves — so a session moved to another
    /// day (flexible week) never shrinks the range and drops a Sunday.
    var mondayStart: Date? {
        guard let first = sortedWorkouts.first?.date else { return nil }
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        var utc = calendar
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = utc.dateComponents([.year, .month, .day], from: first)
        guard let localDay = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) else { return nil }
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: localDay)
        return calendar.date(from: comps)
    }

    var isCurrentWeek: Bool {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        guard let weekStart = mondayStart,
              let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else { return false }
        return todayStart >= weekStart && todayStart <= weekEnd
    }
    
    var isPastWeek: Bool {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        guard let last = sortedWorkouts.last?.date else { return false }
        var utc = calendar
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = utc.dateComponents([.year, .month, .day], from: last)
        guard let localDay = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) else { return false }
        return todayStart > calendar.startOfDay(for: localDay)
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
