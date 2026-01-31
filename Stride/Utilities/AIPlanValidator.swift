import Foundation

/// Validates AI-generated training plans with deterministic checks
class AIPlanValidator {
    
    // MARK: - Validation Result
    
    struct ValidationResult {
        let isValid: Bool
        let errors: [ValidationError]
        let warnings: [String]
    }
    
    struct ValidationError {
        let type: ErrorType
        let message: String
        let affectedDate: Date?
        
        enum ErrorType {
            case missingDays
            case workoutOnRestDay
            case workoutOnUnavailableDay
            case invalidPaces
            case missingGoalPaceExposure
            case jsonStructureInvalid
            case consecutiveGymDays
        }
    }
    
    // MARK: - Main Validation Method
    
    static func validate(
        planJSON: [String: Any],
        goal: Goal,
        baseline: BaselineAssessment?,
        preferences: TrainingPreferences
    ) -> ValidationResult {
        var errors: [ValidationError] = []
        var warnings: [String] = []
        
        // 1. Check JSON structure
        guard let days = planJSON["days"] as? [[String: Any]] else {
            errors.append(ValidationError(
                type: .jsonStructureInvalid,
                message: "Missing 'days' array in response",
                affectedDate: nil
            ))
            return ValidationResult(isValid: false, errors: errors, warnings: warnings)
        }
        
        guard let _ = planJSON["plan_metadata"] as? [String: Any] else {
            errors.append(ValidationError(
                type: .jsonStructureInvalid,
                message: "Missing 'plan_metadata' in response",
                affectedDate: nil
            ))
            return ValidationResult(isValid: false, errors: errors, warnings: warnings)
        }
        
        guard let _ = planJSON["goal_feasibility"] as? [String: Any] else {
            errors.append(ValidationError(
                type: .jsonStructureInvalid,
                message: "Missing 'goal_feasibility' in response",
                affectedDate: nil
            ))
            return ValidationResult(isValid: false, errors: errors, warnings: warnings)
        }
        
        guard let _ = planJSON["pace_context"] as? [String: Any] else {
            errors.append(ValidationError(
                type: .jsonStructureInvalid,
                message: "Missing 'pace_context' in response",
                affectedDate: nil
            ))
            return ValidationResult(isValid: false, errors: errors, warnings: warnings)
        }
        
        // 2. Check date coverage
        let startDate = Calendar.current.startOfDay(for: Date())
        let expectedDays = Calendar.current.dateComponents([.day], from: startDate, to: goal.eventDate).day ?? 0
        
        if days.count != expectedDays + 1 {
            errors.append(ValidationError(
                type: .missingDays,
                message: "Expected \(expectedDays + 1) days from \(startDate) to \(goal.eventDate), got \(days.count) days",
                affectedDate: nil
            ))
        }
        
        // 3. Check no run/gym workouts on rest days - STRICT ENFORCEMENT
        let restDays = preferences.getEffectiveAvailability().restDays
        let isoFormatter = ISO8601DateFormatter()
        let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        
        // Fallback: Date-only format (2026-01-25) - AI often returns this
        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        dateOnlyFormatter.timeZone = TimeZone.current
        
        let displayDateFormatter = DateFormatter()
        displayDateFormatter.dateFormat = "MMM d, yyyy"
        
        for day in days {
            guard let dateString = day["date"] as? String,
                  let date = isoFormatter.date(from: dateString) ?? dateOnlyFormatter.date(from: dateString),
                  let type = day["type"] as? String else {
                continue
            }
            
            let dayOfWeek = Calendar.current.component(.weekday, from: date) - 1
            let dayName = dayNames[dayOfWeek]
            let displayDate = displayDateFormatter.string(from: date)
            
            if restDays.contains(dayOfWeek) && (type == "run" || type == "gym") {
                errors.append(ValidationError(
                    type: .workoutOnRestDay,
                    message: "⛔️ BLOCKED: \(type) workout scheduled on \(dayName) (\(displayDate)) which is a designated rest day. Rest days MUST have type 'rest'.",
                    affectedDate: date
                ))
            }
        }
        
        // 4. Check workouts only on available days (or marked unavailable)
        let availableDays = preferences.getEffectiveAvailability().availableDays
        
        for day in days {
            guard let dateString = day["date"] as? String,
                  let date = isoFormatter.date(from: dateString) ?? dateOnlyFormatter.date(from: dateString),
                  let type = day["type"] as? String else {
                continue
            }
            
            let dayOfWeek = Calendar.current.component(.weekday, from: date) - 1
            let dayName = dayNames[dayOfWeek]
            let displayDate = displayDateFormatter.string(from: date)
            
            // Skip if it's a rest day (already checked above) or if day is available
            if restDays.contains(dayOfWeek) || availableDays.contains(dayOfWeek) {
                continue
            }
            
            // This day is unavailable (not rest, not available)
            if type == "run" || type == "gym" {
                errors.append(ValidationError(
                    type: .workoutOnUnavailableDay,
                    message: "⛔️ BLOCKED: \(type) workout scheduled on \(dayName) (\(displayDate)) which is marked unavailable.",
                    affectedDate: date
                ))
            }
        }
        
        // 5. Check pace validity (tempo > easy, interval > tempo)
        if let paceContext = planJSON["pace_context"] as? [String: Any] {
            validatePaceContext(paceContext: paceContext, errors: &errors, warnings: &warnings)
        }
        
        // 6. Check no consecutive gym days
        validateNoConsecutiveGym(days: days, errors: &errors, warnings: &warnings)
        
        // 7. Check goal pace exposure in peak phase (for time goals)
        if goal.type != .completion, let targetTime = goal.targetTime, let distance = goal.distanceKm {
            let targetPace = targetTime / distance
            checkGoalPaceExposure(days: days, targetPace: targetPace, errors: &errors, warnings: &warnings)
        }
        
        return ValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }
    
