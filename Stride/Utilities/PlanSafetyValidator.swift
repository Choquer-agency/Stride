import Foundation

/// Validates AI-generated training plans for safety concerns
struct PlanSafetyValidator {
    
    // MARK: - Validation Result
    
    struct SafetyValidation {
        var isValid: Bool
        var warnings: [String]
        var criticalIssues: [String]
        
        var hasCriticalIssues: Bool {
            return !criticalIssues.isEmpty
        }
        
        var hasWarnings: Bool {
            return !warnings.isEmpty
        }
    }
    
    // MARK: - Main Validation Method
    
    static func validate(_ plan: TrainingPlan, baseline: BaselineAssessment?) -> SafetyValidation {
        var warnings: [String] = []
        var criticalIssues: [String] = []
        
        // 1. Validate weekly mileage progression
        let mileageIssues = validateWeeklyMileageProgression(plan: plan)
        warnings.append(contentsOf: mileageIssues.warnings)
        criticalIssues.append(contentsOf: mileageIssues.critical)
        
        // 2. Validate workout distribution
        let distributionIssues = validateWorkoutDistribution(plan: plan)
        warnings.append(contentsOf: distributionIssues.warnings)
        criticalIssues.append(contentsOf: distributionIssues.critical)
        
        // 3. Validate paces relative to baseline
        if let baseline = baseline {
            let paceIssues = validatePaces(plan: plan, baseline: baseline)
            warnings.append(contentsOf: paceIssues.warnings)
            criticalIssues.append(contentsOf: paceIssues.critical)
        }
        
        // 4. Validate long run distances
        let longRunIssues = validateLongRuns(plan: plan)
        warnings.append(contentsOf: longRunIssues.warnings)
        criticalIssues.append(contentsOf: longRunIssues.critical)
        
        // 5. Validate taper structure
        let taperIssues = validateTaper(plan: plan)
        warnings.append(contentsOf: taperIssues)
        
        // 6. Validate rest days
        let restIssues = validateRestDays(plan: plan)
        warnings.append(contentsOf: restIssues)
        
        return SafetyValidation(
            isValid: criticalIssues.isEmpty,
            warnings: warnings,
            criticalIssues: criticalIssues
        )
    }
    
    // MARK: - Individual Validators
    
    private static func validateWeeklyMileageProgression(plan: TrainingPlan) -> (warnings: [String], critical: [String]) {
        var warnings: [String] = []
        var critical: [String] = []
        
        for i in 1..<plan.weeks.count {
            let previousWeek = plan.weeks[i - 1]
            let currentWeek = plan.weeks[i]
            
            let previousVolume = previousWeek.targetWeeklyKm
            let currentVolume = currentWeek.targetWeeklyKm
            
            // Skip if in taper phase (volume should decrease)
            if currentWeek.phase.name.contains("Taper") {
                continue
            }
            
            // Check for excessive increases (>15% is critical, >10% is warning)
            if currentVolume > previousVolume {
                let increasePercent = ((currentVolume - previousVolume) / previousVolume) * 100
                
                if increasePercent > 15 {
                    critical.append("Week \(currentWeek.weekNumber): Weekly mileage increases by \(String(format: "%.1f", increasePercent))% (over 15% - injury risk)")
                } else if increasePercent > 10 {
                    warnings.append("Week \(currentWeek.weekNumber): Weekly mileage increases by \(String(format: "%.1f", increasePercent))% (consider 10% rule)")
                }
            }
        }
        
        return (warnings, critical)
    }
    
    private static func validateWorkoutDistribution(plan: TrainingPlan) -> (warnings: [String], critical: [String]) {
        var warnings: [String] = []
        var critical: [String] = []
        
        for week in plan.weeks {
            let workouts = week.workouts
            
            // Check for back-to-back hard workouts
            let sortedWorkouts = workouts.sorted { $0.date < $1.date }
            
            // Guard against empty workouts array
            guard sortedWorkouts.count > 1 else {
                continue
            }
            
            for i in 1..<sortedWorkouts.count {
                let previous = sortedWorkouts[i - 1]
                let current = sortedWorkouts[i]
                
                // Check if workouts are consecutive days
                let calendar = Calendar.current
                if let daysBetween = calendar.dateComponents([.day], from: previous.date, to: current.date).day,
                   daysBetween == 1 {
                    
                    let previousIsHard = isHardWorkout(previous)
                    let currentIsHard = isHardWorkout(current)
                    
                    if previousIsHard && currentIsHard {
                        warnings.append("Week \(week.weekNumber): Back-to-back hard workouts detected - consider adding recovery day")
                    }
                    
                    // Critical: long run followed by hard workout
                    if previous.type == .longRun && currentIsHard {
                        critical.append("Week \(week.weekNumber): Hard workout immediately after long run - high injury risk")
                    }
                }
            }
            
            // Check for too many hard workouts in one week
            let hardWorkoutCount = workouts.filter { isHardWorkout($0) }.count
            if hardWorkoutCount > 3 {
                warnings.append("Week \(week.weekNumber): \(hardWorkoutCount) hard workouts in one week - may be too intense")
            }
        }
        
        return (warnings, critical)
    }
    
