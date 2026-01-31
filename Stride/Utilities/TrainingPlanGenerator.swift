import Foundation

/// Generates rule-based training plans using Jack Daniels methodology
class TrainingPlanGenerator {
    
    private let movementBlockGenerator = MovementBlockGenerator()
    
    // MARK: - Main Generation Method
    
    /// Generate a complete training plan based on goal, baseline, and preferences
    func generatePlan(
        goal: Goal,
        baseline: BaselineAssessment?,
        preferences: TrainingPreferences,
        userProfile: UserTrainingProfile
    ) -> TrainingPlan {
        let weeksAvailable = max(1, goal.weeksRemaining)
        let startDate = Calendar.current.startOfDay(for: Date())
        
        // Build generation context for explainability
        let generationContext = buildGenerationContext(
            goal: goal,
            baseline: baseline,
            preferences: preferences
        )
        
        // 1. Determine periodization phases
        let phases = determinePeriodization(weeksAvailable: weeksAvailable, goalType: goal.type)
        
        // 2. Calculate weekly volume progression
        let volumeProgression = calculateVolumeProgression(
            goalDistance: goal.distanceKm ?? 21.0975,
            weeks: weeksAvailable,
            phases: phases,
            goalType: goal.type
        )
        
        // Track recent exercises for rotation
        var recentExercises: [String] = []
        
        // 3. Generate week-by-week structure
        var weeks: [WeekPlan] = []
        for weekNumber in 1...weeksAvailable {
            guard let weekStartDate = Calendar.current.date(byAdding: .weekOfYear, value: weekNumber - 1, to: startDate),
                  let weekEndDate = Calendar.current.date(byAdding: .day, value: 6, to: weekStartDate) else {
                print("⚠️ Failed to calculate week dates for week \(weekNumber)")
                continue
            }
            
            guard let currentPhase = phases.first(where: { $0.weekRange.contains(weekNumber) }) else {
                print("⚠️ No phase found for week \(weekNumber)")
                continue
            }
            
            let week = generateWeek(
                weekNumber: weekNumber,
                startDate: weekStartDate,
                endDate: weekEndDate,
                phase: currentPhase,
                targetVolume: volumeProgression[weekNumber] ?? 30.0,
                preferences: preferences,
                trainingPaces: baseline?.trainingPaces ?? goal.trainingPaces,
                goalPace: goal.trainingPaces?.racePace,
                goalDistance: goal.distanceKm ?? 21.0975,
                goalType: goal.type,
                userProfile: userProfile,
                recentExercises: &recentExercises
            )
            
            weeks.append(week)
        }
        
        return TrainingPlan(
            goalId: goal.id,
            startDate: startDate,
            eventDate: goal.eventDate,
            generationMethod: .ruleBased,
            totalWeeks: weeksAvailable,
            weeklyRunDays: preferences.weeklyRunDays,
            weeklyGymDays: preferences.weeklyGymDays,
            availability: preferences.getEffectiveAvailability(),
            phases: phases,
            weeks: weeks,
            generationContext: generationContext
        )
    }
    
    // MARK: - Generation Context Builder
    
    /// Build explainability context for the training plan
    private func buildGenerationContext(
        goal: Goal,
        baseline: BaselineAssessment?,
        preferences: TrainingPreferences
    ) -> PlanGenerationContext {
        // Determine baseline source and confidence
        let (baselineSource, baselineVDOT, baselineDate, confidenceLevel) = analyzeBaseline(baseline)
        
        // Determine goal influence on pacing
        let goalInfluence = determineGoalInfluence(goal: goal, baseline: baseline)
        
        // Identify any conservative constraints applied
        let constraints = identifyConstraints(goal: goal, baseline: baseline)
        
        return PlanGenerationContext(
            generationMethod: .ruleBased,
            baselineSource: baselineSource,
            baselineVDOT: baselineVDOT,
            baselineDate: baselineDate,
            goalInfluence: goalInfluence,
            confidenceLevel: confidenceLevel,
            constraintsApplied: constraints,
            llmStatus: .off, // Will be updated by TrainingPlanManager if LLM is used
            generatedAt: Date()
        )
    }
    
    /// Analyze baseline assessment and determine source/confidence
    private func analyzeBaseline(_ baseline: BaselineAssessment?) -> (
        source: PlanGenerationContext.BaselineSource,
        vdot: Double?,
        date: Date?,
        confidence: PlanGenerationContext.ConfidenceLevel
    ) {
        guard let baseline = baseline else {
            return (.none, nil, nil, .low)
        }
        
        // Determine source
        let source: PlanGenerationContext.BaselineSource
        switch baseline.method {
        case .recentRace:
            source = .recentRace
        case .guidedTest:
            source = .guidedTest
        case .timeTrial:
            source = .manualInput
        case .autoCalculated:
            source = .estimated
        case .garminSync:
            source = .recentRace // Treat Garmin as race data
        }
        
        // Determine confidence based on recency
        let ageInDays = Calendar.current.dateComponents([.day], from: baseline.assessmentDate, to: Date()).day ?? 0
        let confidence: PlanGenerationContext.ConfidenceLevel
        if ageInDays <= 90 {
            confidence = .high
        } else if ageInDays <= 180 {
            confidence = .medium
        } else {
            confidence = .low
        }
        
        return (source, baseline.vdot, baseline.assessmentDate, confidence)
    }
    
