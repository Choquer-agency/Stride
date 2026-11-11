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
    var runLogs: [RunLog] = []

    init(plan: TrainingPlan, runLogs: [RunLog] = []) {
        self.plan = plan
        self.runLogs = runLogs
    }

    static var trainingCalendar: Calendar { StatsTrainingData.calendar() }

    // MARK: - Static Helper for No-Plan Mode
    /// Calculate weekly distance using the user's locale-aware calendar week.
    static func weeklyDistanceForCurrentCalendarWeek(runLogs: [RunLog], now: Date = Date(), calendar: Calendar = .current) -> WeeklyDistanceStats {
        let interval = StatsTrainingData.week(containing: now, calendar: calendar)
        return WeeklyDistanceStats(completed: StatsTrainingData.distance(runLogs, in: interval), planned: 0, isNoPlanMode: true)
    }

    // MARK: - Weekly Stats (Completed vs Planned) — plan-specific, unchanged
    var currentWeekStats: WeeklyDistanceStats {
        let targetWeek: Week? = {
            if let currentWeek = plan.currentWeek {
                return currentWeek
            }
            let today = Date()
            let sortedWeeks = plan.sortedWeeks
            guard !sortedWeeks.isEmpty else { return nil }

            return sortedWeeks.min { week1, week2 in
                let date1 = week1.sortedWorkouts.first?.date ?? Date.distantFuture
                let date2 = week2.sortedWorkouts.first?.date ?? Date.distantFuture
                return abs(date1.timeIntervalSince(today)) < abs(date2.timeIntervalSince(today))
            }
        }()

        guard let week = targetWeek else {
            return WeeklyDistanceStats(completed: 0, planned: 0)
        }

        let interval = Self.trainingCalendar.dateInterval(of: .weekOfYear, for: Date())
        let completed = runLogs
            .filter { log in log.isValidForStats && (interval.map { log.completedAt >= $0.start && log.completedAt < $0.end } ?? false) }
            .reduce(0.0) { $0 + $1.distanceKm }

        let planned = week.workouts
            .filter { $0.workoutType.isRunnable }
            .reduce(0.0) { $0 + ($1.distanceKm ?? 0) }

        return WeeklyDistanceStats(completed: completed, planned: planned)
    }

    var previousWeekStats: WeeklyDistanceStats {
        guard let currentWeek = plan.currentWeek,
              let currentWeekIndex = plan.sortedWeeks.firstIndex(where: { $0.id == currentWeek.id }),
              currentWeekIndex > 0 else {
            return WeeklyDistanceStats(completed: 0, planned: 0)
        }

        let previousWeek = plan.sortedWeeks[currentWeekIndex - 1]

        let calendar = Self.trainingCalendar
        let currentInterval = calendar.dateInterval(of: .weekOfYear, for: Date())
        let previousDate = currentInterval.flatMap { calendar.date(byAdding: .second, value: -1, to: $0.start) }
        let previousInterval = previousDate.flatMap { calendar.dateInterval(of: .weekOfYear, for: $0) }
        let completed = runLogs
            .filter { log in log.isValidForStats && (previousInterval.map { log.completedAt >= $0.start && log.completedAt < $0.end } ?? false) }
            .reduce(0.0) { $0 + $1.distanceKm }

        let planned = previousWeek.workouts
            .filter { $0.workoutType.isRunnable }
            .reduce(0.0) { $0 + ($1.distanceKm ?? 0) }

        return WeeklyDistanceStats(completed: completed, planned: planned)
    }

    var weeklyDistanceChange: Double {
        let current = currentWeekStats.completed
        let previous = previousWeekStats.completed

        guard previous > 0 else { return 0 }
        return ((current - previous) / previous) * 100
    }

    // MARK: - Rolling Average (from RunLog)
    var rolling4WeekAverage: Double {
        Self.rolling4WeekAverage(from: runLogs)
    }

    static func rolling4WeekAverage(from runLogs: [RunLog], now: Date = Date()) -> Double {
        let runLogs = runLogs.filter(\.isValidForStats)
        let calendar = Self.trainingCalendar
        let today = now

        var weeklyDistances: [Double] = []
        for weeksBack in 1...4 {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -weeksBack, to: today) else { continue }
            guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: weekStart) else { continue }

            let distance = runLogs
                .filter { runLog in
                    let d = calendar.startOfDay(for: runLog.completedAt)
                    return d >= weekInterval.start && d < weekInterval.end
                }
                .reduce(0.0) { $0 + $1.distanceKm }

            weeklyDistances.append(distance)
        }

        guard !weeklyDistances.isEmpty else { return 0 }
        return weeklyDistances.reduce(0, +) / Double(weeklyDistances.count)
    }

    // MARK: - Year-to-Date (from RunLog)
    var yearToDateDistance: Double {
        Self.yearToDateDistance(from: runLogs)
    }

    static func yearToDateDistance(from runLogs: [RunLog]) -> Double {
        let runLogs = runLogs.filter(\.isValidForStats)
        let calendar = Self.trainingCalendar
        let currentYear = calendar.component(.year, from: Date())

        return runLogs
            .filter { calendar.component(.year, from: $0.completedAt) == currentYear }
            .reduce(0.0) { $0 + $1.distanceKm }
    }

    // MARK: - Streak — plan-specific, unchanged
    var consecutiveWeeksCompleted: Int {
        let sortedWeeks = plan.sortedWeeks
        var streak = 0

        for week in sortedWeeks.reversed() {
            if week.completionProgress >= 0.8 {
                streak += 1
            } else {
                break
            }
        }

        return streak
    }

    // MARK: - Composition — plan-specific, unchanged
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

    // MARK: - Long Runs — plan-specific, unchanged
    var longRunProgression: [(weekNumber: Int, distance: Double)] {
        plan.sortedWeeks.map { week in
            let trainingLongRunDistance = week.workouts
                .filter { $0.workoutType != .rest && $0.workoutType != .gym && $0.workoutType != .crossTraining && $0.workoutType != .race && !Calendar.current.isDate($0.date, inSameDayAs: plan.raceDate) }
                .max(by: { ($0.distanceKm ?? 0) < ($1.distanceKm ?? 0) })?
                .distanceKm ?? 0
            return (weekNumber: week.weekNumber, distance: trainingLongRunDistance)
        }
    }

    /// Actual recorded training maxima; absent weeks are left absent, never carried forward.
    var longRunActualProgression: [(weekNumber: Int, distance: Double)] {
        plan.sortedWeeks.compactMap { week in
            guard let start = week.mondayStart,
                  let end = Self.trainingCalendar.date(byAdding: .day, value: 7, to: start) else { return nil }
            let actual = runLogs.filter {
                $0.isValidForStats && $0.completedAt >= start && $0.completedAt < end && $0.completedAt <= Date()
                    && $0.plannedWorkoutType != .race
                    && !Self.trainingCalendar.isDate($0.completedAt, inSameDayAs: plan.raceDate)
            }.map(\.distanceKm).max()
            return actual.map { (week.weekNumber, $0) }
        }
    }

    /// Completed training only: race day and future prescriptions are not achievements.
    var longestRunEver: Double {
        longRunActualProgression.map(\.distance).max() ?? 0
    }

    var peakLongRunWeek: Int? {
        guard let maxDistance = longRunProgression.map({ $0.distance }).max(),
              maxDistance > 0 else { return nil }

        return longRunProgression.first { $0.distance == maxDistance }?.weekNumber
    }

    // MARK: - Adherence — plan-specific, unchanged
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

    // MARK: - Strength — plan-specific, unchanged
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

        return weeksWithSession.count >= 3
    }

    // MARK: - Milestones (from RunLog)
    var longestRunEverMilestone: Double {
        Self.longestRunEver(from: runLogs)
    }

    var highestWeeklyMileage: Double {
        Self.highestWeeklyMileage(from: runLogs)
    }

    var mostConsistentMonth: (month: String, adherence: Double)? {
        let calendar = Self.trainingCalendar
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

    // MARK: - Race PBs (from RunLog)

    private func fastestConsecutiveTime(distanceKm targetKm: Int) -> MilestoneRecord? {
        Self.fastestConsecutiveTime(from: runLogs, distanceKm: targetKm)
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

    // MARK: - Static Helpers (RunLog-based)

    static func longestRunEver(from runLogs: [RunLog]) -> Double {
        runLogs.filter(\.isValidForStats).map { $0.distanceKm }.max() ?? 0
    }

    static func highestWeeklyMileage(from runLogs: [RunLog]) -> Double {
        let calendar = Self.trainingCalendar
        guard !runLogs.isEmpty else { return 0 }

        let grouped = Dictionary(grouping: runLogs.filter(\.isValidForStats)) { runLog in
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: runLog.completedAt)
            return "\(components.yearForWeekOfYear ?? 0)-W\(components.weekOfYear ?? 0)"
        }

        return grouped.values
            .map { weekLogs in
                weekLogs.reduce(0.0) { $0 + $1.distanceKm }
            }
            .max() ?? 0
    }

    static func fastestConsecutiveTime(from runLogs: [RunLog], distanceKm targetKm: Int) -> MilestoneRecord? {
        var bestTimeSeconds: Int = Int.max
        var bestDate: Date? = nil

        for runLog in runLogs where runLog.isValidForStats {
            let splits = runLog.decodedKmSplits
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
                    bestDate = runLog.completedAt
                }
            }
        }

        guard bestTimeSeconds < Int.max, let date = bestDate else { return nil }

        return MilestoneRecord(
            timeString: .fromSeconds(bestTimeSeconds),
            date: date
        )
    }

    // MARK: - Helper: Get weeks for time range — plan-specific, unchanged
    func weeksForTimeRange(_ range: TimeRange) -> [Week] {
        let sortedWeeks = plan.sortedWeeks
        let today = Date()
        let calendar = Self.trainingCalendar

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

/// Calendar and sample calculations shared by Stats cards and charts.
enum StatsTrainingData {
    static func calendar(from source: Calendar = .current) -> Calendar {
        var result = source
        result.firstWeekday = 2
        result.minimumDaysInFirstWeek = 4
        return result
    }
    static func week(containing date: Date, calendar source: Calendar = .current) -> DateInterval {
        calendar(from: source).dateInterval(of: .weekOfYear, for: date)!
    }
    static func distance(_ logs: [RunLog], in interval: DateInterval) -> Double {
        logs.filter { $0.isValidForStats && $0.completedAt >= interval.start && $0.completedAt < interval.end }
            .reduce(0) { $0 + $1.distanceKm }
    }
    static func inEasyRangeSeconds(_ run: RunLog) -> (inside: Double, recorded: Double) {
        timeInRangeSeconds(run, range: 130...147)
    }
    static func timeInRangeSeconds(_ run: RunLog, range: ClosedRange<Int>) -> (inside: Double, recorded: Double) {
        let samples = run.decodedHRSamples.filter { $0.t.isFinite && $0.t >= 0 && $0.bpm > 0 }.sorted { $0.t < $1.t }
        var inside = 0.0, recorded = 0.0
        for (index, sample) in samples.enumerated() {
            let next = index + 1 < samples.count ? samples[index + 1].t : run.durationSeconds
            let seconds = max(0, min(next, sample.t + 10, run.durationSeconds) - sample.t)
            recorded += seconds
            if range.contains(sample.bpm) { inside += seconds }
        }
        return (inside, recorded)
    }
}

struct TrainingTrendWeek: Identifiable {
    var id: Date { start }
    let start: Date
    let heartRate: Double?
    let feeling: Double?
    let hrRunCount: Int
    let ratedRunCount: Int
}

struct TrainingInsightSummary {
    let heartRateType: WorkoutType
    let heartRateRange: ClosedRange<Int>
    let weeks: [TrainingTrendWeek]
    let recentHR: Double?
    let previousHR: Double?
    let recentPace: Double?
    let previousPace: Double?
    let recentHRCount: Int
    let previousHRCount: Int
    let recentFeeling: Double?
    let previousFeeling: Double?
    let ratedCount: Int
    let inRangePercent: Double?

    init(runLogs: [RunLog], now: Date = Date(), heartRateType: WorkoutType = .easyRun) {
        self.heartRateType = heartRateType
        let range: ClosedRange<Int> = heartRateType == .longRun ? 135...150 : heartRateType == .recovery ? 120...135 : 130...147
        self.heartRateRange = range
        let calendar = StatsTrainingData.calendar()
        let logs = runLogs.filter { $0.isValidForStats && $0.completedAt <= now }
        let current = StatsTrainingData.week(containing: now).start
        let recentStart = calendar.date(byAdding: .day, value: -13, to: calendar.startOfDay(for: now))!
        let priorStart = calendar.date(byAdding: .day, value: -14, to: recentStart)!
        let recent = logs.filter { $0.completedAt >= recentStart }
        let prior = logs.filter { $0.completedAt >= priorStart && $0.completedAt < recentStart }
        func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
        func easyHR(_ runs: [RunLog]) -> [RunLog] {
            runs.filter { $0.plannedWorkoutType == heartRateType && ($0.avgHeartRate ?? 0) > 0 }
        }
        let easy = easyHR(recent), previousEasy = easyHR(prior)
        recentHR = mean(easy.compactMap { $0.avgHeartRate.map(Double.init) })
        previousHR = mean(previousEasy.compactMap { $0.avgHeartRate.map(Double.init) })
        recentPace = mean(easy.map(\.avgPaceSecPerKm))
        previousPace = mean(previousEasy.map(\.avgPaceSecPerKm))
        recentHRCount = easy.count
        previousHRCount = previousEasy.count
        let ratings = recent.compactMap(\.feedbackRating).filter { (0...5).contains($0) }
        recentFeeling = mean(ratings.map(Double.init))
        previousFeeling = mean(prior.compactMap(\.feedbackRating).filter { (0...5).contains($0) }.map(Double.init))
        ratedCount = ratings.count
        let coverage = easy.map { StatsTrainingData.timeInRangeSeconds($0, range: range) }
        let seconds = coverage.reduce(0) { $0 + $1.recorded }
        inRangePercent = seconds > 0 ? coverage.reduce(0) { $0 + $1.inside } / seconds * 100 : nil
        weeks = (0..<8).reversed().map { offset in
            let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: current)!
            let end = calendar.date(byAdding: .day, value: 7, to: start)!
            let week = logs.filter { $0.completedAt >= start && $0.completedAt < end }
            let hr = easyHR(week)
            let feeling = week.compactMap(\.feedbackRating).filter { (0...5).contains($0) }
            return TrainingTrendWeek(start: start, heartRate: mean(hr.compactMap { $0.avgHeartRate.map(Double.init) }),
                feeling: mean(feeling.map(Double.init)), hrRunCount: hr.count, ratedRunCount: feeling.count)
        }
    }
}