    private static func validatePaces(plan: TrainingPlan, baseline: BaselineAssessment) -> (warnings: [String], critical: [String]) {
        var warnings: [String] = []
        var critical: [String] = []
        
        let baselineThreshold = baseline.trainingPaces.threshold
        let baselineInterval = baseline.trainingPaces.interval
        
        for week in plan.weeks {
            for workout in week.workouts {
                guard let targetPace = workout.targetPaceSecondsPerKm else { continue }
                
                // Check tempo runs
                if workout.type == .tempoRun {
                    // Critical if more than 20% faster than baseline threshold
                    let percentFaster = ((baselineThreshold - targetPace) / baselineThreshold) * 100
                    
                    if percentFaster > 20 {
                        critical.append("Week \(week.weekNumber): Tempo pace is \(String(format: "%.1f", percentFaster))% faster than baseline - dangerously aggressive")
                    } else if percentFaster > 15 {
                        warnings.append("Week \(week.weekNumber): Tempo pace is \(String(format: "%.1f", percentFaster))% faster than baseline - aggressive progression")
                    }
                }
                
                // Check interval workouts
                if workout.type == .intervalWorkout {
                    let percentFaster = ((baselineInterval - targetPace) / baselineInterval) * 100
                    
                    if percentFaster > 15 {
                        warnings.append("Week \(week.weekNumber): Interval pace is \(String(format: "%.1f", percentFaster))% faster than baseline - very challenging")
                    }
                }
            }
        }
        
        return (warnings, critical)
    }
    
    private static func validateLongRuns(plan: TrainingPlan) -> (warnings: [String], critical: [String]) {
        var warnings: [String] = []
        var critical: [String] = []
        
        for week in plan.weeks {
            for workout in week.workouts {
                if workout.type == .longRun {
                    guard let distance = workout.targetDistanceKm else { continue }
                    
                    // Check for excessive long run distance
                    let weeklyVolume = week.targetWeeklyKm
                    let longRunPercent = (distance / weeklyVolume) * 100
                    
                    if longRunPercent > 50 {
                        warnings.append("Week \(week.weekNumber): Long run is \(String(format: "%.1f", longRunPercent))% of weekly volume - very high proportion")
                    }
                    
                    // Check absolute distances
                    if distance > 35 {
                        warnings.append("Week \(week.weekNumber): Long run distance (\(String(format: "%.1f", distance)) km) is very long - ensure proper preparation")
                    }
                    
                    // Critical for extreme distances
                    if distance > 42 {
                        critical.append("Week \(week.weekNumber): Long run exceeds marathon distance - too risky for most runners")
                    }
                }
            }
        }
        
        return (warnings, critical)
    }
    
    private static func validateTaper(plan: TrainingPlan) -> [String] {
        var warnings: [String] = []
        
        // Find taper phase
        let taperWeeks = plan.weeks.filter { $0.phase.name.contains("Taper") }
        
        if taperWeeks.isEmpty {
            warnings.append("No taper phase detected - consider adding 1-2 weeks of reduced volume before race")
            return warnings
        }
        
        // Check if taper reduces volume
        if let lastBuildWeek = plan.weeks.filter({ !$0.phase.name.contains("Taper") }).last,
           let firstTaperWeek = taperWeeks.first {
            
            let buildVolume = lastBuildWeek.targetWeeklyKm
            let taperVolume = firstTaperWeek.targetWeeklyKm
            
            if taperVolume >= buildVolume * 0.9 {
                warnings.append("Taper week \(firstTaperWeek.weekNumber): Volume only reduced to \(String(format: "%.1f", taperVolume)) km - consider deeper taper")
            }
        }
        
        return warnings
    }
    
    private static func validateRestDays(plan: TrainingPlan) -> [String] {
        var warnings: [String] = []
        
        for week in plan.weeks {
            let workoutDays = Set(week.workouts.filter { $0.type != .rest }.map { 
                Calendar.current.component(.weekday, from: $0.date)
            })
            
            if workoutDays.count >= 7 {
                warnings.append("Week \(week.weekNumber): No rest days scheduled - recovery is essential for adaptation")
            }
        }
        
        return warnings
    }
    
    // MARK: - Helpers
    
    private static func isHardWorkout(_ workout: PlannedWorkout) -> Bool {
        switch workout.type {
        case .tempoRun, .intervalWorkout, .raceSimulation, .longRun:
            return true
        case .easyRun, .recoveryRun, .gym, .rest, .crossTraining:
            return false
        }
    }
}