    /// Determine how goal influenced pacing decisions
    private func determineGoalInfluence(
        goal: Goal,
        baseline: BaselineAssessment?
    ) -> PlanGenerationContext.GoalInfluence {
        // Completion goals focus on endurance, not speed
        if goal.type == .completion {
            return .noTimeGoal
        }
        
        // If no baseline, we can't properly assess goal alignment
        guard let baseline = baseline,
              let goalPace = goal.trainingPaces?.racePace,
              let goalDistance = goal.distanceKm else {
            return .pacesConstrained
        }
        
        // Check if goal pace is realistic based on VDOT
        let predictedTime = VDOTCalculator.predictRaceTime(vdot: baseline.vdot, distanceKm: goalDistance)
        let predictedPace = predictedTime / goalDistance
        
        // If goal is more than 10% faster than predicted, it's constrained
        let paceRatio = goalPace / predictedPace
        if paceRatio < 0.9 {
            return .pacesConstrained
        } else {
            return .pacesAligned
        }
    }
    
    /// Identify conservative constraints applied during generation
    private func identifyConstraints(
        goal: Goal,
        baseline: BaselineAssessment?
    ) -> [String] {
        var constraints: [String] = []
        
        // No baseline constraint
        if baseline == nil {
            constraints.append("Using conservative default paces due to missing baseline")
        }
        
        // Old baseline constraint
        if let baseline = baseline {
            let ageInDays = Calendar.current.dateComponents([.day], from: baseline.assessmentDate, to: Date()).day ?? 0
            if ageInDays > 90 {
                constraints.append("Baseline is \(ageInDays) days old - consider updating for more accurate paces")
            }
        }
        
        // Aggressive goal constraint
        if goal.type != .completion,
           let baseline = baseline,
           let goalPace = goal.trainingPaces?.racePace,
           let goalDistance = goal.distanceKm {
            let predictedTime = VDOTCalculator.predictRaceTime(vdot: baseline.vdot, distanceKm: goalDistance)
            let predictedPace = predictedTime / goalDistance
            let paceRatio = goalPace / predictedPace
            
            if paceRatio < 0.9 {
                let percentFaster = Int((1.0 - paceRatio) * 100)
                constraints.append("Goal pace is \(percentFaster)% faster than current fitness suggests - building gradually")
            }
        }
        
        // Short timeline constraint
        if goal.weeksRemaining < 8 {
            constraints.append("Limited training time available - plan focuses on race readiness over volume building")
        }
        
        return constraints
    }
    
    // MARK: - Periodization
    
    /// Determine training phases based on available weeks
    private func determinePeriodization(weeksAvailable: Int, goalType: Goal.GoalType) -> [TrainingPhase] {
        var phases: [TrainingPhase] = []
        
        // Ensure we have at least 1 week
        guard weeksAvailable >= 1 else {
            return [TrainingPhase.baseBuilding(weeks: 1...1)]
        }
        
        // Completion goals use more conservative periodization
        if goalType == .completion {
            return determineCompletionPeriodization(weeksAvailable: weeksAvailable)
        }
        
        if weeksAvailable <= 8 {
            // Short plan: Base (50%) → Build (25%) → Peak (15%) → Taper (10%)
            let baseWeeks = max(1, Int(Double(weeksAvailable) * 0.5))
            let buildWeeks = max(1, Int(Double(weeksAvailable) * 0.25))
            let peakWeeks = max(1, Int(Double(weeksAvailable) * 0.15))
            let taperWeeks = max(1, weeksAvailable - baseWeeks - buildWeeks - peakWeeks)
            
            var currentWeek = 1
            let baseEnd = currentWeek + baseWeeks - 1
            phases.append(.baseBuilding(weeks: currentWeek...baseEnd))
            
            currentWeek = baseEnd + 1
            let buildEnd = min(currentWeek + buildWeeks - 1, weeksAvailable)
            if currentWeek <= buildEnd {
                phases.append(.buildUp(weeks: currentWeek...buildEnd))
            }
            
            currentWeek = buildEnd + 1
            let peakEnd = min(currentWeek + peakWeeks - 1, weeksAvailable)
            if currentWeek <= peakEnd {
                phases.append(.peakTraining(weeks: currentWeek...peakEnd))
            }
            
            currentWeek = peakEnd + 1
            if currentWeek <= weeksAvailable {
                phases.append(.taper(weeks: currentWeek...weeksAvailable))
            }
            
        } else if weeksAvailable <= 12 {
            // Standard plan: Base (50%) → Build (30%) → Peak (10%) → Taper (10%)
            let baseWeeks = max(1, Int(Double(weeksAvailable) * 0.5))
            let buildWeeks = max(1, Int(Double(weeksAvailable) * 0.3))
            let peakWeeks = max(1, Int(Double(weeksAvailable) * 0.1))
            let taperWeeks = max(1, weeksAvailable - baseWeeks - buildWeeks - peakWeeks)
            
            var currentWeek = 1
            let baseEnd = currentWeek + baseWeeks - 1
            phases.append(.baseBuilding(weeks: currentWeek...baseEnd))
            
            currentWeek = baseEnd + 1
            let buildEnd = min(currentWeek + buildWeeks - 1, weeksAvailable)
            if currentWeek <= buildEnd {
                phases.append(.buildUp(weeks: currentWeek...buildEnd))
            }
            
            currentWeek = buildEnd + 1
            let peakEnd = min(currentWeek + peakWeeks - 1, weeksAvailable)
            if currentWeek <= peakEnd {
                phases.append(.peakTraining(weeks: currentWeek...peakEnd))
            }
            
            currentWeek = peakEnd + 1
            if currentWeek <= weeksAvailable {
                phases.append(.taper(weeks: currentWeek...weeksAvailable))
            }
            
        } else if weeksAvailable <= 16 {
            // Medium plan: Base (40%) → Build (35%) → Peak (15%) → Taper (10%)
            let baseWeeks = max(1, Int(Double(weeksAvailable) * 0.4))
            let buildWeeks = max(1, Int(Double(weeksAvailable) * 0.35))
            let peakWeeks = max(1, Int(Double(weeksAvailable) * 0.15))
            let taperWeeks = max(1, weeksAvailable - baseWeeks - buildWeeks - peakWeeks)
            
            var currentWeek = 1
            let baseEnd = currentWeek + baseWeeks - 1
            phases.append(.baseBuilding(weeks: currentWeek...baseEnd))
            
            currentWeek = baseEnd + 1
            let buildEnd = min(currentWeek + buildWeeks - 1, weeksAvailable)
            if currentWeek <= buildEnd {
                phases.append(.buildUp(weeks: currentWeek...buildEnd))
            }
            
            currentWeek = buildEnd + 1
            let peakEnd = min(currentWeek + peakWeeks - 1, weeksAvailable)
            if currentWeek <= peakEnd {
                phases.append(.peakTraining(weeks: currentWeek...peakEnd))
            }
            
            currentWeek = peakEnd + 1
            if currentWeek <= weeksAvailable {
                phases.append(.taper(weeks: currentWeek...weeksAvailable))
            }
            
        } else {
            // Long plan: Base (35%) → Build (40%) → Peak (15%) → Taper (10%)
            let baseWeeks = max(1, Int(Double(weeksAvailable) * 0.35))
            let buildWeeks = max(1, Int(Double(weeksAvailable) * 0.40))
            let peakWeeks = max(1, Int(Double(weeksAvailable) * 0.15))
            let taperWeeks = max(1, weeksAvailable - baseWeeks - buildWeeks - peakWeeks)
            
            var currentWeek = 1
            let baseEnd = currentWeek + baseWeeks - 1
            phases.append(.baseBuilding(weeks: currentWeek...baseEnd))
            
            currentWeek = baseEnd + 1
            let buildEnd = min(currentWeek + buildWeeks - 1, weeksAvailable)
            if currentWeek <= buildEnd {
                phases.append(.buildUp(weeks: currentWeek...buildEnd))
            }
            
            currentWeek = buildEnd + 1
            let peakEnd = min(currentWeek + peakWeeks - 1, weeksAvailable)
            if currentWeek <= peakEnd {
                phases.append(.peakTraining(weeks: currentWeek...peakEnd))
            }
            
            currentWeek = peakEnd + 1
            if currentWeek <= weeksAvailable {
                phases.append(.taper(weeks: currentWeek...weeksAvailable))
            }
        }
        
        // Fallback: if no phases were created, create a simple base phase
        if phases.isEmpty {
            phases.append(.baseBuilding(weeks: 1...weeksAvailable))
        }
        
        return phases
    }
    
