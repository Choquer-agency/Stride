import Foundation

/// Adaptation plan with specific changes and reasoning
struct AdaptationPlan {
    let createdAt: Date
    let analysisResult: AnalysisResult
    let adjustments: [WorkoutAdjustment]
    let coachMessage: CoachMessage
    
    struct WorkoutAdjustment {
        let workoutId: UUID
        let workoutDate: Date
        let changeType: ChangeType
        let oldValue: String
        let newValue: String
        let reason: String
        
        enum ChangeType {
            case volumeReduction
            case volumeIncrease
            case intensityReduction
            case intensityIncrease
            case workoutTypeChange
            case addedRestDay
            case removedRestDay
        }
    }
    
    struct CoachMessage {
        let title: String
        let summary: String
        let details: [String]
        let severity: Severity
        
        enum Severity {
            case positive // Green - good progress
            case neutral // Blue - maintaining
            case caution // Yellow - needs attention
            case warning // Red - needs recovery
        }
    }
}

/// Adapts training plan based on analysis results
class PlanAdapter {
    private let calendar = Calendar.current
    
    /// Generate adaptation plan based on analysis
    func generateAdaptation(from analysis: AnalysisResult, for plan: TrainingPlan) -> AdaptationPlan {
        var adjustments: [AdaptationPlan.WorkoutAdjustment] = []
        
        // Get next 7 days of workouts
        let today = calendar.startOfDay(for: Date())
        guard let nextWeekEnd = calendar.date(byAdding: .day, value: 6, to: today) else {
            return createNoChangesPlan(analysis: analysis)
        }
        
        let upcomingWorkouts = plan.allWorkouts.filter { workout in
            let workoutDay = calendar.startOfDay(for: workout.date)
            return workoutDay >= today && workoutDay <= nextWeekEnd && !workout.completed
        }
        
        guard !upcomingWorkouts.isEmpty else {
            return createNoChangesPlan(analysis: analysis)
        }
        
        // Apply adaptation logic based on overall status
        switch analysis.overallStatus {
        case .needsRest:
            adjustments = applyRestProtocol(workouts: upcomingWorkouts, analysis: analysis, availability: plan.availability)
            
        case .needsRecovery:
            adjustments = applyRecoveryProtocol(workouts: upcomingWorkouts, analysis: analysis, availability: plan.availability)
            
        case .excellent:
            adjustments = applyProgressionProtocol(workouts: upcomingWorkouts, analysis: analysis, availability: plan.availability)
            
        case .good:
            adjustments = applyMaintenanceProtocol(workouts: upcomingWorkouts, analysis: analysis)
        }
        
        // Generate coach message
        let coachMessage = generateCoachMessage(analysis: analysis, adjustments: adjustments, availability: plan.availability)
        
        return AdaptationPlan(
            createdAt: Date(),
            analysisResult: analysis,
            adjustments: adjustments,
            coachMessage: coachMessage
        )
    }
    
    // MARK: - Adaptation Protocols
    
    private func applyRestProtocol(workouts: [PlannedWorkout], analysis: AnalysisResult, availability: TrainingAvailability) -> [AdaptationPlan.WorkoutAdjustment] {
        var adjustments: [AdaptationPlan.WorkoutAdjustment] = []
        let reductionFactor = 0.85 // 15% reduction
        
        for workout in workouts {
            guard workout.isRunWorkout else { continue }
            
            // Reduce all run workouts by 15%
            if let targetDistance = workout.targetDistanceKm {
                let newDistance = targetDistance * reductionFactor
                adjustments.append(AdaptationPlan.WorkoutAdjustment(
                    workoutId: workout.id,
                    workoutDate: workout.date,
                    changeType: .volumeReduction,
                    oldValue: String(format: "%.1f km", targetDistance),
                    newValue: String(format: "%.1f km", newDistance),
                    reason: analysis.injuryStatus == .concerning ? "Injury recovery" : "Reduce fatigue"
                ))
            }
            
            // Convert high-intensity workouts to easy runs
            if workout.type == .tempoRun || workout.type == .intervalWorkout {
                adjustments.append(AdaptationPlan.WorkoutAdjustment(
                    workoutId: workout.id,
                    workoutDate: workout.date,
                    changeType: .workoutTypeChange,
                    oldValue: workout.type.displayName,
                    newValue: "Easy Run",
                    reason: "Recovery takes priority"
                ))
            }
        }
        
        // ONLY suggest adding a rest day if there are available days that could be converted
        // NEVER suggest rest days beyond availability constraints
        if analysis.injuryStatus == .concerning && workouts.count >= 3 {
            // Find a workout on an available day (not already a rest day)
            let convertibleWorkout = workouts.first { workout in
                let dayOfWeek = calendar.component(.weekday, from: workout.date) - 1
                return availability.availableDays.contains(dayOfWeek) && workout.type != .rest
            }
            
            if let midWeekWorkout = convertibleWorkout {
                // This is a SUGGESTION only - system won't auto-apply
                let dayOfWeek = calendar.component(.weekday, from: midWeekWorkout.date) - 1
                let dayName = TrainingAvailability.dayName(for: dayOfWeek)
                
                adjustments.append(AdaptationPlan.WorkoutAdjustment(
                    workoutId: midWeekWorkout.id,
                    workoutDate: midWeekWorkout.date,
                    changeType: .workoutTypeChange,
                    oldValue: midWeekWorkout.type.displayName,
                    newValue: "Rest Day",
                    reason: "Consider making \(dayName) a rest day to manage fatigue (optional)"
                ))
            }
        }
        
        return adjustments
    }
    
