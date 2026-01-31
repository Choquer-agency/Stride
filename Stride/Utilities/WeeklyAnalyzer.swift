import Foundation

/// Result of weekly workout analysis
struct AnalysisResult {
    let weekStartDate: Date
    let weekEndDate: Date
    
    // Workout completion metrics
    let plannedWorkouts: [PlannedWorkout]
    let completedWorkouts: [WorkoutSession]
    let completionRate: Double // 0.0 to 1.0
    
    // Performance metrics
    let avgPaceVariance: Double? // Negative = faster than target, positive = slower
    let avgHRDrift: Double? // Average HR drift percentage
    let avgRPE: Double? // Average effort rating
    let avgFatigue: Double? // Average fatigue level
    let injuryCount: Int // Number of workouts with injury flag
    
    // Detailed analysis
    let paceConsistency: PaceConsistency
    let fatigueStatus: FatigueStatus
    let injuryStatus: InjuryStatus
    let overallStatus: OverallStatus
    
    enum PaceConsistency {
        case excellent // Within 2% of target
        case good // Within 5% of target
        case moderate // Within 10% of target
        case struggling // More than 10% slower
        case noData
    }
    
    enum FatigueStatus {
        case fresh // Avg < 2.5
        case moderate // Avg 2.5-3.5
        case high // Avg 3.5-4.5
        case exhausted // Avg > 4.5
        case noData
    }
    
    enum InjuryStatus {
        case none
        case minor // 1 flag
        case concerning // 2+ flags
    }
    
    enum OverallStatus {
        case excellent // Ready for progression
        case good // Maintain current load
        case needsRecovery // Reduce load
        case needsRest // Significant reduction needed
    }
}

/// Analyzes past week's workout performance
class WeeklyAnalyzer {
    private let storageManager: StorageManager
    private let calendar = Calendar.current
    
    init(storageManager: StorageManager) {
        self.storageManager = storageManager
    }
    