    /// Determine periodization for completion goals (more conservative, longer taper)
    private func determineCompletionPeriodization(weeksAvailable: Int) -> [TrainingPhase] {
        var phases: [TrainingPhase] = []
        
        if weeksAvailable <= 8 {
            // Short plan: Base (60%) → Build (20%) → Taper (20%)
            let baseWeeks = max(1, Int(Double(weeksAvailable) * 0.6))
            let buildWeeks = max(1, Int(Double(weeksAvailable) * 0.2))
            let taperWeeks = max(1, weeksAvailable - baseWeeks - buildWeeks)
            
            var currentWeek = 1
            let baseEnd = currentWeek + baseWeeks - 1
            phases.append(.baseBuilding(weeks: currentWeek...baseEnd))
            
            currentWeek = baseEnd + 1
            let buildEnd = min(currentWeek + buildWeeks - 1, weeksAvailable)
            if currentWeek <= buildEnd {
                phases.append(.buildUp(weeks: currentWeek...buildEnd))
            }
            
            currentWeek = buildEnd + 1
            if currentWeek <= weeksAvailable {
                phases.append(.taper(weeks: currentWeek...weeksAvailable))
            }
            
        } else if weeksAvailable <= 16 {
            // Standard completion plan: Base (50%) → Build (30%) → Taper (20%)
            let baseWeeks = max(1, Int(Double(weeksAvailable) * 0.5))
            let buildWeeks = max(1, Int(Double(weeksAvailable) * 0.3))
            let taperWeeks = max(1, weeksAvailable - baseWeeks - buildWeeks)
            
            var currentWeek = 1
            let baseEnd = currentWeek + baseWeeks - 1
            phases.append(.baseBuilding(weeks: currentWeek...baseEnd))
            
            currentWeek = baseEnd + 1
            let buildEnd = min(currentWeek + buildWeeks - 1, weeksAvailable)
            if currentWeek <= buildEnd {
                phases.append(.buildUp(weeks: currentWeek...buildEnd))
            }
            
            currentWeek = buildEnd + 1
            if currentWeek <= weeksAvailable {
                phases.append(.taper(weeks: currentWeek...weeksAvailable))
            }
            
        } else {
            // Long completion plan: Base (45%) → Build (35%) → Taper (20%)
            let baseWeeks = max(1, Int(Double(weeksAvailable) * 0.45))
            let buildWeeks = max(1, Int(Double(weeksAvailable) * 0.35))
            let taperWeeks = max(1, weeksAvailable - baseWeeks - buildWeeks)
            
            var currentWeek = 1
            let baseEnd = currentWeek + baseWeeks - 1
            phases.append(.baseBuilding(weeks: currentWeek...baseEnd))
            
            currentWeek = baseEnd + 1
            let buildEnd = min(currentWeek + buildWeeks - 1, weeksAvailable)
            if currentWeek <= buildEnd {
                phases.append(.buildUp(weeks: currentWeek...buildEnd))
            }
            
            currentWeek = buildEnd + 1
            if currentWeek <= weeksAvailable {
                phases.append(.taper(weeks: currentWeek...weeksAvailable))
            }
        }
        
        // Fallback
        if phases.isEmpty {
            phases.append(.baseBuilding(weeks: 1...weeksAvailable))
        }
        
        return phases
    }
    