    private func applyRecoveryProtocol(workouts: [PlannedWorkout], analysis: AnalysisResult, availability: TrainingAvailability) -> [AdaptationPlan.WorkoutAdjustment] {
        var adjustments: [AdaptationPlan.WorkoutAdjustment] = []
        let reductionFactor = 0.90 // 10% reduction
        
        for workout in workouts {
            guard workout.isRunWorkout else { continue }
            
            // Reduce volume by 10%
            if let targetDistance = workout.targetDistanceKm {
                let newDistance = targetDistance * reductionFactor
                adjustments.append(AdaptationPlan.WorkoutAdjustment(
                    workoutId: workout.id,
                    workoutDate: workout.date,
                    changeType: .volumeReduction,
                    oldValue: String(format: "%.1f km", targetDistance),
                    newValue: String(format: "%.1f km", newDistance),
                    reason: "Moderate recovery needed"
                ))
            }
            
            // Reduce intensity on tempo/interval workouts
            if (workout.type == .tempoRun || workout.type == .intervalWorkout),
               let targetPace = workout.targetPaceSecondsPerKm {
                let newPace = targetPace * 1.05 // 5% slower
                adjustments.append(AdaptationPlan.WorkoutAdjustment(
                    workoutId: workout.id,
                    workoutDate: workout.date,
                    changeType: .intensityReduction,
                    oldValue: formatPace(targetPace),
                    newValue: formatPace(newPace),
                    reason: "Ease intensity for recovery"
                ))
            }
        }
        
        return adjustments
    }
    
    private func applyProgressionProtocol(workouts: [PlannedWorkout], analysis: AnalysisResult, availability: TrainingAvailability) -> [AdaptationPlan.WorkoutAdjustment] {
        var adjustments: [AdaptationPlan.WorkoutAdjustment] = []
        let progressionFactor = 1.05 // 5% increase
        
        // Only progress if completion rate is very high and all metrics are positive
        // AND user has training days available to accommodate progression
        guard analysis.completionRate >= 0.9,
              analysis.paceConsistency == .excellent || analysis.paceConsistency == .good,
              analysis.fatigueStatus == .fresh || analysis.fatigueStatus == .moderate,
              availability.totalAvailableDays >= 3 else { // Need enough training days for progression
            return adjustments
        }
        
        // Increase volume on easy and long runs only (conservative progression)
        for workout in workouts {
            if workout.type == .easyRun || workout.type == .longRun,
               let targetDistance = workout.targetDistanceKm {
                let newDistance = targetDistance * progressionFactor
                adjustments.append(AdaptationPlan.WorkoutAdjustment(
                    workoutId: workout.id,
                    workoutDate: workout.date,
                    changeType: .volumeIncrease,
                    oldValue: String(format: "%.1f km", targetDistance),
                    newValue: String(format: "%.1f km", newDistance),
                    reason: "Progressive overload"
                ))
            }
        }
        
        return adjustments
    }
    
