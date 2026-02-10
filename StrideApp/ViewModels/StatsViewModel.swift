import Foundation
import SwiftUI
import SwiftData

// MARK: - Weekly Distance Stats
struct WeeklyDistanceStats {
    let completed: Double    // Sum of completed workout distances
    let planned: Double      // Sum of all planned workout distances
    let isNoPlanMode: Bool   // True if this is standalone running (no plan)
    
    init(completed: Double, planned: Double, isNoPlanMode: Bool = false) {
        self.completed = completed
        self.planned = planned
        self.isNoPlanMode = isNoPlanMode
    }
    
    var percentage: Double {
        guard planned > 0 else { return 0 }
        return (completed / planned) * 100
    }
    
    var displayText: String {
        if isNoPlanMode {
            return "\(Int(completed)) km"
        }
        return "\(Int(completed)) / \(Int(planned)) km"
    }
    
    var percentageText: String {
        if isNoPlanMode {
            return "this week"
        }
        return "\(Int(percentage))% completed"
    }
}

// MARK: - Milestone Record
struct MilestoneRecord {
    let timeString: String   // e.g. "22:15" or "1:45:00"
    let date: Date           // when this record was set
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - Stats View Model
@MainActor
class StatsViewModel: ObservableObject {
    let plan: TrainingPlan
    var additionalWorkouts: [Workout] = []
    
    init(plan: TrainingPlan, additionalWorkouts: [Workout] = []) {
        self.plan = plan
        self.additionalWorkouts = additionalWorkouts
    }
    
    // MARK: - Static Helper for No-Plan Mode
    /// Calculate weekly distance for the current calendar week (Sunday-Saturday) from any workouts
    static func weeklyDistanceForCurrentCalendarWeek(workouts: [Workout]) -> WeeklyDistanceStats {
        let calendar = Calendar.current
        let today = Date()
        
        // Find Sunday of current week (week starts on Sunday)
        let weekday = calendar.component(.weekday, from: today) // 1 = Sunday, 7 = Saturday
        let daysFromSunday = (weekday == 1) ? 0 : weekday - 1
        guard let sunday = calendar.date(byAdding: .day, value: -daysFromSunday, to: today),
              let saturday = calendar.date(byAdding: .day, value: 6, to: sunday) else {
            return WeeklyDistanceStats(completed: 0, planned: 0, isNoPlanMode: true)
        }
        
        // Normalize to start of day for comparison
        let sundayStart = calendar.startOfDay(for: sunday)
        let saturdayEnd = calendar.startOfDay(for: saturday).addingTimeInterval(86400 - 1) // End of Saturday
        
        // Filter workouts in current calendar week (Sunday-Saturday)
        let weekWorkouts = workouts.filter { workout in
            let workoutDate = calendar.startOfDay(for: workout.date)
            return workoutDate >= sundayStart && workoutDate <= saturdayEnd
        }
        
        // Sum completed running distances (prefer actual treadmill data)
        let completed = weekWorkouts
            .filter { $0.isCompleted && $0.workoutType != .rest }
            .reduce(0.0) { $0 + ($1.effectiveDistanceKm ?? 0) }
        
        return WeeklyDistanceStats(completed: completed, planned: 0, isNoPlanMode: true)
    }
    
    // MARK: - Weekly Stats (Completed vs Planned)
    var currentWeekStats: WeeklyDistanceStats {
        // Try to get current week, or fall back to nearest week
        let targetWeek: Week? = {
            if let currentWeek = plan.currentWeek {
                return currentWeek
            }
            // If no current week, find the week closest to today
            let today = Date()
            let sortedWeeks = plan.sortedWeeks
            guard !sortedWeeks.isEmpty else { return nil }
            
            // Find the week with the closest start date to today
            return sortedWeeks.min { week1, week2 in
                let date1 = week1.sortedWorkouts.first?.date ?? Date.distantFuture
                let date2 = week2.sortedWorkouts.first?.date ?? Date.distantFuture
                return abs(date1.timeIntervalSince(today)) < abs(date2.timeIntervalSince(today))
            }
        }()
        
        guard let week = targetWeek else {
            #if DEBUG
            print("⚠️ StatsViewModel: No week found for currentWeekStats")
            #endif
            return WeeklyDistanceStats(completed: 0, planned: 0)
        }
        
        let completed = week.workouts
            .filter { $0.isCompleted && $0.workoutType != .rest }
            .reduce(0.0) { $0 + ($1.effectiveDistanceKm ?? 0) }
        
        let planned = week.workouts
            .filter { $0.workoutType != .rest }
            .reduce(0.0) { $0 + ($1.distanceKm ?? 0) }
        
        #if DEBUG
        if planned == 0 {
            let workoutsWithoutDistance = week.workouts.filter { $0.workoutType != .rest && $0.distanceKm == nil }
            if !workoutsWithoutDistance.isEmpty {
                print("⚠️ StatsViewModel: Week \(week.weekNumber) has \(workoutsWithoutDistance.count) workouts without distance")
            }
        }
        #endif
        
        return WeeklyDistanceStats(completed: completed, planned: planned)
    }
    