    // MARK: - Volume Progression
    
    /// Calculate weekly volume progression based on goal and phases
    private func calculateVolumeProgression(
        goalDistance: Double,
        weeks: Int,
        phases: [TrainingPhase],
        goalType: Goal.GoalType
    ) -> [Int: Double] {
        var progression: [Int: Double] = [:]
        
        // Determine base weekly volume based on goal distance
        let baseVolume = determineBaseVolume(for: goalDistance, goalType: goalType)
        
        // Completion goals use more conservative progression
        let peakMultiplier = goalType == .completion ? 1.05 : 1.1  // 105% vs 110%
        let startMultiplier = goalType == .completion ? 0.75 : 0.7  // 75% vs 70%
        
        let peakVolume = baseVolume * peakMultiplier
        let startVolume = baseVolume * startMultiplier
        
        for weekNumber in 1...weeks {
            // Find which phase this week is in
            guard let phase = phases.first(where: { $0.weekRange.contains(weekNumber) }) else {
                progression[weekNumber] = baseVolume
                continue
            }
            
            let phaseProgress = Double(weekNumber - phase.weekRange.lowerBound) / Double(phase.weekRange.count)
            
            switch phase.name {
            case "Base Building":
                // Gradual build from start to base volume
                progression[weekNumber] = startVolume + (baseVolume - startVolume) * phaseProgress
                
            case "Build Up":
                // Continue building to peak volume
                progression[weekNumber] = baseVolume + (peakVolume - baseVolume) * phaseProgress
                
            case "Peak Training":
                // Maintain peak volume
                progression[weekNumber] = peakVolume
                
            case "Taper":
                // Reduce volume to 40-50% for taper
                let taperVolume = baseVolume * 0.45
                progression[weekNumber] = peakVolume - (peakVolume - taperVolume) * phaseProgress
                
            default:
                progression[weekNumber] = baseVolume
            }
        }
        
        return progression
    }
    
    /// Determine appropriate base weekly volume based on goal distance
    private func determineBaseVolume(for goalDistance: Double, goalType: Goal.GoalType = .race) -> Double {
        var baseVolume: Double
        
        if goalDistance <= 5.0 {
            baseVolume = 25.0  // 5K: ~25km/week
        } else if goalDistance <= 10.0 {
            baseVolume = 35.0  // 10K: ~35km/week
        } else if goalDistance <= 21.1 {
            baseVolume = 50.0  // Half Marathon: ~50km/week
        } else if goalDistance <= 42.2 {
            baseVolume = 70.0  // Marathon: ~70km/week
        } else {
            // Ultra distances: scale up gradually
            baseVolume = 70.0 + (goalDistance - 42.2) * 0.5  // Add 0.5km/week per km over marathon
            baseVolume = min(baseVolume, 100.0)  // Cap at 100km/week
        }
        
        // Completion goals increase base volume by 10% for better endurance
        if goalType == .completion && goalDistance > 42.2 {
            baseVolume *= 1.1
        }
        
        return baseVolume
    }
    
    // MARK: - Week Generation
    
