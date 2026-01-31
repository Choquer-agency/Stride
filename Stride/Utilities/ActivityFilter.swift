import Foundation

// MARK: - Time Period Filter

enum TimePeriod: String, CaseIterable {
    case week = "W"
    case month = "M"
    case year = "Y"
    case all = "All"
    
    var displayName: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        case .all: return "All"
        }
    }
}

// MARK: - Daily Aggregate for Chart

struct DailyAggregate: Identifiable {
    let id = UUID()
    let date: Date
    let totalDistanceKm: Double
    let workoutCount: Int
    
    var dayNumber: Int {
        Calendar.current.component(.day, from: date)
    }
    
    var shortDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

// MARK: - Activity Statistics

struct ActivityStatistics {
    let totalDistanceKm: Double
    let totalRuns: Int
    let avgPaceSecondsPerKm: Double
    let totalTimeSeconds: Double
    let dailyAggregates: [DailyAggregate]
    
    var avgDistancePerDay: Double {
        // Only count days that have workouts
        let daysWithWorkouts = dailyAggregates.filter { $0.totalDistanceKm > 0 }.count
        guard daysWithWorkouts > 0 else { return 0 }
        return totalDistanceKm / Double(daysWithWorkouts)
    }
}

// MARK: - Workout Session Extension

extension Array where Element == WorkoutSession {
    
    /// Filter workouts by time period and selected date
    func filtered(by period: TimePeriod, month: Int, year: Int) -> [WorkoutSession] {
        let calendar = Calendar.current
        
        switch period {
        case .all:
            return self
            
        case .week:
            // Get current week (last 7 days)
            let now = Date()
            guard let weekAgo = calendar.date(byAdding: .day, value: -6, to: now) else {
                return self
            }
            let startOfWeekAgo = calendar.startOfDay(for: weekAgo)
            let endOfToday = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now
            
            return self.filter { workout in
                workout.startTime >= startOfWeekAgo && workout.startTime <= endOfToday
            }
            
        case .month:
            // Filter by selected month and year
            return self.filter { workout in
                let components = calendar.dateComponents([.year, .month], from: workout.startTime)
                return components.year == year && components.month == month
            }
            
        case .year:
            // Filter by selected year
            return self.filter { workout in
                let components = calendar.dateComponents([.year], from: workout.startTime)
                return components.year == year
            }
        }
    }
    
    /// Calculate activity statistics for filtered workouts
    func calculateStatistics(for period: TimePeriod, month: Int, year: Int) -> ActivityStatistics {
        let filteredWorkouts = self.filtered(by: period, month: month, year: year)
        
        // Calculate totals
        let totalDistance = filteredWorkouts.reduce(0.0) { $0 + $1.totalDistanceKm }
        let totalTime = filteredWorkouts.reduce(0.0) { $0 + $1.durationSeconds }
        
        // Calculate average pace (weighted by distance)
        let totalDistanceMeters = filteredWorkouts.reduce(0.0) { $0 + $1.totalDistanceMeters }
        let avgPace: Double
        if totalDistanceMeters > 0 && totalTime > 0 {
            let avgSpeed = totalDistanceMeters / totalTime
            avgPace = avgSpeed > 0 ? 1000.0 / avgSpeed : 0
        } else {
            avgPace = 0
        }
        
        // Generate daily aggregates
        let dailyAggregates = self.generateDailyAggregates(
            filteredWorkouts: filteredWorkouts,
            period: period,
            month: month,
            year: year
        )
        
        return ActivityStatistics(
            totalDistanceKm: totalDistance,
            totalRuns: filteredWorkouts.count,
            avgPaceSecondsPerKm: avgPace,
            totalTimeSeconds: totalTime,
            dailyAggregates: dailyAggregates
        )
    }
    