    private func applyMaintenanceProtocol(workouts: [PlannedWorkout], analysis: AnalysisResult) -> [AdaptationPlan.WorkoutAdjustment] {
        var adjustments: [AdaptationPlan.WorkoutAdjustment] = []
        
        // Minor tweaks based on specific feedback
        
        // If pace is consistently slow, reduce intensity slightly
        if let paceVariance = analysis.avgPaceVariance, paceVariance > 5.0 {
            for workout in workouts {
                if (workout.type == .tempoRun || workout.type == .intervalWorkout),
                   let targetPace = workout.targetPaceSecondsPerKm {
                    let newPace = targetPace * 1.03 // 3% slower
                    adjustments.append(AdaptationPlan.WorkoutAdjustment(
                        workoutId: workout.id,
                        workoutDate: workout.date,
                        changeType: .intensityReduction,
                        oldValue: formatPace(targetPace),
                        newValue: formatPace(newPace),
                        reason: "Adjust pace targets to match current fitness"
                    ))
                }
            }
        }
        
        // If completion rate is borderline, don't make changes
        if analysis.completionRate < 0.8 {
            // Already handled by recovery protocol
        }
        
        return adjustments
    }
    
    // MARK: - Coach Message Generation
    
    private func generateCoachMessage(analysis: AnalysisResult, adjustments: [AdaptationPlan.WorkoutAdjustment], availability: TrainingAvailability) -> AdaptationPlan.CoachMessage {
        let severity: AdaptationPlan.CoachMessage.Severity
        let title: String
        let summary: String
        var details: [String] = []
        
        switch analysis.overallStatus {
        case .needsRest:
            severity = .warning
            title = "Recovery Week Ahead"
            if analysis.injuryStatus == .concerning {
                summary = "Your plan has been adjusted significantly to allow for injury recovery. Volume reduced by 15% and intensity lowered."
                details.append("⚠️ Multiple injury flags detected - prioritize rest and recovery")
            } else {
                summary = "Your body needs more recovery. Volume reduced by 15% and intensity lowered across all workouts."
                details.append("High fatigue levels detected - taking a recovery week")
            }
            
        case .needsRecovery:
            severity = .caution
            title = "Plan Adjusted for Recovery"
            summary = "Your training load has been reduced by 10% to support recovery while maintaining fitness."
            
            if let avgFatigue = analysis.avgFatigue, avgFatigue >= 3.5 {
                details.append("Elevated fatigue levels - reducing volume")
            }
            if analysis.completionRate < 0.7 {
                details.append("Lower completion rate - simplifying schedule")
            }
            if analysis.paceConsistency == .struggling {
                details.append("Pace targets adjusted to current fitness level")
            }
            
        case .excellent:
            severity = .positive
            title = "Great Week! Small Progression"
            summary = "Excellent performance last week. Your plan includes a small 5% volume increase to continue building fitness."
            details.append("✅ 90%+ completion rate")
            details.append("✅ Strong pace consistency")
            details.append("✅ Good recovery metrics")
            
        case .good:
            severity = .neutral
            title = "Plan Maintained"
            if adjustments.isEmpty {
                summary = "Your training is progressing well. No changes needed - stick with the current plan."
                details.append("Continue with planned workouts")
            } else {
                summary = "Minor adjustments made to better match your current fitness level."
                details.append("Small pace adjustments based on recent performance")
            }
        }
        
        // Add completion rate detail
        let completionPct = Int(analysis.completionRate * 100)
        details.append("Last week: \(completionPct)% of planned workouts completed")
        
        // Add specific adjustment count
        if !adjustments.isEmpty {
            details.append("\(adjustments.count) workout(s) adjusted for next week")
        }
        
        return AdaptationPlan.CoachMessage(
            title: title,
            summary: summary,
            details: details,
            severity: severity
        )
    }
    
    private func createNoChangesPlan(analysis: AnalysisResult) -> AdaptationPlan {
        return AdaptationPlan(
            createdAt: Date(),
            analysisResult: analysis,
            adjustments: [],
            coachMessage: AdaptationPlan.CoachMessage(
                title: "No Changes Needed",
                summary: "No upcoming workouts to adjust. Your plan continues as scheduled.",
                details: [],
                severity: .neutral
            )
        )
    }
    
    // MARK: - Helper Methods
    
    private func formatPace(_ secondsPerKm: Double) -> String {
        let minutes = Int(secondsPerKm / 60)
        let seconds = Int(secondsPerKm.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d /km", minutes, seconds)
    }
}