    /// Generate a complete week of workouts
    private func generateWeek(
        weekNumber: Int,
        startDate: Date,
        endDate: Date,
        phase: TrainingPhase,
        targetVolume: Double,
        preferences: TrainingPreferences,
        trainingPaces: TrainingPaces?,
        goalPace: Double?,
        goalDistance: Double,
        goalType: Goal.GoalType,
        userProfile: UserTrainingProfile,
        recentExercises: inout [String]
    ) -> WeekPlan {
        var workouts: [PlannedWorkout] = []
        let calendar = Calendar.current
        
        // Get effective availability from preferences
        let availability = preferences.getEffectiveAvailability()
        let usableDays = Array(availability.availableDays).sorted()
        
        // Calculate long run distance (25-35% of weekly volume)
        let longRunDistance = min(targetVolume * 0.30, getMaxLongRunDistance(phase: phase))
        
        // Remaining volume for other runs
        let remainingVolume = targetVolume - longRunDistance
        let otherRunDays = max(0, usableDays.count - 1)  // Subtract long run day
        let avgOtherRunDistance = otherRunDays > 0 ? remainingVolume / Double(otherRunDays) : 0
        
        // Determine workout distribution based on available days and phase
        let workoutPlan = planWorkoutsForWeek(
            availableDays: usableDays.count,
            weekNumber: weekNumber,
            phase: phase,
            preferences: preferences,
            goalType: goalType
        )
        
        // Map workouts to specific days
        var assignedWorkouts: [Int: PlannedWorkout] = [:]
        
        // 1. Assign long run to preferred day (if available)
        let longRunDay: Int
        if let preferredDay = availability.preferredLongRunDay,
           availability.availableDays.contains(preferredDay) {
            longRunDay = preferredDay
        } else if !usableDays.isEmpty {
            longRunDay = usableDays[0]  // Default to first available day
        } else {
            longRunDay = -1  // No available days
        }
        
        if longRunDay >= 0, let date = calculateDate(for: longRunDay, in: startDate, calendar: calendar) {
            assignedWorkouts[longRunDay] = generateLongRun(
                date: date,
                distance: longRunDistance,
                trainingPaces: trainingPaces
            )
        }
        
        // 2. Assign other workouts to remaining available days
        var workoutIndex = 0
        var lastGymDay: Int? = nil  // Track last gym day to enforce spacing
        
        for dayOfWeek in usableDays where dayOfWeek != longRunDay {
            guard workoutIndex < workoutPlan.count else { break }
            guard let date = calculateDate(for: dayOfWeek, in: startDate, calendar: calendar) else {
                continue
            }
            
            let plannedType = workoutPlan[workoutIndex]
            
            // Check if this is a gym workout and enforce spacing
            if plannedType == .gym {
                if let lastGym = lastGymDay {
                    let dayGap = abs(dayOfWeek - lastGym)
                    let actualGap = min(dayGap, 7 - dayGap)  // Handle week wrap-around
                    
                    // Require at least 2 days between gym sessions
                    if actualGap < 2 {
                        // Skip this gym workout for now - try to place it later
                        workoutIndex += 1
                        continue
                    }
                }
            }
            
            if plannedType == .gym {
                let gymWorkout = generateGymWorkout(
                    date: date,
                    phase: phase,
                    goalDistance: goalDistance,
                    availableEquipment: userProfile.availableEquipment,
                    recentExercises: recentExercises
                )
                assignedWorkouts[dayOfWeek] = gymWorkout
                lastGymDay = dayOfWeek
                
                // Track exercises for rotation
                if let exercises = gymWorkout.exerciseProgram {
                    recentExercises.append(contentsOf: exercises.map { $0.exerciseSlug })
                    if recentExercises.count > 20 {
                        recentExercises = Array(recentExercises.suffix(20))
                    }
                }
            } else {
                assignedWorkouts[dayOfWeek] = generateWorkout(
                    date: date,
                    type: plannedType,
                    distance: avgOtherRunDistance,
                    phase: phase,
                    trainingPaces: trainingPaces,
                    goalPace: goalPace,
                    goalType: goalType
                )
            }
            
            workoutIndex += 1
        }
        
        // 2b. Second pass: Try to place any skipped gym workouts
        if workoutIndex < workoutPlan.count {
            for dayOfWeek in usableDays where dayOfWeek != longRunDay && assignedWorkouts[dayOfWeek] == nil {
                guard workoutIndex < workoutPlan.count else { break }
                guard let date = calculateDate(for: dayOfWeek, in: startDate, calendar: calendar) else {
                    continue
                }
                
                let plannedType = workoutPlan[workoutIndex]
                
                if plannedType == .gym {
                    let gymWorkout = generateGymWorkout(
                        date: date,
                        phase: phase,
                        goalDistance: goalDistance,
                        availableEquipment: userProfile.availableEquipment,
                        recentExercises: recentExercises
                    )
                    assignedWorkouts[dayOfWeek] = gymWorkout
                    
                    // Track exercises for rotation
                    if let exercises = gymWorkout.exerciseProgram {
                        recentExercises.append(contentsOf: exercises.map { $0.exerciseSlug })
                        if recentExercises.count > 20 {
                            recentExercises = Array(recentExercises.suffix(20))
                        }
                    }
                } else {
                    assignedWorkouts[dayOfWeek] = generateWorkout(
                        date: date,
                        type: plannedType,
                        distance: avgOtherRunDistance,
                        phase: phase,
                        trainingPaces: trainingPaces,
                        goalPace: goalPace,
                        goalType: goalType
                    )
                }
                
                workoutIndex += 1
            }
        }
        
        // 3. Generate rest day markers for explicitly marked rest days
        for dayOfWeek in availability.restDays {
            guard let date = calculateDate(for: dayOfWeek, in: startDate, calendar: calendar) else {
                continue
            }
            assignedWorkouts[dayOfWeek] = generateRestDay(date: date)
        }
        
        // 4. Build final workout list (unavailable days are omitted entirely)
        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate) else {
                continue
            }
            let dayOfWeek = calendar.component(.weekday, from: date) - 1  // 0 = Sunday
            