    /// Generate daily aggregates for the bar chart
    private func generateDailyAggregates(
        filteredWorkouts: [WorkoutSession],
        period: TimePeriod,
        month: Int,
        year: Int
    ) -> [DailyAggregate] {
        guard !filteredWorkouts.isEmpty else { return [] }
        
        let calendar = Calendar.current
        
        // For year view, group by month instead of day
        if period == .year {
            return generateMonthlyAggregates(filteredWorkouts: filteredWorkouts, year: year)
        }
        
        // Determine date range for the period
        let dateRange = self.getDateRange(for: period, month: month, year: year)
        
        // Group workouts by day
        var workoutsByDay: [Date: [WorkoutSession]] = [:]
        for workout in filteredWorkouts {
            let dayStart = calendar.startOfDay(for: workout.startTime)
            workoutsByDay[dayStart, default: []].append(workout)
        }
        
        // For 'all' period, only include days with workouts to avoid too many bars
        if period == .all {
            return workoutsByDay.keys.sorted().map { date in
                let workoutsForDay = workoutsByDay[date] ?? []
                let totalDistance = workoutsForDay.reduce(0.0) { $0 + $1.totalDistanceKm }
                return DailyAggregate(
                    date: date,
                    totalDistanceKm: totalDistance,
                    workoutCount: workoutsForDay.count
                )
            }
        }
        
        // Create aggregates for each day in range
        var aggregates: [DailyAggregate] = []
        var currentDate = dateRange.start
        
        while currentDate <= dateRange.end {
            let workoutsForDay = workoutsByDay[currentDate] ?? []
            let totalDistance = workoutsForDay.reduce(0.0) { $0 + $1.totalDistanceKm }
            
            aggregates.append(DailyAggregate(
                date: currentDate,
                totalDistanceKm: totalDistance,
                workoutCount: workoutsForDay.count
            ))
            
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDate) else {
                break
            }
            currentDate = nextDay
        }
        
        return aggregates
    }
    
    /// Generate monthly aggregates for year view
    private func generateMonthlyAggregates(
        filteredWorkouts: [WorkoutSession],
        year: Int
    ) -> [DailyAggregate] {
        let calendar = Calendar.current
        
        // Group workouts by month
        var workoutsByMonth: [Int: [WorkoutSession]] = [:]
        for workout in filteredWorkouts {
            let month = calendar.component(.month, from: workout.startTime)
            workoutsByMonth[month, default: []].append(workout)
        }
        
        // Create aggregates for each month (only months with data)
        var aggregates: [DailyAggregate] = []
        for month in 1...12 {
            let workoutsForMonth = workoutsByMonth[month] ?? []
            guard !workoutsForMonth.isEmpty else { continue }
            
            let totalDistance = workoutsForMonth.reduce(0.0) { $0 + $1.totalDistanceKm }
            
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = 1
            
            if let date = calendar.date(from: components) {
                aggregates.append(DailyAggregate(
                    date: date,
                    totalDistanceKm: totalDistance,
                    workoutCount: workoutsForMonth.count
                ))
            }
        }
        
        return aggregates
    }
    
    /// Get the date range for the selected period
    private func getDateRange(for period: TimePeriod, month: Int, year: Int) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        
        switch period {
        case .all:
            // From first workout to today
            let firstDate = self.map { $0.startTime }.min() ?? now
            return (calendar.startOfDay(for: firstDate), calendar.startOfDay(for: now))
            
        case .week:
            // Last 7 days
            let weekAgo = calendar.date(byAdding: .day, value: -6, to: now) ?? now
            return (calendar.startOfDay(for: weekAgo), calendar.startOfDay(for: now))
            
        case .month:
            // All days in selected month
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = 1
            
            guard let firstDay = calendar.date(from: components),
                  let range = calendar.range(of: .day, in: .month, for: firstDay),
                  let lastDay = calendar.date(byAdding: .day, value: range.count - 1, to: firstDay) else {
                return (now, now)
            }
            
            return (calendar.startOfDay(for: firstDay), calendar.startOfDay(for: lastDay))
            
        case .year:
            // All days in selected year (or just months with data)
            var components = DateComponents()
            components.year = year
            components.month = 1
            components.day = 1
            
            guard let firstDay = calendar.date(from: components) else {
                return (now, now)
            }
            
            components.month = 12
            components.day = 31
            guard let lastDay = calendar.date(from: components) else {
                return (now, now)
            }
            
            return (calendar.startOfDay(for: firstDay), calendar.startOfDay(for: lastDay))
        }
    }
}

