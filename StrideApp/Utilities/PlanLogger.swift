import Foundation

/// Debug logging utility for training plans
/// Outputs comprehensive plan details to Xcode console for debugging
enum PlanLogger {
    
    // MARK: - Main Logging Methods
    
    /// Log a complete training plan with all details
    static func logPlan(_ plan: TrainingPlan, rawContent: String? = nil) {
        printSeparator()
        print(" TRAINING PLAN DEBUG LOG")
        printSeparator()
        
        // Plan metadata
        print("Race: \(plan.raceType.rawValue) on \(formatDate(plan.raceDate))")
        if let goalTime = plan.goalTime {
            print("Goal Time: \(goalTime)")
        }
        if let mode = plan.planMode {
            print("Plan Mode: \(mode.rawValue)")
        }
        print("Start Date: \(formatDate(plan.startDate))")
        print("Total Weeks: \(plan.totalWeeks)")
        print("Total Workouts: \(plan.totalWorkouts)")
        print("")
        
        // Raw content from API
        if let content = rawContent ?? plan.rawPlanContent {
            print("--- RAW CONTENT FROM API ---")
            print(content)
            print("")
        }
        
        // Parsed structure
        print("--- PARSED PLAN STRUCTURE ---")
        print("")
        
        for week in plan.sortedWeeks {
            logWeek(week)
        }
        
        printSeparator()
        print(" END PLAN DEBUG LOG")
        printSeparator()
        print("")
    }
    
    /// Log parsed weeks before they're converted to SwiftData models
    static func logParsedWeeks(_ weeks: [ParsedWeek], startDate: Date, raceDate: Date) {
        printSeparator()
        print(" PARSED WEEKS DEBUG LOG")
        printSeparator()
        print("Start Date: \(formatDate(startDate))")
        print("Race Date: \(formatDate(raceDate))")
        print("Weeks Parsed: \(weeks.count)")
        print("")
        
        for week in weeks {
            logParsedWeek(week)
        }
        
        printSeparator()
        print(" END PARSED WEEKS LOG")
        printSeparator()
        print("")
    }
    
    /// Log raw API content as it's received
    static func logRawContent(_ content: String) {
        printSeparator()
        print(" RAW API RESPONSE")
        printSeparator()
        print(content)
        printSeparator()
        print("")
    }
    
    // MARK: - Week Logging
    
    private static func logWeek(_ week: Week) {
        var weekHeader = "WEEK \(week.weekNumber)"
        if let theme = week.theme {
            weekHeader += " [\(theme)]"
        }
        if !week.dateRange.isEmpty {
            weekHeader += " (\(week.dateRange))"
        }
        print(weekHeader)
        print("  Total Distance: \(String(format: "%.1f", week.totalDistance)) km")
        print("  Workouts: \(week.activeWorkouts) active, \(week.workouts.count) total")
        print("")
        
        for workout in week.sortedWorkouts {
            logWorkout(workout)
        }
        print("")
    }
    
    private static func logParsedWeek(_ week: ParsedWeek) {
        var weekHeader = "WEEK \(week.weekNumber)"
        if let theme = week.theme {
            weekHeader += " [\(theme)]"
        }
        print(weekHeader)
        print("  Workouts: \(week.workouts.count)")
        print("")
        
        for workout in week.workouts {
            logParsedWorkout(workout)
        }
        print("")
    }
    
    // MARK: - Workout Logging
    
    private static func logWorkout(_ workout: Workout) {
        // Format: "  Mon Feb 10: Easy Run - 8km @ 5:45/km"
        var line = "  \(workout.shortDayOfWeek) \(workout.formattedDate): "
        line += "\(workout.workoutType.displayName)"
        
        if workout.title != workout.workoutType.displayName {
            line += " - \(workout.title)"
        }
        
        var metrics: [String] = []
        if let distance = workout.distanceDisplay {
            metrics.append(distance)
        }
        if let duration = workout.durationDisplay {
            metrics.append(duration)
        }
        if let pace = workout.paceDescription {
            metrics.append("@ \(pace)")
        }
        
        if !metrics.isEmpty {
            line += " | \(metrics.joined(separator: ", "))"
        }
        
        print(line)
        
        // Log full details on next line if present
        if let details = workout.details, !details.isEmpty {
            print("    Details: \(details)")
        }
    }
    
    private static func logParsedWorkout(_ workout: ParsedWorkout) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE MMM d"
        let dateStr = dateFormatter.string(from: workout.date)
        
        var line = "  \(dateStr): \(workout.workoutType.displayName)"
        
        if workout.title != workout.workoutType.displayName {
            line += " - \(workout.title)"
        }
        
        var metrics: [String] = []
        if let distance = workout.distanceKm {
            if distance == floor(distance) {
                metrics.append("\(Int(distance)) km")
            } else {
                metrics.append(String(format: "%.1f km", distance))
            }
        }
        if let duration = workout.durationMinutes {
            if duration >= 60 {
                let hours = duration / 60
                let mins = duration % 60
                metrics.append(mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h")
            } else {
                metrics.append("\(duration) min")
            }
        }
        if let pace = workout.paceDescription {
            metrics.append("@ \(pace)")
        }
        
        if !metrics.isEmpty {
            line += " | \(metrics.joined(separator: ", "))"
        }
        
        print(line)
        
        if let details = workout.details, !details.isEmpty {
            print("    Details: \(details)")
        }
    }
    
    // MARK: - Helpers
    
    private static func printSeparator() {
        print("========================================")
    }
    
    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: date)
    }
}