            if let workout = assignedWorkouts[dayOfWeek] {
                workouts.append(workout)
            }
            // If no workout assigned and not rest/available, it's unavailable - skip entirely
        }
        
        // Add warmup and cooldown blocks to all workouts
        let workoutsWithMovementBlocks = workouts.map { workout in
            movementBlockGenerator.addMovementBlocks(to: workout)
        }
        
        return WeekPlan(
            weekNumber: weekNumber,
            startDate: startDate,
            endDate: endDate,
            phase: phase,
            targetWeeklyKm: targetVolume,
            workouts: workoutsWithMovementBlocks
        )
    }
    
    /// Calculate date for a specific day of week within a week
    private func calculateDate(for dayOfWeek: Int, in weekStartDate: Date, calendar: Calendar) -> Date? {
        let weekStartDay = calendar.component(.weekday, from: weekStartDate) - 1
        let dayOffset = (dayOfWeek - weekStartDay + 7) % 7
        return calendar.date(byAdding: .day, value: dayOffset, to: weekStartDate)
    }
    
    /// Plan which workout types to do based on available days per week
    private func planWorkoutsForWeek(
        availableDays: Int,
        weekNumber: Int,
        phase: TrainingPhase,
        preferences: TrainingPreferences,
        goalType: Goal.GoalType
    ) -> [PlannedWorkout.WorkoutType] {
        // Long run is handled separately, so we plan for (availableDays - 1)
        let otherDays = max(0, availableDays - 1)
        var workouts: [PlannedWorkout.WorkoutType] = []
        
        // Completion goals emphasize easy/base miles over intensity
        let isCompletionGoal = goalType == .completion
        
        switch availableDays {
        case 0:
            // No workouts possible
            break
            
        case 1:
            // Only long run (handled separately)
            // Alternate quality run on odd weeks if in later phases
            if weekNumber % 2 == 1 && (phase.name == "Peak Training" || phase.name == "Build Up") {
                // Replace long run with quality run on odd weeks
                // This is handled by caller - just return empty
            }
            break
            
        case 2:
            // Long run + 1 quality workout
            workouts.append(getQualityWorkout(for: phase, isCompletionGoal: isCompletionGoal))
            
        case 3:
            // Long run + easy + quality
            workouts.append(.easyRun)
            workouts.append(getQualityWorkout(for: phase, isCompletionGoal: isCompletionGoal))
            
        case 4:
            // Long run + easy + tempo + intervals (or 2 easy + 1 quality)
            if phase.name == "Base Building" || isCompletionGoal {
                workouts.append(.easyRun)
                workouts.append(.easyRun)
                workouts.append(.tempoRun)
            } else {
                workouts.append(.easyRun)
                workouts.append(.tempoRun)
                if preferences.weeklyGymDays > 0 {
                    workouts.append(.gym)
                } else {
                    workouts.append(.intervalWorkout)
                }
            }
            
        case 5:
            // Long run + 2 easy + tempo + intervals/gym
            workouts.append(.easyRun)
            workouts.append(.tempoRun)
            workouts.append(.easyRun)
            if preferences.weeklyGymDays > 0 {
                workouts.append(.gym)
            } else if !isCompletionGoal {
                workouts.append(.intervalWorkout)
            } else {
                workouts.append(.easyRun)  // Extra easy run for completion goals
            }
            
        case 6, 7:
            // Full distribution: long run + 2-3 easy + tempo + intervals + gym
            workouts.append(.easyRun)
            workouts.append(.tempoRun)
            workouts.append(.easyRun)
            
            if isCompletionGoal {
                // Completion goals: more easy runs, less intensity
                workouts.append(.easyRun)
                if preferences.weeklyGymDays >= 1 {
                    workouts.append(.gym)
                } else {
                    workouts.append(.easyRun)
                }
            } else if preferences.weeklyGymDays >= 2 {
                // FIXED: Don't add consecutive gym days - they'll be properly spaced in assignment
                workouts.append(.intervalWorkout)
                workouts.append(.gym)
                workouts.append(.gym)  // Will be separated by algorithm below
            } else if preferences.weeklyGymDays == 1 {
                workouts.append(.gym)
                workouts.append(.intervalWorkout)
            } else {
                workouts.append(.intervalWorkout)
                workouts.append(.easyRun)
            }
            
            // Add one more easy if 7 days
            if availableDays == 7 {
                workouts.append(.easyRun)
            }
            
        default:
            break
        }
        
        return workouts
    }
    
    /// Get appropriate quality workout for phase
    private func getQualityWorkout(for phase: TrainingPhase, isCompletionGoal: Bool = false) -> PlannedWorkout.WorkoutType {
        // Completion goals avoid high-intensity work, stick to tempo
        if isCompletionGoal {
            return .tempoRun
        }
        
        switch phase.name {
        case "Base Building":
            return .tempoRun
        case "Build Up":
            return .intervalWorkout
        case "Peak Training":
            // FIXED: Peak training should include race pace practice, not just intervals
            return .raceSimulation
        case "Taper":
            return .raceSimulation
        default:
            return .tempoRun
        }
    }
    
    /// Get maximum long run distance for phase
    private func getMaxLongRunDistance(phase: TrainingPhase) -> Double {
        switch phase.name {
        case "Base Building":
            return 18.0  // Cap at 18km during base
        case "Build Up":
            return 25.0  // Cap at 25km during build
        case "Peak Training":
            return 32.0  // Cap at 32km during peak
        case "Taper":
            return 15.0  // Reduce for taper
        default:
            return 20.0
        }
    }
    
    // MARK: - Workout Generation
    
    /// Generate a specific workout
    private func generateWorkout(
        date: Date,
        type: PlannedWorkout.WorkoutType,
        distance: Double,
        phase: TrainingPhase,
        trainingPaces: TrainingPaces?,
        goalPace: Double?,
        goalType: Goal.GoalType
    ) -> PlannedWorkout {
        switch type {
        case .easyRun:
            return generateEasyRun(date: date, distance: distance, trainingPaces: trainingPaces)
            
        case .tempoRun:
            return generateTempoRun(date: date, distance: distance, trainingPaces: trainingPaces, goalType: goalType, phase: phase, goalPace: goalPace)
            
        case .intervalWorkout:
            return generateIntervalWorkout(date: date, trainingPaces: trainingPaces)
            
        case .raceSimulation:
            return generateRaceSimulation(date: date, distance: distance, goalPace: goalPace, trainingPaces: trainingPaces, goalType: goalType)
            
        case .recoveryRun:
            return generateRecoveryRun(date: date, distance: distance * 0.6, trainingPaces: trainingPaces)
            
        default:
            return generateEasyRun(date: date, distance: distance, trainingPaces: trainingPaces)
        }
    }
    
    /// Generate easy run workout
    private func generateEasyRun(date: Date, distance: Double, trainingPaces: TrainingPaces?) -> PlannedWorkout {
        let pace = trainingPaces?.easy.midpoint ?? 360.0  // 6:00/km default
        
        return PlannedWorkout(
            date: date,
            type: .easyRun,
            title: "Easy Run",
            description: "Comfortable, conversational pace. Should feel effortless.",
            targetDistanceKm: distance,
            targetPaceSecondsPerKm: pace
        )
    }
    
    /// Generate long run workout
    private func generateLongRun(date: Date, distance: Double, trainingPaces: TrainingPaces?) -> PlannedWorkout {
        let pace = trainingPaces?.longRun.midpoint ?? 360.0  // 6:00/km default
        
        return PlannedWorkout(
            date: date,
            type: .longRun,
            title: "Long Run",
            description: "Steady aerobic pace. Build endurance and mental toughness.",
            targetDistanceKm: distance,
            targetPaceSecondsPerKm: pace
        )
    }
    
    /// Generate tempo run with intervals
    private func generateTempoRun(date: Date, distance: Double, trainingPaces: TrainingPaces?, goalType: Goal.GoalType = .race, phase: TrainingPhase, goalPace: Double?) -> PlannedWorkout {
        var tempoPace = trainingPaces?.threshold ?? 330.0  // 5:30/km default
        let easyPace = trainingPaces?.easy.midpoint ?? 360.0
        
        // FIXED: Progressive pacing in peak phase
        // If in peak phase and goal pace is faster than threshold, use intermediate pace
        if phase.name == "Peak Training", let goalPace = goalPace, goalPace < tempoPace {
            // Use midpoint between threshold and goal pace for peak tempo runs
            tempoPace = tempoPace - ((tempoPace - goalPace) * 0.5)
        }
        
        let tempoDistance = distance * 0.6  // 60% at tempo
        let warmupCooldown = distance * 0.2  // 20% each for warmup/cooldown
        
        // Adjust description for completion goals
        let workDescription = goalType == .completion
            ? "Steady effort at comfortable-hard pace - focus on sustained aerobic work"
            : "Tempo at threshold pace - comfortably hard"
        
        let mainDescription = goalType == .completion
            ? "Sustained aerobic effort. Focus on consistency and comfort."
            : "Comfortably hard sustained effort at threshold pace."
        
        let intervals: [PlannedWorkout.Interval] = [
            PlannedWorkout.Interval(
                order: 1,
                type: .warmup,
                distanceKm: warmupCooldown,
                targetPaceSecondsPerKm: easyPace,
                description: "Warmup at easy pace"
            ),
            PlannedWorkout.Interval(
                order: 2,
                type: .work,
                distanceKm: tempoDistance,
                targetPaceSecondsPerKm: tempoPace,
                description: workDescription
            ),
            PlannedWorkout.Interval(
                order: 3,
                type: .cooldown,
                distanceKm: warmupCooldown,
                targetPaceSecondsPerKm: easyPace,
                description: "Cooldown at easy pace"
            )
        ]
        
        return PlannedWorkout(
            date: date,
            type: .tempoRun,
            title: "Tempo Run",
            description: mainDescription,
            targetDistanceKm: distance,
            targetPaceSecondsPerKm: tempoPace,
            intervals: intervals
        )
    }
    
    /// Generate interval workout
    private func generateIntervalWorkout(date: Date, trainingPaces: TrainingPaces?) -> PlannedWorkout {
        let intervalPace = trainingPaces?.interval ?? 300.0  // 5:00/km default
        let easyPace = trainingPaces?.easy.midpoint ?? 360.0
        let recoveryPace = trainingPaces?.easy.max ?? 390.0
        
        var intervals: [PlannedWorkout.Interval] = []
        
        // Warmup
        intervals.append(PlannedWorkout.Interval(
            order: 1,
            type: .warmup,
            distanceKm: 2.0,
            targetPaceSecondsPerKm: easyPace,
            description: "Warmup at easy pace"
        ))
        
        // 6x800m intervals with 400m recovery
        for rep in 1...6 {
            intervals.append(PlannedWorkout.Interval(
                order: intervals.count + 1,
                type: .work,
                distanceKm: 0.8,
                targetPaceSecondsPerKm: intervalPace,
                description: "800m repeat #\(rep) at interval pace"
            ))
            
            if rep < 6 {
                intervals.append(PlannedWorkout.Interval(
                    order: intervals.count + 1,
                    type: .recovery,
                    distanceKm: 0.4,
                    targetPaceSecondsPerKm: recoveryPace,
                    description: "400m recovery jog"
                ))
            }
        }
        
        // Cooldown
        intervals.append(PlannedWorkout.Interval(
            order: intervals.count + 1,
            type: .cooldown,
            distanceKm: 2.0,
            targetPaceSecondsPerKm: easyPace,
            description: "Cooldown at easy pace"
        ))
        
        let totalDistance = intervals.compactMap { $0.distanceKm }.reduce(0, +)
        
        return PlannedWorkout(
            date: date,
            type: .intervalWorkout,
            title: "Interval Workout",
            description: "6x800m at VO2max pace with 400m recoveries. Focus on form and consistent splits.",
            targetDistanceKm: totalDistance,
            targetPaceSecondsPerKm: intervalPace,
            intervals: intervals
        )
    }
    
    /// Generate race simulation workout
    private func generateRaceSimulation(date: Date, distance: Double, goalPace: Double?, trainingPaces: TrainingPaces?, goalType: Goal.GoalType = .race) -> PlannedWorkout {
        // For completion goals or when goalPace is nil, use threshold pace instead
        let targetPace: Double
        let description: String
        let workDescription: String
        
        if goalType == .completion || goalPace == nil {
            // Use threshold pace for sustained effort runs
            targetPace = trainingPaces?.threshold ?? 330.0
            description = "Sustained effort run. Focus on maintaining a steady, comfortable-hard pace."
            workDescription = "Sustained effort - practice maintaining steady aerobic pace"
        } else {
            targetPace = goalPace!
            description = "Practice your goal race pace. Focus on efficiency and rhythm."
            workDescription = "Race pace segment - practice goal pace"
        }
        
        let easyPace = targetPace + 30.0
        let sustainedDistance = distance * 0.5  // 50% at target pace
        let warmupCooldown = distance * 0.25  // 25% each
        
        let intervals: [PlannedWorkout.Interval] = [
            PlannedWorkout.Interval(
                order: 1,
                type: .warmup,
                distanceKm: warmupCooldown,
                targetPaceSecondsPerKm: easyPace,
                description: "Warmup"
            ),
            PlannedWorkout.Interval(
                order: 2,
                type: .work,
                distanceKm: sustainedDistance,
                targetPaceSecondsPerKm: targetPace,
                description: workDescription
            ),
            PlannedWorkout.Interval(
                order: 3,
                type: .cooldown,
                distanceKm: warmupCooldown,
                targetPaceSecondsPerKm: easyPace,
                description: "Cooldown"
            )
        ]
        
        let title = goalType == .completion ? "Sustained Effort Run" : "Race Pace Run"
        
        return PlannedWorkout(
            date: date,
            type: .raceSimulation,
            title: title,
            description: description,
            targetDistanceKm: distance,
            targetPaceSecondsPerKm: targetPace,
            intervals: intervals
        )
    }
    
    /// Generate recovery run
    private func generateRecoveryRun(date: Date, distance: Double, trainingPaces: TrainingPaces?) -> PlannedWorkout {
        let pace = trainingPaces?.easy.max ?? 390.0  // Slower end of easy pace
        
        return PlannedWorkout(
            date: date,
            type: .recoveryRun,
            title: "Recovery Run",
            description: "Very easy effort. Focus on active recovery and loosening up.",
            targetDistanceKm: distance,
            targetPaceSecondsPerKm: pace
        )
    }
    
    /// Generate gym/strength workout with intent only (exercises generated on-demand when workout is opened)
    private func generateGymWorkout(
        date: Date,
        phase: TrainingPhase,
        goalDistance: Double,
        availableEquipment: Set<GymEquipment>,
        recentExercises: [String]
    ) -> PlannedWorkout {
        // Plan generation produces intent only, not implementation
        // Exercises are generated on-demand when the user opens the workout
        
        // Create phase-specific title and description
        let title = "\(phase.name) Strength"
        let description = getGymWorkoutDescription(phase: phase)
        
        // Estimate duration based on phase (without generating exercises)
        let estimatedDuration = getEstimatedGymDuration(for: phase.name)
        
        return PlannedWorkout(
            date: date,
            type: .gym,
            title: title,
            description: description,
            targetDurationSeconds: Double(estimatedDuration),
            exerciseProgram: nil  // Generated on-demand when workout is opened
        )
    }
    
    /// Get estimated gym workout duration based on phase
    private func getEstimatedGymDuration(for phaseName: String) -> Int {
        switch phaseName {
        case "Base Building":
            return 45 * 60  // 45 minutes
        case "Build Up":
            return 40 * 60  // 40 minutes
        case "Peak Training":
            return 35 * 60  // 35 minutes
        case "Taper":
            return 25 * 60  // 25 minutes
        default:
            return 40 * 60  // 40 minutes default
        }
    }
    
    /// Get minimum exercise count based on phase
    private func getMinimumExerciseCount(for phaseName: String) -> Int {
        switch phaseName {
        case "Base Building":
            return 6  // 4 strength + 2 mobility + 2 prehab = 8 target, 6 minimum
        case "Build Up":
            return 5  // 3-4 strength + plyos + stability + prehab = 7 target, 5 minimum
        case "Peak Training":
            return 4  // 2-3 strength + plyos + prehab = 6 target, 4 minimum
        case "Taper":
            return 3  // 2 strength + 2 mobility = 4 target, 3 minimum
        default:
            return 4  // Generic minimum
        }
    }
    
    /// Calculate estimated duration for gym workout
    private func calculateGymWorkoutDuration(_ exercises: [ExerciseAssignment]) -> Int {
        var totalSeconds = 0
        
        for assignment in exercises {
            // Time per set
            let timePerSet: Int
            if let duration = assignment.durationSeconds {
                timePerSet = duration
            } else if let reps = assignment.reps {
                // Estimate 3 seconds per rep
                timePerSet = (reps.lowerBound + reps.upperBound) / 2 * 3
            } else {
                timePerSet = 30 // Default
            }
            
            // Total time = (time per set + rest) * sets
            let restTime = assignment.restSeconds ?? 60
            totalSeconds += (timePerSet + restTime) * assignment.sets
        }
        
        // Add 5 minutes warmup and 5 minutes cooldown
        totalSeconds += 600
        
        return totalSeconds
    }
    
    /// Get description based on training phase
    private func getGymWorkoutDescription(phase: TrainingPhase) -> String {
        switch phase.name {
        case "Base Building":
            return "Foundation building with bilateral strength movements. Focus on form and building a base."
        case "Build Up":
            return "Progressive overload with unilateral work and power development. Push yourself but maintain quality."
        case "Peak Training":
            return "Maintain strength while managing fatigue. Quality over quantity."
        case "Taper":
            return "Light maintenance to stay sharp without accumulating fatigue. Keep it easy."
        default:
            return "Runner-specific strength training. Focus on core, legs, and hip stability."
        }
    }
    
    /// Generate rest day
    private func generateRestDay(date: Date) -> PlannedWorkout {
        return PlannedWorkout(
            date: date,
            type: .rest,
            title: "Rest Day",
            description: "Complete rest or light stretching. Allow your body to recover and adapt."
        )
    }
}