    var previousWeekStats: WeeklyDistanceStats {
        guard let currentWeek = plan.currentWeek,
              let currentWeekIndex = plan.sortedWeeks.firstIndex(where: { $0.id == currentWeek.id }),
              currentWeekIndex > 0 else {
            return WeeklyDistanceStats(completed: 0, planned: 0)
        }
        
        let previousWeek = plan.sortedWeeks[currentWeekIndex - 1]
        
        let completed = previousWeek.workouts
            .filter { $0.isCompleted && $0.workoutType != .rest }
            .reduce(0.0) { $0 + ($1.effectiveDistanceKm ?? 0) }
        
        let planned = previousWeek.workouts
            .filter { $0.workoutType != .rest }
            .reduce(0.0) { $0 + ($1.distanceKm ?? 0) }
        
        return WeeklyDistanceStats(completed: completed, planned: planned)
    }
    
    var weeklyDistanceChange: Double {
        let current = currentWeekStats.completed
        let previous = previousWeekStats.completed
        
        guard previous > 0 else { return 0 }
        return ((current - previous) / previous) * 100
    }
    
    // MARK: - Rolling Average
    var rolling4WeekAverage: Double {
        // Combine plan workouts with any additional (free run) workouts
        let planWorkouts = plan.weeks.flatMap { $0.workouts }
        let planWorkoutIDs = Set(planWorkouts.map { $0.id })
        let combined = planWorkouts + additionalWorkouts.filter { !planWorkoutIDs.contains($0.id) }
        return Self.rolling4WeekAverage(from: combined)
    }
    
    /// Calculate 4-week rolling average from a flat list of workouts (plan-independent)
    static func rolling4WeekAverage(from workouts: [Workout]) -> Double {
        let calendar = Calendar.current
        let today = Date()
        
        // Build 4 calendar week buckets ending with the current week
        var weeklyDistances: [Double] = []
        for weeksBack in 0..<4 {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -weeksBack, to: today) else { continue }
            guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: weekStart) else { continue }
            
            let distance = workouts
                .filter { workout in
                    guard workout.isCompleted, workout.workoutType != .rest else { return false }
                    let d = calendar.startOfDay(for: workout.date)
                    return d >= weekInterval.start && d < weekInterval.end
                }
                .reduce(0.0) { $0 + ($1.effectiveDistanceKm ?? 0) }
            
            weeklyDistances.append(distance)
        }
        