    /// Analyze the past week's workouts
    func analyzeWeek(plan: TrainingPlan, referenceDate: Date = Date()) -> AnalysisResult {
        // Calculate week boundaries (last 7 days ending on referenceDate)
        let weekEndDate = calendar.startOfDay(for: referenceDate)
        guard let weekStartDate = calendar.date(byAdding: .day, value: -6, to: weekEndDate) else {
            return emptyResult(for: weekEndDate)
        }
        
        // Get planned workouts for this period
        let plannedWorkouts = plan.allWorkouts.filter { workout in
            let workoutDay = calendar.startOfDay(for: workout.date)
            return workoutDay >= weekStartDate && workoutDay <= weekEndDate
        }
        
        // Get completed workouts for this period
        let allWorkouts = storageManager.workouts
        let completedWorkouts = allWorkouts.filter { workout in
            let workoutDay = calendar.startOfDay(for: workout.startTime)
            return workoutDay >= weekStartDate && workoutDay <= weekEndDate
        }
        
        // Get workout feedback for this period
        let allFeedback = storageManager.loadAllWorkoutFeedback()
        let weekFeedback = allFeedback.filter { feedback in
            let feedbackDay = calendar.startOfDay(for: feedback.date)
            return feedbackDay >= weekStartDate && feedbackDay <= weekEndDate
        }
        
        // Calculate completion rate
        let completionRate = plannedWorkouts.isEmpty ? 0.0 : Double(completedWorkouts.count) / Double(plannedWorkouts.count)
        
        print("\n📊 WEEKLY ANALYSIS DEBUG")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("Period: \(weekStartDate) to \(weekEndDate)")
        print("Planned: \(plannedWorkouts.count), Completed: \(completedWorkouts.count)")
        print("Total feedback in system: \(allFeedback.count)")
        print("Feedback entries in week: \(weekFeedback.count)")
        
        // Calculate performance metrics (use feedback if available, fallback to old WorkoutSession fields)
        let paceVariance = calculatePaceVariance(planned: plannedWorkouts, completed: completedWorkouts)
        let hrDrift = calculateAverageHRDrift(workouts: completedWorkouts)
        let avgRPE = calculateAverageRPE(workouts: completedWorkouts, feedback: weekFeedback)
        let avgFatigue = calculateAverageFatigue(workouts: completedWorkouts, feedback: weekFeedback)
        let injuryCount = calculateInjuryCount(workouts: completedWorkouts, feedback: weekFeedback)
        
        print("\n📈 Performance Metrics:")
        print("  Completion Rate: \(String(format: "%.1f%%", completionRate * 100))")
        print("  Avg Pace Variance: \(paceVariance.map { String(format: "%.1f%%", $0) } ?? "N/A")")
        print("  Avg HR Drift: \(hrDrift.map { String(format: "%.1f%%", $0) } ?? "N/A")")
        print("  Avg RPE: \(avgRPE.map { String(format: "%.1f", $0) } ?? "N/A")")
        print("  Avg Fatigue: \(avgFatigue.map { String(format: "%.1f", $0) } ?? "N/A")")
        print("  Injury Count: \(injuryCount)")
        
        // Check for advanced injury/overreaching flags using feedback
        print("\n🔍 Advanced Analysis:")
        let injuryRiskFlags = analyzeInjuryRisk(feedback: weekFeedback)
        let overreachingFlags = analyzeOverreaching(feedback: weekFeedback)
        let gymFormIssues = analyzeGymFormIssues(feedback: allFeedback)
        
        print("\n🚩 Flags Summary:")
        print("  Injury Risk Flags: \(injuryRiskFlags.isEmpty ? "None" : injuryRiskFlags.joined(separator: ", "))")
        print("  Overreaching Flags: \(overreachingFlags.isEmpty ? "None" : overreachingFlags.joined(separator: ", "))")
        print("  Gym Form Issues: \(gymFormIssues ? "Yes" : "No")")
        
        // Determine status categories
        let paceConsistency = determinePaceConsistency(variance: paceVariance)
        let fatigueStatus = determineFatigueStatus(avgFatigue: avgFatigue)
        let injuryStatus = determineInjuryStatus(count: injuryCount, riskFlags: injuryRiskFlags)
        let overallStatus = determineOverallStatus(
            completionRate: completionRate,
            paceConsistency: paceConsistency,
            fatigueStatus: fatigueStatus,
            injuryStatus: injuryStatus,
            avgRPE: avgRPE,
            overreachingFlags: overreachingFlags,
            gymFormIssues: gymFormIssues
        )
        
        print("\n📋 Status Categories:")
        print("  Pace Consistency: \(paceConsistency)")
        print("  Fatigue Status: \(fatigueStatus)")
        print("  Injury Status: \(injuryStatus)")
        print("  Overall Status: \(overallStatus)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
        
        return AnalysisResult(
            weekStartDate: weekStartDate,
            weekEndDate: weekEndDate,
            plannedWorkouts: plannedWorkouts,
            completedWorkouts: completedWorkouts,
            completionRate: completionRate,
            avgPaceVariance: paceVariance,
            avgHRDrift: hrDrift,
            avgRPE: avgRPE,
            avgFatigue: avgFatigue,
            injuryCount: injuryCount,
            paceConsistency: paceConsistency,
            fatigueStatus: fatigueStatus,
            injuryStatus: injuryStatus,
            overallStatus: overallStatus
        )
    }
    
    // MARK: - Private Calculation Methods
    
    private func calculatePaceVariance(planned: [PlannedWorkout], completed: [WorkoutSession]) -> Double? {
        guard !completed.isEmpty else { return nil }
        
        var totalVariance: Double = 0
        var count = 0
        
        for workout in completed {
            // Find matching planned workout (by date)
            let workoutDay = calendar.startOfDay(for: workout.startTime)
            if let plannedWorkout = planned.first(where: { calendar.isDate($0.date, inSameDayAs: workoutDay) }),
               let targetPace = plannedWorkout.targetPaceSecondsPerKm,
               workout.avgPaceSecondsPerKm > 0 {
                
                let actualPace = workout.avgPaceSecondsPerKm
                let variance = ((actualPace - targetPace) / targetPace) * 100.0
                totalVariance += variance
                count += 1
            }
        }
        
        return count > 0 ? totalVariance / Double(count) : nil
    }
    
    private func calculateAverageHRDrift(workouts: [WorkoutSession]) -> Double? {
        // Calculate HR drift from splits data
        var totalDrift: Double = 0
        var count = 0
        
        for workout in workouts {
            let splits = workout.splits
            guard splits.count >= 3 else { continue }
            
            // Get first and last 3 splits
            let firstThree = splits.prefix(3).compactMap { $0.avgHeartRate }
            let lastThree = splits.suffix(3).compactMap { $0.avgHeartRate }
            
            guard !firstThree.isEmpty && !lastThree.isEmpty else { continue }
            
            let avgFirst = Double(firstThree.reduce(0, +)) / Double(firstThree.count)
            let avgLast = Double(lastThree.reduce(0, +)) / Double(lastThree.count)
            
            if avgFirst > 0 {
                let drift = ((avgLast - avgFirst) / avgFirst) * 100.0
                totalDrift += drift
                count += 1
            }
        }
        
        return count > 0 ? totalDrift / Double(count) : nil
    }
    
    private func calculateAverageRPE(workouts: [WorkoutSession], feedback: [WorkoutFeedback]) -> Double? {
        // Prefer feedback data, fallback to workout session data
        if !feedback.isEmpty {
            let rpeValues = feedback.map { $0.perceivedEffort }
            return Double(rpeValues.reduce(0, +)) / Double(rpeValues.count)
        }
        
        // Fallback to old effortRating from WorkoutSession
        let rpeValues = workouts.compactMap { $0.effortRating }
        guard !rpeValues.isEmpty else { return nil }
        return Double(rpeValues.reduce(0, +)) / Double(rpeValues.count)
    }
    
    private func calculateAverageFatigue(workouts: [WorkoutSession], feedback: [WorkoutFeedback]) -> Double? {
        // Prefer feedback data, fallback to workout session data
        if !feedback.isEmpty {
            let fatigueValues = feedback.map { $0.fatigueLevel }
            return Double(fatigueValues.reduce(0, +)) / Double(fatigueValues.count)
        }
        
        // Fallback to old fatigueLevel from WorkoutSession
        let fatigueValues = workouts.compactMap { $0.fatigueLevel }
        guard !fatigueValues.isEmpty else { return nil }
        return Double(fatigueValues.reduce(0, +)) / Double(fatigueValues.count)
    }
    
    private func calculateInjuryCount(workouts: [WorkoutSession], feedback: [WorkoutFeedback]) -> Int {
        // Prefer feedback data (painLevel >= 4), fallback to workout session injuryFlag
        if !feedback.isEmpty {
            return feedback.filter { $0.painLevel >= 4 }.count
        }
        
        // Fallback to old injuryFlag from WorkoutSession
        return workouts.filter { $0.injuryFlag == true }.count
    }
    
    // MARK: - WorkoutFeedback Analysis Methods
    
    /// Analyze injury risk based on pain patterns
    private func analyzeInjuryRisk(feedback: [WorkoutFeedback]) -> [String] {
        var flags: [String] = []
        
        print("🔍 Analyzing injury risk from \(feedback.count) feedback entries")
        
        // Rule 1: Pain level >= 7 once = high risk
        let highPainWorkouts = feedback.filter { $0.painLevel >= 7 }
        if !highPainWorkouts.isEmpty {
            flags.append("High pain level detected")
            print("  ⚠️ Rule 1: Found \(highPainWorkouts.count) workout(s) with pain >= 7")
        }
        
        // Rule 2: Pain level >= 4 two workouts in a row = watch
        if feedback.count > 1 {
            let sortedFeedback = feedback.sorted { $0.date < $1.date }
            print("  📅 Sorted feedback chronologically:")
            for (index, fb) in sortedFeedback.enumerated() {
                print("    [\(index)] Date: \(fb.date), Pain: \(fb.painLevel), Session ID: \(fb.workoutSessionId)")
            }
            
            for i in 1..<sortedFeedback.count {
                let prev = sortedFeedback[i-1]
                let curr = sortedFeedback[i]
                
                if prev.painLevel >= 4 && curr.painLevel >= 4 {
                    flags.append("Consecutive moderate pain")
                    print("  ⚠️ Rule 2: Consecutive moderate pain detected!")
                    print("    Previous: Pain \(prev.painLevel) on \(prev.date)")
                    print("    Current: Pain \(curr.painLevel) on \(curr.date)")
                    break
                }
            }
        } else {
            print("  ℹ️ Only \(feedback.count) feedback entry, skipping consecutive pain check")
        }
        
        // Rule 3: Same pain area appears 2+ times in 7 days = pattern
        var painAreaCounts: [InjuryArea: Int] = [:]
        for fb in feedback {
            if let areas = fb.painAreas {
                for area in areas {
                    painAreaCounts[area, default: 0] += 1
                }
            }
        }
        
        if !painAreaCounts.isEmpty {
            print("  📊 Pain area counts:")
            for (area, count) in painAreaCounts {
                print("    - \(area.displayName): \(count) occurrence(s)")
            }
        }
        
        for (area, count) in painAreaCounts where count >= 2 {
            flags.append("Recurring pain: \(area.displayName)")
            print("  ⚠️ Rule 3: Recurring pain in \(area.displayName)")
        }
        
        print("  ✅ Injury risk analysis complete: \(flags.count) flag(s) found")
        return flags
    }
    
    /// Analyze overreaching based on effort and fatigue patterns
    private func analyzeOverreaching(feedback: [WorkoutFeedback]) -> [String] {
        var flags: [String] = []
        
        print("🔍 Analyzing overreaching from \(feedback.count) feedback entries")
        
        // Rule: Effort >= 8 AND fatigue >= 4 for 2 workouts in a week
        let highLoadWorkouts = feedback.filter { $0.perceivedEffort >= 8 && $0.fatigueLevel >= 4 }
        if highLoadWorkouts.count >= 2 {
            flags.append("High effort + high fatigue pattern")
            print("  ⚠️ Found \(highLoadWorkouts.count) workout(s) with effort >= 8 AND fatigue >= 4")
        }
        
        // Rule: 2+ stopped early in rolling 14 days
        let stoppedEarlyCount = feedback.filter { $0.completionStatus == .stoppedEarly }.count
        if stoppedEarlyCount >= 2 {
            flags.append("Multiple workouts stopped early")
            print("  ⚠️ Found \(stoppedEarlyCount) workout(s) stopped early")
        }
        
        print("  ✅ Overreaching analysis complete: \(flags.count) flag(s) found")
        return flags
    }
    
    /// Analyze gym form issues
    private func analyzeGymFormIssues(feedback: [WorkoutFeedback]) -> Bool {
        // Rule: Form breakdown twice in last 2 weeks (14 days)
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let recentFeedback = feedback.filter { $0.date >= twoWeeksAgo }
        let formBreakdownCount = recentFeedback.filter { $0.formBreakdown == true }.count
        
        print("🔍 Analyzing gym form issues")
        print("  Feedback from last 14 days: \(recentFeedback.count)")
        print("  Form breakdown count: \(formBreakdownCount)")
        
        let hasIssues = formBreakdownCount >= 2
        if hasIssues {
            print("  ⚠️ Form breakdown detected \(formBreakdownCount) times in 14 days")
        } else {
            print("  ✅ No recurring form issues")
        }
        
        return hasIssues
    }
    
    // MARK: - Status Determination Methods
    
    private func determinePaceConsistency(variance: Double?) -> AnalysisResult.PaceConsistency {
        guard let variance = variance else { return .noData }
        
        let absVariance = abs(variance)
        if absVariance <= 2.0 {
            return .excellent
        } else if absVariance <= 5.0 {
            return .good
        } else if absVariance <= 10.0 {
            return .moderate
        } else {
            return .struggling
        }
    }
    
    private func determineFatigueStatus(avgFatigue: Double?) -> AnalysisResult.FatigueStatus {
        guard let avgFatigue = avgFatigue else { return .noData }
        
        if avgFatigue < 2.5 {
            return .fresh
        } else if avgFatigue < 3.5 {
            return .moderate
        } else if avgFatigue < 4.5 {
            return .high
        } else {
            return .exhausted
        }
    }
    
    private func determineInjuryStatus(count: Int, riskFlags: [String]) -> AnalysisResult.InjuryStatus {
        // Enhanced with risk flags
        if !riskFlags.isEmpty || count >= 2 {
            return .concerning
        } else if count == 1 {
            return .minor
        } else {
            return .none
        }
    }
    
    private func determineOverallStatus(
        completionRate: Double,
        paceConsistency: AnalysisResult.PaceConsistency,
        fatigueStatus: AnalysisResult.FatigueStatus,
        injuryStatus: AnalysisResult.InjuryStatus,
        avgRPE: Double?,
        overreachingFlags: [String],
        gymFormIssues: Bool
    ) -> AnalysisResult.OverallStatus {
        
        // Injury takes priority
        if injuryStatus == .concerning {
            return .needsRest
        }
        
        // Overreaching flags
        if !overreachingFlags.isEmpty {
            return .needsRecovery
        }
        
        // Gym form issues
        if gymFormIssues {
            return .needsRecovery
        }
        
        // High fatigue needs recovery
        if fatigueStatus == .exhausted || fatigueStatus == .high {
            return .needsRecovery
        }
        
        // Low completion rate indicates overload
        if completionRate < 0.7 {
            return .needsRecovery
        }
        
        // Consistently high RPE
        if let rpe = avgRPE, rpe >= 8.5 {
            return .needsRecovery
        }
        
        // Struggling with pace
        if paceConsistency == .struggling {
            return .needsRecovery
        }
        
        // Ready for progression
        if completionRate >= 0.9 &&
           (paceConsistency == .excellent || paceConsistency == .good) &&
           (fatigueStatus == .fresh || fatigueStatus == .moderate) &&
           injuryStatus == .none {
            return .excellent
        }
        
        // Default: maintain
        return .good
    }
    
    private func emptyResult(for date: Date) -> AnalysisResult {
        guard let weekStart = calendar.date(byAdding: .day, value: -6, to: date) else {
            return AnalysisResult(
                weekStartDate: date,
                weekEndDate: date,
                plannedWorkouts: [],
                completedWorkouts: [],
                completionRate: 0,
                avgPaceVariance: nil,
                avgHRDrift: nil,
                avgRPE: nil,
                avgFatigue: nil,
                injuryCount: 0,
                paceConsistency: .noData,
                fatigueStatus: .noData,
                injuryStatus: .none,
                overallStatus: .good
            )
        }
        
        return AnalysisResult(
            weekStartDate: weekStart,
            weekEndDate: date,
            plannedWorkouts: [],
            completedWorkouts: [],
            completionRate: 0,
            avgPaceVariance: nil,
            avgHRDrift: nil,
            avgRPE: nil,
            avgFatigue: nil,
            injuryCount: 0,
            paceConsistency: .noData,
            fatigueStatus: .noData,
            injuryStatus: .none,
            overallStatus: .good
        )
    }
}