    // MARK: - Individual Validators
    
    private static func validatePaceContext(
        paceContext: [String: Any],
        errors: inout [ValidationError],
        warnings: inout [String]
    ) {
        guard let easyPace = paceContext["easy_pace_sec_per_km"] as? Double,
              let tempoPace = paceContext["tempo_pace_sec_per_km"] as? Double,
              let intervalPace = paceContext["interval_pace_sec_per_km"] as? Double else {
            errors.append(ValidationError(
                type: .invalidPaces,
                message: "pace_context missing required pace fields",
                affectedDate: nil
            ))
            return
        }
        
        // Tempo must be at least 15 sec/km faster than easy
        let tempoDiff = easyPace - tempoPace
        if tempoDiff < 15 {
            errors.append(ValidationError(
                type: .invalidPaces,
                message: "Tempo pace (\(Int(tempoPace))s/km) must be at least 15 sec/km faster than easy pace (\(Int(easyPace))s/km). Current difference: \(Int(tempoDiff))s/km",
                affectedDate: nil
            ))
        }
        
        // Interval must be at least 10 sec/km faster than tempo
        let intervalDiff = tempoPace - intervalPace
        if intervalDiff < 10 {
            errors.append(ValidationError(
                type: .invalidPaces,
                message: "Interval pace (\(Int(intervalPace))s/km) must be at least 10 sec/km faster than tempo pace (\(Int(tempoPace))s/km). Current difference: \(Int(intervalDiff))s/km",
                affectedDate: nil
            ))
        }
    }
    