        guard !weeklyDistances.isEmpty else { return 0 }
        return weeklyDistances.reduce(0, +) / Double(weeklyDistances.count)
    }
    
    // MARK: - Year-to-Date
    var yearToDateDistance: Double {
        let planWorkouts = plan.weeks.flatMap { $0.workouts }
        let planWorkoutIDs = Set(planWorkouts.map { $0.id })
        let combined = planWorkouts + additionalWorkouts.filter { !planWorkoutIDs.contains($0.id) }
        return Self.yearToDateDistance(from: combined)
    }
    
    /// Calculate year-to-date distance from a flat list of workouts (plan-independent)
    static func yearToDateDistance(from workouts: [Workout]) -> Double {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        
        return workouts
            .filter { workout in
                guard let completedAt = workout.completedAt ?? (workout.isCompleted ? workout.date : nil) else {
                    return false
                }
                return calendar.component(.year, from: completedAt) == currentYear
            }
            .reduce(0.0) { $0 + ($1.effectiveDistanceKm ?? 0) }
    }
    
    // MARK: - Streak
    var consecutiveWeeksCompleted: Int {
        let sortedWeeks = plan.sortedWeeks
        var streak = 0
        
        // Count backwards from most recent week
        for week in sortedWeeks.reversed() {
            // Week is considered "completed" if >= 80% adherence
            if week.completionProgress >= 0.8 {
                streak += 1
            } else {
                break
            }
        }
        
        return streak
    }
    
    // MARK: - Composition (using IntensityBucket)
    func intensityBreakdown(for week: Week) -> [IntensityBucket: Double] {
        var breakdown: [IntensityBucket: Double] = [
            .easy: 0,
            .moderate: 0,
            .hard: 0
        ]
        
        for workout in week.workouts {
            guard let intensity = workout.workoutType.runIntensity,
                  let distance = workout.distanceKm else { continue }
            
            let bucket = intensity.displayBucket
            breakdown[bucket] = (breakdown[bucket] ?? 0) + distance
        }
        
        return breakdown
    }
    
    // MARK: - Long Runs (longest run per week, not just Sunday)
    /// Long run progression excluding race workouts (shows training long runs only)
    var longRunProgression: [(weekNumber: Int, distance: Double)] {
        plan.sortedWeeks.map { week in
            let trainingLongRunDistance = week.workouts
                .filter { $0.workoutType != .rest && $0.workoutType != .gym && $0.workoutType != .crossTraining && $0.workoutType != .race }
                .max(by: { ($0.distanceKm ?? 0) < ($1.distanceKm ?? 0) })?
                .distanceKm ?? 0
            return (weekNumber: week.weekNumber, distance: trainingLongRunDistance)
        }
    }
    
    /// Longest training run (excludes race workouts)
    var longestRunEver: Double {
        longRunProgression.map { $0.distance }.max() ?? 0
    }
    
    /// Peak training week (excludes race week)
    var peakLongRunWeek: Int? {
        guard let maxDistance = longRunProgression.map({ $0.distance }).max(),
              maxDistance > 0 else { return nil }
        
        return longRunProgression.first { $0.distance == maxDistance }?.weekNumber
    }
    
    // MARK: - Adherence
    var last4WeeksAdherence: Double {
        let sortedWeeks = plan.sortedWeeks
        let last4Weeks = Array(sortedWeeks.suffix(4))
        
        guard !last4Weeks.isEmpty else { return 0 }
        
        let totalAdherence = last4Weeks.reduce(0.0) { $0 + $1.completionProgress }
        return (totalAdherence / Double(last4Weeks.count)) * 100
    }
    
    var overallPlanAdherence: Double {
        let sortedWeeks = plan.sortedWeeks
        guard !sortedWeeks.isEmpty else { return 0 }
        
        let totalAdherence = sortedWeeks.reduce(0.0) { $0 + $1.completionProgress }
        return (totalAdherence / Double(sortedWeeks.count)) * 100
    }
    
    // MARK: - Strength
    var strengthSessionsThisWeek: Int {
        plan.currentWeek?.workouts.filter { $0.workoutType == .gym && $0.isCompleted }.count ?? 0
    }
    
    var strengthSessionsTotal: Int {
        plan.weeks.flatMap { $0.workouts }
            .filter { $0.workoutType == .gym && $0.isCompleted }
            .count
    }
    
    var strengthWeeksWithSession: (completed: Int, total: Int) {
        let sortedWeeks = plan.sortedWeeks
        let weeksWithSession = sortedWeeks.filter { week in
            week.workouts.contains { $0.workoutType == .gym && $0.isCompleted }
        }
        
        return (completed: weeksWithSession.count, total: sortedWeeks.count)
    }
    
    var strengthIsOnTrack: Bool {
        let sortedWeeks = plan.sortedWeeks
        let last4Weeks = Array(sortedWeeks.suffix(4))
        
        guard last4Weeks.count >= 4 else { return false }
        
        let weeksWithSession = last4Weeks.filter { week in
            week.workouts.contains { $0.workoutType == .gym && $0.isCompleted }
        }
        
        // On track = at least 1 session in 3 of last 4 weeks
        return weeksWithSession.count >= 3
    }
    
    // MARK: - Milestones
    var longestRunEverMilestone: Double {
        // Only count completed workouts for milestones
        let planWorkouts = plan.weeks.flatMap { $0.workouts }
        let planWorkoutIDs = Set(planWorkouts.map { $0.id })
        let combined = planWorkouts + additionalWorkouts.filter { !planWorkoutIDs.contains($0.id) }
        return Self.longestRunEver(from: combined)
    }
    
    var highestWeeklyMileage: Double {
        // Only count completed workouts for milestones
        let planWorkouts = plan.weeks.flatMap { $0.workouts }
        let planWorkoutIDs = Set(planWorkouts.map { $0.id })
        let combined = planWorkouts + additionalWorkouts.filter { !planWorkoutIDs.contains($0.id) }
        return Self.highestWeeklyMileage(from: combined)
    }
    
    var mostConsistentMonth: (month: String, adherence: Double)? {
        let calendar = Calendar.current
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM"
        
        var monthStats: [String: (total: Double, count: Int)] = [:]
        
        for week in plan.sortedWeeks {
            guard let firstWorkout = week.sortedWorkouts.first else { continue }
            let month = monthFormatter.string(from: firstWorkout.date)
            
            if monthStats[month] == nil {
                monthStats[month] = (total: 0, count: 0)
            }
            
            monthStats[month]?.total += week.completionProgress
            monthStats[month]?.count += 1
        }
        
        guard let bestMonth = monthStats.max(by: { ($0.value.total / Double($0.value.count)) < ($1.value.total / Double($1.value.count)) }) else {
            return nil
        }
        
        let averageAdherence = (bestMonth.value.total / Double(bestMonth.value.count)) * 100
        return (month: bestMonth.key, adherence: averageAdherence)
    }
    
    // MARK: - Race PBs (Fastest Consecutive Times via Sliding Window)
    
    /// Find the fastest consecutive N-km stretch across all completed workouts
    /// using a sliding window over each workout's persisted km splits.
    private func fastestConsecutiveTime(distanceKm targetKm: Int) -> MilestoneRecord? {
        // Combine plan workouts with any additional workouts (e.g., free runs)
        let planWorkouts = plan.weeks.flatMap { $0.workouts }
        let planWorkoutIDs = Set(planWorkouts.map { $0.id })
        let combined = planWorkouts + additionalWorkouts.filter { !planWorkoutIDs.contains($0.id) }
        
        var bestTimeSeconds: Int = Int.max
        var bestDate: Date? = nil
        
        for workout in combined {
            guard workout.isCompleted else { continue }
            
            let splits = workout.decodedKmSplits
            guard splits.count >= targetKm else { continue }
            
            // Sort splits by kilometer to ensure order
            let sortedSplits = splits.sorted { $0.kilometer < $1.kilometer }
            
            // Parse cumulative times to seconds
            let cumulativeSeconds = sortedSplits.compactMap { $0.time.toSeconds }
            guard cumulativeSeconds.count == sortedSplits.count else { continue }
            
            // Sliding window of targetKm consecutive kilometers
            for startIndex in 0...(cumulativeSeconds.count - targetKm) {
                let endIndex = startIndex + targetKm - 1
                let windowTime: Int
                if startIndex == 0 {
                    windowTime = cumulativeSeconds[endIndex]
                } else {
                    windowTime = cumulativeSeconds[endIndex] - cumulativeSeconds[startIndex - 1]
                }
                
                if windowTime > 0 && windowTime < bestTimeSeconds {
                    bestTimeSeconds = windowTime
                    bestDate = workout.completedAt ?? workout.date
                }
            }
        }
        
        guard bestTimeSeconds < Int.max, let date = bestDate else { return nil }
        
        return MilestoneRecord(
            timeString: .fromSeconds(bestTimeSeconds),
            date: date
        )
    }
    
    var fastest5K: MilestoneRecord? {
        fastestConsecutiveTime(distanceKm: 5)
    }
    
    var fastest10K: MilestoneRecord? {
        fastestConsecutiveTime(distanceKm: 10)
    }
    
    var fastest21K: MilestoneRecord? {
        fastestConsecutiveTime(distanceKm: 21)
    }
    
    var fastest42K: MilestoneRecord? {
        fastestConsecutiveTime(distanceKm: 42)
    }
    
    // MARK: - Static Helpers for No-Plan Mode
    
    /// Longest completed run distance from a flat list of workouts
    static func longestRunEver(from workouts: [Workout]) -> Double {
        workouts
            .filter { $0.isCompleted && $0.workoutType != .rest && $0.workoutType != .gym && $0.workoutType != .crossTraining }
            .compactMap { $0.effectiveDistanceKm }
            .max() ?? 0
    }
    
    /// Highest weekly mileage from a flat list of workouts (grouped by calendar week)
    static func highestWeeklyMileage(from workouts: [Workout]) -> Double {
        let calendar = Calendar.current
        let completed = workouts.filter { $0.isCompleted && $0.workoutType != .rest }
        guard !completed.isEmpty else { return 0 }
        
        // Group by calendar week
        let grouped = Dictionary(grouping: completed) { workout in
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: workout.date)
            return "\(components.yearForWeekOfYear ?? 0)-W\(components.weekOfYear ?? 0)"
        }
        
        // Sum distance per week and return max
        return grouped.values
            .map { weekWorkouts in
                weekWorkouts.reduce(0.0) { $0 + ($1.effectiveDistanceKm ?? 0) }
            }
            .max() ?? 0
    }
    
    /// Find fastest consecutive N-km stretch from a flat list of workouts (plan-independent)
    static func fastestConsecutiveTime(from workouts: [Workout], distanceKm targetKm: Int) -> MilestoneRecord? {
        var bestTimeSeconds: Int = Int.max
        var bestDate: Date? = nil
        
        for workout in workouts {
            guard workout.isCompleted else { continue }
            
            let splits = workout.decodedKmSplits
            guard splits.count >= targetKm else { continue }
            
            let sortedSplits = splits.sorted { $0.kilometer < $1.kilometer }
            let cumulativeSeconds = sortedSplits.compactMap { $0.time.toSeconds }
            guard cumulativeSeconds.count == sortedSplits.count else { continue }
            
            for startIndex in 0...(cumulativeSeconds.count - targetKm) {
                let endIndex = startIndex + targetKm - 1
                let windowTime: Int
                if startIndex == 0 {
                    windowTime = cumulativeSeconds[endIndex]
                } else {
                    windowTime = cumulativeSeconds[endIndex] - cumulativeSeconds[startIndex - 1]
                }
                
                if windowTime > 0 && windowTime < bestTimeSeconds {
                    bestTimeSeconds = windowTime
                    bestDate = workout.completedAt ?? workout.date
                }
            }
        }
        
        guard bestTimeSeconds < Int.max, let date = bestDate else { return nil }
        
        return MilestoneRecord(
            timeString: .fromSeconds(bestTimeSeconds),
            date: date
        )
    }
    
    // MARK: - Helper: Get weeks for time range
    func weeksForTimeRange(_ range: TimeRange) -> [Week] {
        let sortedWeeks = plan.sortedWeeks
        let today = Date()
        let calendar = Calendar.current
        
        switch range {
        case .thisWeek:
            return sortedWeeks.filter { $0.isCurrentWeek }
        case .last4Weeks:
            let fourWeeksAgo = calendar.date(byAdding: .weekOfYear, value: -4, to: today) ?? today
            return sortedWeeks.filter { week in
                guard let firstWorkout = week.sortedWorkouts.first else { return false }
                return firstWorkout.date >= fourWeeksAgo
            }
        case .last12Weeks:
            let twelveWeeksAgo = calendar.date(byAdding: .weekOfYear, value: -12, to: today) ?? today
            return sortedWeeks.filter { week in
                guard let firstWorkout = week.sortedWorkouts.first else { return false }
                return firstWorkout.date >= twelveWeeksAgo
            }
        case .fullPlan:
            return sortedWeeks
        case .yearToDate:
            let currentYear = calendar.component(.year, from: today)
            return sortedWeeks.filter { week in
                guard let firstWorkout = week.sortedWorkouts.first else { return false }
                return calendar.component(.year, from: firstWorkout.date) == currentYear
            }
        }
    }
}

// MARK: - Time Range
enum TimeRange: String, CaseIterable {
    case thisWeek = "This Week"
    case last4Weeks = "Last 4 Weeks"
    case last12Weeks = "Last 12 Weeks"
    case fullPlan = "Full Plan"
    case yearToDate = "Year-to-Date"
}