    private static func validateNoConsecutiveGym(
        days: [[String: Any]],
        errors: inout [ValidationError],
        warnings: inout [String]
    ) {
        let isoFormatter = ISO8601DateFormatter()
        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        dateOnlyFormatter.timeZone = TimeZone.current
        
        // Helper to parse date with fallback
        func parseDate(_ str: String) -> Date? {
            return isoFormatter.date(from: str) ?? dateOnlyFormatter.date(from: str)
        }
        
        var previousGymDate: Date?
        
        for day in days.sorted(by: { d1, d2 in
            guard let date1 = (d1["date"] as? String).flatMap({ parseDate($0) }),
                  let date2 = (d2["date"] as? String).flatMap({ parseDate($0) }) else {
                return false
            }
            return date1 < date2
        }) {
            guard let dateString = day["date"] as? String,
                  let date = parseDate(dateString),
                  let type = day["type"] as? String else {
                continue
            }
            
            if type == "gym" {
                if let prevDate = previousGymDate {
                    let daysBetween = Calendar.current.dateComponents([.day], from: prevDate, to: date).day ?? 0
                    if daysBetween < 2 {
                        errors.append(ValidationError(
                            type: .consecutiveGymDays,
                            message: "Gym workouts scheduled on consecutive days (must have at least 48 hours between sessions)",
                            affectedDate: date
                        ))
                    }
                }
                previousGymDate = date
            }
        }
    }
    
    private static func checkGoalPaceExposure(
        days: [[String: Any]],
        targetPace: Double,
        errors: inout [ValidationError],
        warnings: inout [String]
    ) {
        // Check for goal-pace workouts in the final 4 weeks (before any taper)
        let isoFormatter = ISO8601DateFormatter()
        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        dateOnlyFormatter.timeZone = TimeZone.current
        
        // Find the race date (last day)
        let sortedDays = days.compactMap { day -> (Date, [String: Any])? in
            guard let dateString = day["date"] as? String,
                  let date = isoFormatter.date(from: dateString) ?? dateOnlyFormatter.date(from: dateString) else {
                return nil
            }
            return (date, day)
        }.sorted { $0.0 < $1.0 }
        
        guard let raceDate = sortedDays.last?.0 else { return }
        
        // Check workouts in final 4 weeks (28 days before race)
        let finalPhaseCutoff = Calendar.current.date(byAdding: .day, value: -28, to: raceDate) ?? raceDate
        
        var goalPaceWorkoutCount = 0
        let tolerance = 15.0 // within 15 sec/km of goal pace
        
        for (date, day) in sortedDays {
            guard date >= finalPhaseCutoff else { continue }
            guard let type = day["type"] as? String, type == "run" else { continue }
            
            // Check for explicit goal_pace run type
            if let runType = day["run_type"] as? String, runType == "goal_pace" {
                goalPaceWorkoutCount += 1
                continue
            }
            
            // Check if pace is close to goal pace
            if let pace = day["pace"] as? Double, abs(pace - targetPace) <= tolerance {
                goalPaceWorkoutCount += 1
            }
            
            // Also check nested workout object
            if let workout = day["workout"] as? [String: Any],
               let pace = workout["target_pace_sec_per_km"] as? Double,
               abs(pace - targetPace) <= tolerance {
                goalPaceWorkoutCount += 1
            }
        }
        
        // Format goal pace for display
        let goalPaceMin = Int(targetPace) / 60
        let goalPaceSec = Int(targetPace) % 60
        let goalPaceStr = "\(goalPaceMin):\(String(format: "%02d", goalPaceSec))/km"
        
        if goalPaceWorkoutCount == 0 {
            errors.append(ValidationError(
                type: .missingGoalPaceExposure,
                message: "No goal-pace workouts found in final 4 weeks. Plan MUST include at least 2 workouts at or near goal pace (\(goalPaceStr)) to prepare for race day.",
                affectedDate: nil
            ))
        } else if goalPaceWorkoutCount < 2 {
            warnings.append("Only \(goalPaceWorkoutCount) goal-pace workout found in final 4 weeks. Recommend 2-3 sessions at \(goalPaceStr) for optimal race preparation.")
        }
    }
}
