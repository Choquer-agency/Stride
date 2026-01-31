import Foundation
import Combine

/// Manages training plan generation, storage, and updates
@MainActor
class TrainingPlanManager: ObservableObject {
    @Published private(set) var activePlan: TrainingPlan?
    @Published var isGenerating: Bool = false
    @Published var generationError: Error?
    @Published var showPlanSummary: Bool = false
    @Published var planWarnings: [String] = []
    
    // Skeleton-first flow state
    @Published private(set) var activeSkeleton: PlanSkeleton?
    @Published var isHydrating: Bool = false
    @Published var needsHydration: Bool = false
    
    private let storageManager: StorageManager
    private let aiGenerator: AITrainingPlanGenerator?
    
    // MARK: - Initialization
    
    init(storageManager: StorageManager, aiGenerator: AITrainingPlanGenerator? = nil) {
        self.storageManager = storageManager
        self.aiGenerator = aiGenerator
        loadActivePlan()
    }
    
    // MARK: - Plan Loading
    
    /// Load the active plan from storage
    func loadActivePlan() {
        activePlan = storageManager.loadTrainingPlan()
        
        if let plan = activePlan {
            print("📅 Loaded training plan: \(plan.totalWeeks) weeks, \(plan.allWorkouts.count) workouts")
        } else {
            print("📅 No active training plan")
        }
    }
    
    /// Get the user's training profile
    func getUserProfile() -> UserTrainingProfile {
        return storageManager.loadUserProfile()
    }
    
    // MARK: - Skeleton-First Plan Generation
    
    /// Generate plan skeleton for fast summary display (~3 seconds).
    /// Creates TrainingPlan with empty weeks[], stores skeleton for UI.
    /// Call hydratePlanWithDailySchedule() when user taps "View Full Plan".
    func generatePlanSkeleton(
        for goal: Goal,
        baseline: BaselineAssessment?,
        preferences: TrainingPreferences
    ) async throws -> PlanSkeleton {
        print("\n⚡ ========================================")
        print("⚡ SKELETON GENERATION STARTED")
        print("⚡ ========================================")
        
        isGenerating = true
        generationError = nil
        activeSkeleton = nil
        needsHydration = false
        
        defer {
            isGenerating = false
        }
        
        guard let aiGenerator = aiGenerator else {
            let error = AIGeneratorError.aiNotConfigured
            generationError = error
            throw error
        }
        
        do {
            // Generate skeleton via fast AI call
            let skeleton = try await aiGenerator.generatePlanSkeleton(
                goal: goal,
                baseline: baseline,
                preferences: preferences
            )
            
            // Create TrainingPlan with empty weeks (will be hydrated later)
            let calendar = Calendar.current
            let startDate = calendar.startOfDay(for: Date())
            
            // Create empty week structures based on skeleton
            var emptyWeeks: [WeekPlan] = []
            for target in skeleton.weeklyTargets {
                guard let weekStart = calendar.date(byAdding: .weekOfYear, value: target.week - 1, to: startDate),
                      let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
                    continue
                }
                
                let phase = skeleton.phases.first { $0.weekRange.contains(target.week) } ?? skeleton.phases.first!
                
                emptyWeeks.append(WeekPlan(
                    weekNumber: target.week,
                    startDate: weekStart,
                    endDate: weekEnd,
                    phase: phase,
                    targetWeeklyKm: target.totalKm,
                    workouts: []  // Empty - will be hydrated later
                ))
            }
            
            // Create plan with metadata but empty workouts
            let plan = TrainingPlan(
                goalId: goal.id,
                startDate: startDate,
                eventDate: goal.eventDate,
                generationMethod: .llmGenerated,
                totalWeeks: skeleton.weeklyTargets.count,
                weeklyRunDays: preferences.weeklyRunDays,
                weeklyGymDays: preferences.weeklyGymDays,
                availability: preferences.getEffectiveAvailability(),
                phases: skeleton.phases,
                weeks: emptyWeeks,
                generationContext: PlanGenerationContext(
                    generationMethod: .aiEnhanced,
                    baselineSource: baseline != nil ? .guidedTest : .none,
                    baselineVDOT: baseline?.vdot,
                    baselineDate: baseline?.assessmentDate,
                    goalInfluence: .pacesAligned,
                    confidenceLevel: baseline != nil ? .high : .medium,
                    constraintsApplied: ["Skeleton-first generation"],
                    llmStatus: .enabled,
                    generatedAt: Date()
                ),
                goalFeasibility: skeleton.goalFeasibility
            )
            
            // Save plan and skeleton
            try storageManager.saveTrainingPlan(plan)
            activePlan = plan
            activeSkeleton = skeleton
            needsHydration = true
            showPlanSummary = true
            
            print("⚡ Skeleton complete: \(skeleton.phases.count) phases, plan saved")
            print("⚡ ========================================\n")
            
            return skeleton
            
        } catch {
            generationError = error
            print("❌ Skeleton generation failed: \(error)")
            throw error
        }
    }
    
    /// Hydrate plan with daily workouts. Called when user taps "View Full Plan".
    /// This is a synchronous, user-triggered action only.
    func hydratePlanWithDailySchedule(
        goal: Goal,
        baseline: BaselineAssessment?,
        preferences: TrainingPreferences
    ) async throws {
        print("\n📅 ========================================")
        print("📅 PLAN HYDRATION STARTED")
        print("📅 ========================================")
        
        guard let skeleton = activeSkeleton else {
            throw PlanError.noPlan
        }
        
        guard var plan = activePlan else {
            throw PlanError.noPlan
        }
        
        isHydrating = true
        
        defer {
            isHydrating = false
        }
        
        guard let aiGenerator = aiGenerator else {
            throw AIGeneratorError.aiNotConfigured
        }
        
        do {
            // Generate daily schedule
            let days = try await aiGenerator.generateDailySchedule(
                skeleton: skeleton,
                goal: goal,
                baseline: baseline,
                preferences: preferences
            )
            
            // Parse days into workouts
            let workouts = parseDaysIntoWorkouts(days: days, preferences: preferences)
            
            // Group workouts into weeks
            let calendar = Calendar.current
            var updatedWeeks: [WeekPlan] = []
            
            for week in plan.weeks {
                let weekWorkouts = workouts.filter { workout in
                    workout.date >= week.startDate && workout.date <= week.endDate
                }.sorted { $0.date < $1.date }
                
                updatedWeeks.append(WeekPlan(
                    id: week.id,
                    weekNumber: week.weekNumber,
                    startDate: week.startDate,
                    endDate: week.endDate,
                    phase: week.phase,
                    targetWeeklyKm: week.targetWeeklyKm,
                    workouts: weekWorkouts
                ))
            }
            
            // Update plan with hydrated weeks
            plan = TrainingPlan(
                id: plan.id,
                goalId: plan.goalId,
                createdAt: plan.createdAt,
                lastModified: Date(),
                startDate: plan.startDate,
                eventDate: plan.eventDate,
                generationMethod: plan.generationMethod,
                totalWeeks: plan.totalWeeks,
                weeklyRunDays: plan.weeklyRunDays,
                weeklyGymDays: plan.weeklyGymDays,
                availability: plan.availability,
                phases: plan.phases,
                weeks: updatedWeeks,
                generationContext: plan.generationContext,
                goalFeasibility: plan.goalFeasibility
            )
            
            // Save hydrated plan
            try storageManager.saveTrainingPlan(plan)
            activePlan = plan
            needsHydration = false
            
            print("📅 Hydration complete: \(workouts.count) workouts added")
            print("📅 ========================================\n")
            
        } catch {
            print("❌ Hydration failed: \(error)")
            throw error
        }
    }
    
    /// Parse days array from AI into PlannedWorkout objects
    private func parseDaysIntoWorkouts(days: [[String: Any]], preferences: TrainingPreferences) -> [PlannedWorkout] {
        var workouts: [PlannedWorkout] = []
        
        let isoFormatter = ISO8601DateFormatter()
        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        dateOnlyFormatter.timeZone = TimeZone.current
        
        for dayData in days {
            guard let dateString = dayData["date"] as? String,
                  let date = isoFormatter.date(from: dateString) ?? dateOnlyFormatter.date(from: dateString),
                  let typeString = dayData["type"] as? String else {
                continue
            }
            
            let type = typeString.lowercased()
            
            if type == "rest" {
                workouts.append(PlannedWorkout(
                    date: date,
                    type: .rest,
                    title: "Rest Day",
                    description: nil
                ))
            } else if type == "gym" {
                // Simplified gym workouts - no duration, no exercises, just "Strength Training"
                workouts.append(PlannedWorkout(
                    date: date,
                    type: .gym,
                    title: "Strength Training",
                    description: nil
                ))
            } else if type == "run" {
                let runType = dayData["run_type"] as? String ?? "easy"
                let distance = dayData["distance_km"] as? Double ?? 5.0
                let pace = dayData["pace"] as? Double ?? 390.0
                
                let workoutType: PlannedWorkout.WorkoutType
                let title: String
                
                switch runType.lowercased() {
                case "long":
                    workoutType = .longRun
                    title = "Long Run"
                case "tempo":
                    workoutType = .tempoRun
                    title = "Tempo Run"
                case "intervals":
                    workoutType = .intervalWorkout
                    title = "Interval Workout"
                case "recovery":
                    workoutType = .recoveryRun
                    title = "Recovery Run"
                case "goal_pace":
                    workoutType = .raceSimulation
                    title = "Goal Pace Run"
                default:
                    workoutType = .easyRun
                    title = "Easy Run"
                }
                
                workouts.append(PlannedWorkout(
                    date: date,
                    type: workoutType,
                    title: title,
                    description: nil,
                    targetDistanceKm: distance,
                    targetPaceSecondsPerKm: pace
                ))
            }
        }
        
        return workouts
    }
    
    // MARK: - Legacy Plan Generation (Full)
    
    /// Generate a new training plan using AI (required)
    /// NOTE: Consider using generatePlanSkeleton() + hydratePlanWithDailySchedule() instead
    func generatePlan(
        for goal: Goal,
        baseline: BaselineAssessment?,
        preferences: TrainingPreferences
    ) async throws {
        print("\n🎬 ========================================")
        print("🎬 TRAINING PLAN GENERATION STARTED")
        print("🎬 ========================================")
        print("   Time: \(Date())")
        print("   Goal: \(goal.displayName)")
        print("   Distance: \(goal.distanceKm ?? 0)km")
        print("   Weeks: \(goal.weeksRemaining)")
        
        isGenerating = true
        generationError = nil
        planWarnings = []
        
        defer {
            Task { @MainActor in
                isGenerating = false
                print("\n🏁 ========================================")
                print("🏁 GENERATION PROCESS ENDED")
                print("🏁 ========================================\n")
            }
        }
        
        print("\n✅ Step 0: Checking AI configuration...")
        // AI is required - check if configured
        guard let aiGenerator = aiGenerator else {
            let error = AIGeneratorError.aiNotConfigured
            generationError = error
            print("❌ AI Coach not configured - cannot generate training plan")
            print("   Please add your OpenAI API key in Settings or add OPENAI_API_KEY to Xcode scheme")
            throw error
        }
        print("   AI Generator: ✅ Available")
        
        do {
            print("\n✅ Step 1: Loading user profile...")
            // Load user profile for equipment settings
            let userProfile = storageManager.loadUserProfile()
            print("   Profile loaded: \(userProfile.availableEquipment.count) equipment items")
            
            print("\n🤖 Step 2: Calling AI Generator...")
            print("🤖 AI Coach: Generating plan with structured prompt...")
            
            // ATTEMPT 1: Initial generation
            var planJSON = try await aiGenerator.generateCompletePlanJSON(
                goal: goal,
                baseline: baseline,
                preferences: preferences,
                userProfile: userProfile
            )
            print("\n✅ Step 2 Complete: Initial plan JSON received")
            
            // VALIDATE with deterministic checks
            print("\n🛡️ Step 3: Validating AI response with AIPlanValidator...")
            var validation = AIPlanValidator.validate(
                planJSON: planJSON,
                goal: goal,
                baseline: baseline,
                preferences: preferences
            )
            
            print("   Validation result:")
            print("     - Valid: \(validation.isValid)")
            print("     - Errors: \(validation.errors.count)")
            print("     - Warnings: \(validation.warnings.count)")
            if !validation.errors.isEmpty {
                print("   Error details:")
                for (i, error) in validation.errors.enumerated() {
                    print("     \(i+1). [\(error.type)] \(error.message)")
                }
            }
            
            // REPAIR LOOP: TEMPORARILY DISABLED FOR DEBUGGING
            // This makes failures deterministic and surfaces real issues
            // TODO: Re-enable repair loop once plan generation is stable
            /*
            var repairAttempts = 0
            while !validation.isValid && repairAttempts < 2 {
                repairAttempts += 1
                print("\n⚠️ Step 3.\(repairAttempts): Validation failed - Repair attempt \(repairAttempts)/2...")
                print("   Building repair prompt...")
                
                // Build repair prompt with specific errors
                let repairPrompt = buildRepairPrompt(
                    errors: validation.errors,
                    originalJSON: planJSON,
                    goal: goal,
                    baseline: baseline,
                    preferences: preferences
                )
                
                print("   Sending repair request to OpenAI...")
                planJSON = try await aiGenerator.repairPlan(
                    repairPrompt: repairPrompt,
                    originalJSON: planJSON
                )
                print("   ✅ Received repaired plan")
                
                print("   Re-validating repaired plan...")
                validation = AIPlanValidator.validate(
                    planJSON: planJSON,
                    goal: goal,
                    baseline: baseline,
                    preferences: preferences
                )
                print("     - Valid: \(validation.isValid)")
                print("     - Errors: \(validation.errors.count)")
                print("     - Warnings: \(validation.warnings.count)")
            }
            */
            
            // Fail fast and surface validation errors clearly (debugging mode)
            guard validation.isValid else {
                print("\n❌ Step 3 FAILED: Validation failed - not attempting repair (debugging mode)")
                print("   Errors:")
                for (i, error) in validation.errors.enumerated() {
                    print("     \(i+1). [\(error.type)] \(error.message)")
                }
                let error = PlanError.generationFailed
                generationError = error
                planWarnings = validation.errors.map { $0.message }
                throw error
            }
            
            print("\n✅ Step 3 Complete: Validation passed")
            
            // Store any warnings
            if !validation.warnings.isEmpty {
                planWarnings = validation.warnings
                print("   ⚠️ Non-critical warnings (\(validation.warnings.count)):")
                for (i, warning) in validation.warnings.enumerated() {
                    print("     \(i+1). \(warning)")
                }
            }
            
            // Parse validated JSON into TrainingPlan
            print("\n📦 Step 4: Parsing JSON into TrainingPlan object...")
            var plan = try aiGenerator.parsePlanFromJSON(
                planJSON: planJSON,
                goal: goal,
                baseline: baseline,
                preferences: preferences
            )
            print("✅ Step 4 Complete: TrainingPlan object created")
            print("   - Total weeks: \(plan.totalWeeks)")
            print("   - Total workouts: \(plan.allWorkouts.count)")
            print("   - Phases: \(plan.phases.map { $0.name }.joined(separator: ", "))")
            if let feasibility = plan.goalFeasibility {
                print("   - Goal feasibility: \(feasibility.rating.rawValue)")
            }
            
            // Existing safety validation (redundant backup)
            print("\n🛡️ Step 5: Running backup safety validation...")
            let safetyValidation = PlanSafetyValidator.validate(plan, baseline: baseline)
            if safetyValidation.hasCriticalIssues {
                print("❌ Step 5 FAILED: Safety validation found critical issues")
                for (i, issue) in safetyValidation.criticalIssues.enumerated() {
                    print("     \(i+1). \(issue)")
                }
                planWarnings.append(contentsOf: safetyValidation.criticalIssues)
                let error = PlanError.generationFailed
                generationError = error
                throw error
            }
            print("✅ Step 5 Complete: Safety checks passed")
            
            // Note: Gym exercises are now generated on-demand when user opens the workout
            // This reduces plan generation time and failure points
            print("\n🏋️ Step 6: Gym workouts configured")
            let gymCount = plan.allWorkouts.filter { $0.type == .gym }.count
            print("   - Found \(gymCount) gym workouts (exercises generated on-demand)")
            
            // Save plan
            print("\n💾 Step 7: Saving training plan...")
            try storageManager.saveTrainingPlan(plan)
            print("✅ Step 7 Complete: Plan saved to storage")
            
            print("\n🎉 Step 8: Finalizing...")
            activePlan = plan
            
            // Show plan summary after successful generation
            showPlanSummary = true
            print("✅ Step 8 Complete: Activated plan and showing summary")
            
            print("\n✅ ==========================================")
            print("✅ PLAN GENERATION SUCCESSFUL!")
            print("✅ ==========================================")
            print("   Plan: \(plan.totalWeeks) weeks, \(plan.allWorkouts.count) workouts")
            if let feasibility = plan.goalFeasibility {
                print("   Goal feasibility: \(feasibility.rating.rawValue), realistic: \(feasibility.isRealistic)")
                if let recommendedTime = feasibility.recommendedTargetTime {
                    print("   Recommended time: \(Int(recommendedTime))s")
                }
            }
            
        } catch {
            print("\n❌ ==========================================")
            print("❌ PLAN GENERATION FAILED")
            print("❌ ==========================================")
            print("   Error type: \(type(of: error))")
            print("   Error: \(error)")
            print("   Localized: \(error.localizedDescription)")
            if let aiError = error as? AIGeneratorError {
                print("   AI Error details: \(aiError)")
            }
            print("❌ ==========================================\n")
            generationError = error
            throw error
        }
    }
    
    // MARK: - Repair Prompt Builder
    
    private func buildRepairPrompt(
        errors: [AIPlanValidator.ValidationError],
        originalJSON: [String: Any],
        goal: Goal,
        baseline: BaselineAssessment?,
        preferences: TrainingPreferences
    ) -> String {
        var prompt = """
        Your previous plan had validation errors. Regenerate ONLY the days array to fix these issues.
        
        DO NOT modify:
        - plan_metadata
        - goal_feasibility
        - pace_context
        - phases
        
        Preserve these sections exactly as they were.
        
        ERRORS TO FIX:
        """
        
        for error in errors {
            prompt += "\n- \(error.message)"
            if let date = error.affectedDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                prompt += " (Date: \(formatter.string(from: date)))"
            }
        }
        
        prompt += """
        
        
        ORIGINAL PLAN METADATA (keep this):
        """
        
        if let metadata = originalJSON["plan_metadata"] as? [String: Any],
           let jsonData = try? JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            prompt += "\n\(jsonString)"
        }
        
        prompt += """
        
        
        ORIGINAL FEASIBILITY (keep this):
        """
        
        if let feasibility = originalJSON["goal_feasibility"] as? [String: Any],
           let jsonData = try? JSONSerialization.data(withJSONObject: feasibility, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            prompt += "\n\(jsonString)"
        }
        
        prompt += """
        
        
        ORIGINAL PACE CONTEXT (keep this):
        """
        
        if let paceContext = originalJSON["pace_context"] as? [String: Any],
           let jsonData = try? JSONSerialization.data(withJSONObject: paceContext, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            prompt += "\n\(jsonString)"
        }
        
        prompt += """
        
        
        ORIGINAL PHASES (keep this):
        """
        
        if let phases = originalJSON["phases"] as? [[String: Any]],
           let jsonData = try? JSONSerialization.data(withJSONObject: phases, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            prompt += "\n\(jsonString)"
        }
        
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: Date())
        let isoFormatter = ISO8601DateFormatter()
        
        prompt += """
        
        
        REQUIREMENTS:
        - Regenerate days array from \(isoFormatter.string(from: startDate)) to \(isoFormatter.string(from: goal.eventDate))
        - Respect rest days: \(preferences.getEffectiveAvailability().restDays)
        - Respect available days: \(preferences.getEffectiveAvailability().availableDays)
        - No run/gym workouts on rest days
        - No consecutive gym days
        - Use pace_context values for workout paces
        
        Return the complete JSON with the corrected days array.
        """
        
        return prompt
    }
    
    /// Whether AI coaching is available
    var aiCoachEnabled: Bool {
        return aiGenerator != nil
    }
    
    /// Description of AI coach status for UI
    var aiCoachStatusDescription: String {
        if aiGenerator != nil {
            return "AI Coach (ChatGPT) enabled"
        } else {
            return "AI Coach off (no API key configured)"
        }
    }
    
    // MARK: - Plan Management
    
    /// Mark a workout as complete (for workouts without actual workout sessions, like gym)
    func markWorkoutCompleted(_ workoutId: UUID) {
        guard var plan = activePlan else { return }
        
        // Find and mark the workout complete
        var found = false
        for weekIndex in 0..<plan.weeks.count {
            var week = plan.weeks[weekIndex]
            
            for workoutIndex in 0..<week.workouts.count {
                if week.workouts[workoutIndex].id == workoutId {
                    var workout = week.workouts[workoutIndex]
                    workout.completed = true
                    week.workouts[workoutIndex] = workout
                    found = true
                    break
                }
            }
            
            plan.weeks[weekIndex] = week
            if found { break }
        }
        
        if !found {
            print("⚠️ Workout not found: \(workoutId)")
            return
        }
        
        // Update last modified
        plan = TrainingPlan(
            id: plan.id,
            goalId: plan.goalId,
            createdAt: plan.createdAt,
            lastModified: Date(),
            startDate: plan.startDate,
            eventDate: plan.eventDate,
            generationMethod: plan.generationMethod,
            totalWeeks: plan.totalWeeks,
            weeklyRunDays: plan.weeklyRunDays,
            weeklyGymDays: plan.weeklyGymDays,
            availability: plan.availability,
            phases: plan.phases,
            weeks: plan.weeks
        )
        
        // Save updated plan
        do {
            try storageManager.saveTrainingPlan(plan)
            activePlan = plan
            print("✅ Marked workout as complete: \(workoutId)")
        } catch {
            print("⚠️ Error saving updated plan: \(error)")
        }
    }
    
    /// Mark a workout as complete with actual workout session data
    func markWorkoutComplete(_ workoutId: UUID, actualWorkout: WorkoutSession) throws {
        guard var plan = activePlan else {
            throw PlanError.noPlan
        }
        
        // Find and update the workout
        var found = false
        for weekIndex in 0..<plan.weeks.count {
            var week = plan.weeks[weekIndex]
            
            for workoutIndex in 0..<week.workouts.count {
                if week.workouts[workoutIndex].id == workoutId {
                    var workout = week.workouts[workoutIndex]
                    workout.completed = true
                    workout.actualWorkoutId = actualWorkout.id
                    week.workouts[workoutIndex] = workout
                    found = true
                    break
                }
            }
            
            plan.weeks[weekIndex] = week
            if found { break }
        }
        
        guard found else {
            throw PlanError.workoutNotFound
        }
        
        // Update last modified
        plan = TrainingPlan(
            id: plan.id,
            goalId: plan.goalId,
            createdAt: plan.createdAt,
            lastModified: Date(),
            startDate: plan.startDate,
            eventDate: plan.eventDate,
            generationMethod: plan.generationMethod,
            totalWeeks: plan.totalWeeks,
            weeklyRunDays: plan.weeklyRunDays,
            weeklyGymDays: plan.weeklyGymDays,
            availability: plan.availability,
            phases: plan.phases,
            weeks: plan.weeks,
            generationContext: plan.generationContext
        )
        
        // Save updated plan
        try storageManager.saveTrainingPlan(plan)
        activePlan = plan
        
        print("✅ Marked workout as complete: \(workoutId)")
    }
    
    /// Update a workout in the plan (e.g., exercise substitution)
    func updateWorkout(_ updatedWorkout: PlannedWorkout) {
        guard var plan = activePlan else { return }
        
        // Find and update the workout
        var found = false
        for weekIndex in 0..<plan.weeks.count {
            var week = plan.weeks[weekIndex]
            
            for workoutIndex in 0..<week.workouts.count {
                if week.workouts[workoutIndex].id == updatedWorkout.id {
                    week.workouts[workoutIndex] = updatedWorkout
                    found = true
                    break
                }
            }
            
            plan.weeks[weekIndex] = week
            if found { break }
        }
        
        if !found {
            print("⚠️ Workout not found: \(updatedWorkout.id)")
            return
        }
        
        // Update last modified
        plan = TrainingPlan(
            id: plan.id,
            goalId: plan.goalId,
            createdAt: plan.createdAt,
            lastModified: Date(),
            startDate: plan.startDate,
            eventDate: plan.eventDate,
            generationMethod: plan.generationMethod,
            totalWeeks: plan.totalWeeks,
            weeklyRunDays: plan.weeklyRunDays,
            weeklyGymDays: plan.weeklyGymDays,
            availability: plan.availability,
            phases: plan.phases,
            weeks: plan.weeks,
            generationContext: plan.generationContext
        )
        
        // Save updated plan
        do {
            try storageManager.saveTrainingPlan(plan)
            activePlan = plan
            print("✅ Updated workout: \(updatedWorkout.id)")
        } catch {
            print("⚠️ Error saving updated plan: \(error)")
        }
    }
    
    /// Regenerate the training plan (e.g., after goal change)
    func regeneratePlan(
        for goal: Goal,
        baseline: BaselineAssessment?,
        preferences: TrainingPreferences
    ) async throws {
        // Delete existing plan first
        try deletePlan()
        
        // Generate new plan
        try await generatePlan(for: goal, baseline: baseline, preferences: preferences)
    }
    
    /// Adjust the plan from a specific date (for future use)
    func adjustPlan(from date: Date) async throws {
        guard let plan = activePlan else {
            throw PlanError.noPlan
        }
        
        // This is a placeholder for future adaptive adjustments
        // For now, we'll just keep the plan as is
        print("📅 Plan adjustment from \(date) - feature coming soon")
    }
    
    /// Apply weekly adaptation to the training plan
    func applyWeeklyAdaptation(_ adaptation: AdaptationPlan) throws {
        guard var plan = activePlan else {
            throw PlanError.noPlan
        }
        
        print("📅 Applying weekly adaptation with \(adaptation.adjustments.count) adjustments")
        
        // Apply each adjustment to the plan
        for adjustment in adaptation.adjustments {
            // Find the workout to adjust
            var found = false
            for weekIndex in 0..<plan.weeks.count {
                var week = plan.weeks[weekIndex]
                
                for workoutIndex in 0..<week.workouts.count {
                    var workout = week.workouts[workoutIndex]
                    
                    if workout.id == adjustment.workoutId {
                        // Apply the adjustment based on type
                        switch adjustment.changeType {
                        case .volumeReduction, .volumeIncrease:
                            if let currentDistance = workout.targetDistanceKm {
                                // Extract new distance from newValue string (format: "X.X km")
                                if let newDistance = extractDistance(from: adjustment.newValue) {
                                    workout = PlannedWorkout(
                                        id: workout.id,
                                        date: workout.date,
                                        type: workout.type,
                                        title: workout.title,
                                        description: workout.description,
                                        completed: workout.completed,
                                        actualWorkoutId: workout.actualWorkoutId,
                                        targetDistanceKm: newDistance,
                                        targetDurationSeconds: workout.targetDurationSeconds,
                                        targetPaceSecondsPerKm: workout.targetPaceSecondsPerKm,
                                        intervals: workout.intervals
                                    )
                                }
                            }
                            
                        case .intensityReduction, .intensityIncrease:
                            // Extract new pace from newValue string (format: "M:SS /km")
                            if let newPace = extractPace(from: adjustment.newValue) {
                                workout = PlannedWorkout(
                                    id: workout.id,
                                    date: workout.date,
                                    type: workout.type,
                                    title: workout.title,
                                    description: workout.description,
                                    completed: workout.completed,
                                    actualWorkoutId: workout.actualWorkoutId,
                                    targetDistanceKm: workout.targetDistanceKm,
                                    targetDurationSeconds: workout.targetDurationSeconds,
                                    targetPaceSecondsPerKm: newPace,
                                    intervals: workout.intervals
                                )
                            }
                            
                        case .workoutTypeChange:
                            // Change workout type
                            let newType: PlannedWorkout.WorkoutType
                            if adjustment.newValue == "Easy Run" {
                                newType = .easyRun
                            } else if adjustment.newValue == "Rest Day" {
                                newType = .rest
                            } else {
                                newType = workout.type // Keep original if unknown
                            }
                            
                            workout = PlannedWorkout(
                                id: workout.id,
                                date: workout.date,
                                type: newType,
                                title: newType.displayName,
                                description: adjustment.reason,
                                completed: workout.completed,
                                actualWorkoutId: workout.actualWorkoutId,
                                targetDistanceKm: workout.targetDistanceKm,
                                targetDurationSeconds: workout.targetDurationSeconds,
                                targetPaceSecondsPerKm: workout.targetPaceSecondsPerKm,
                                intervals: nil // Clear intervals for type changes
                            )
                            
                        case .addedRestDay, .removedRestDay:
                            // Handle rest day changes
                            break
                        }
                        
                        week.workouts[workoutIndex] = workout
                        found = true
                        break
                    }
                }
                
                plan.weeks[weekIndex] = week
                if found { break }
            }
        }
        
        // Update last modified
        plan = TrainingPlan(
            id: plan.id,
            goalId: plan.goalId,
            createdAt: plan.createdAt,
            lastModified: Date(),
            startDate: plan.startDate,
            eventDate: plan.eventDate,
            generationMethod: plan.generationMethod,
            totalWeeks: plan.totalWeeks,
            weeklyRunDays: plan.weeklyRunDays,
            weeklyGymDays: plan.weeklyGymDays,
            availability: plan.availability,
            phases: plan.phases,
            weeks: plan.weeks,
            generationContext: plan.generationContext
        )
        
        // Save updated plan
        try storageManager.saveTrainingPlan(plan)
        activePlan = plan
        
        print("✅ Weekly adaptation applied successfully")
    }
    
    // MARK: - Helper Methods
    
    private func extractDistance(from string: String) -> Double? {
        // Extract distance from strings like "5.5 km"
        let components = string.components(separatedBy: " ")
        if let firstComponent = components.first,
           let distance = Double(firstComponent) {
            return distance
        }
        return nil
    }
    
    private func extractPace(from string: String) -> Double? {
        // Extract pace from strings like "5:30 /km"
        let components = string.components(separatedBy: " ")
        if let paceString = components.first {
            let timeComponents = paceString.components(separatedBy: ":")
            if timeComponents.count == 2,
               let minutes = Int(timeComponents[0]),
               let seconds = Int(timeComponents[1]) {
                return Double(minutes * 60 + seconds)
            }
        }
        return nil
    }
    
    /// Delete the active plan
    func deletePlan() throws {
        guard activePlan != nil else {
            throw PlanError.noPlan
        }
        
        try storageManager.deleteTrainingPlan()
        activePlan = nil
        showPlanSummary = false
        
        print("🗑️ Deleted training plan")
    }
    
    /// Dismiss the plan summary (mark as seen)
    func dismissPlanSummary() {
        showPlanSummary = false
    }
    
    // MARK: - Helper Properties
    
    /// Whether there is an active plan
    var hasActivePlan: Bool {
        return activePlan != nil
    }
    
    /// Today's workout (if any)
    var todaysWorkout: PlannedWorkout? {
        return activePlan?.todaysWorkout
    }
    
    /// Current week in the plan
    var currentWeek: WeekPlan? {
        return activePlan?.currentWeek
    }
    
    /// Current training phase
    var currentPhase: TrainingPhase? {
        return activePlan?.currentPhase
    }
    
    /// Upcoming workouts (next 7 days)
    var upcomingWorkouts: [PlannedWorkout] {
        guard let plan = activePlan else { return [] }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: today)!
        
        return plan.allWorkouts.filter { workout in
            let workoutDay = calendar.startOfDay(for: workout.date)
            return workoutDay >= today && workoutDay < nextWeek
        }.sorted { $0.date < $1.date }
    }
    
    /// Progress summary
    var progressSummary: String {
        guard let plan = activePlan else { return "No active plan" }
        
        let completed = plan.completedWorkoutsCount
        let total = plan.totalWorkoutsCount
        let percentage = Int(plan.completionPercentage)
        
        return "\(completed)/\(total) workouts • \(percentage)% complete"
    }
    
    // MARK: - Preferences Management
    
    /// Load training preferences
    func loadPreferences() -> TrainingPreferences {
        return storageManager.loadTrainingPreferences()
    }
    
    /// Save training preferences
    func savePreferences(_ preferences: TrainingPreferences) throws {
        try storageManager.saveTrainingPreferences(preferences)
        print("✅ Saved training preferences")
    }
    
    /// Load the latest baseline assessment
    func loadLatestBaselineAssessment() -> BaselineAssessment? {
        return storageManager.loadLatestBaselineAssessment()
    }
    
    // MARK: - Availability Management
    
    /// Update availability and adjust active plan if needed
    func updateAvailability(_ newAvailability: TrainingAvailability) throws {
        guard var plan = activePlan else {
            // No active plan, just save preferences
            var preferences = storageManager.loadTrainingPreferences()
            preferences.availability = newAvailability
            try storageManager.saveTrainingPreferences(preferences)
            return
        }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Get old availability for comparison
        let oldAvailability = plan.availability
        
        // Track if we made any changes
        var madeChanges = false
        
        // Process each future week
        for weekIndex in 0..<plan.weeks.count {
            var week = plan.weeks[weekIndex]
            
            // Skip past weeks
            if week.endDate < today {
                continue
            }
            
            var updatedWorkouts: [PlannedWorkout] = []
            var workoutsToReassign: [PlannedWorkout] = []
            
            // Collect workouts that need to be moved or kept
            for workout in week.workouts {
                let workoutDay = calendar.component(.weekday, from: workout.date) - 1
                
                // Check if workout is on a new rest day
                if newAvailability.restDays.contains(workoutDay) {
                    if workout.type == .rest {
                        // Already a rest day, keep it
                        updatedWorkouts.append(workout)
                    } else {
                        // Need to move this workout
                        workoutsToReassign.append(workout)
                        madeChanges = true
                        
                        // Add rest day marker
                        updatedWorkouts.append(generateRestDayForDate(workout.date))
                    }
                } else if newAvailability.availableDays.contains(workoutDay) {
                    // Still available, keep workout
                    updatedWorkouts.append(workout)
                } else {
                    // Day is now unavailable
                    if workout.type != .rest {
                        // Need to move or drop
                        workoutsToReassign.append(workout)
                        madeChanges = true
                    }
                    // Unavailable days get no entries
                }
            }
            
            // Try to reassign workouts within the same week
            for workout in workoutsToReassign {
                if let newDate = findNextAvailableDay(
                    in: week,
                    availability: newAvailability,
                    takenDays: Set(updatedWorkouts.map { calendar.component(.weekday, from: $0.date) - 1 }),
                    calendar: calendar
                ) {
                    var movedWorkout = workout
                    movedWorkout = PlannedWorkout(
                        id: movedWorkout.id,
                        date: newDate,
                        type: movedWorkout.type,
                        title: movedWorkout.title,
                        description: movedWorkout.description,
                        completed: movedWorkout.completed,
                        actualWorkoutId: movedWorkout.actualWorkoutId,
                        targetDistanceKm: movedWorkout.targetDistanceKm,
                        targetDurationSeconds: movedWorkout.targetDurationSeconds,
                        targetPaceSecondsPerKm: movedWorkout.targetPaceSecondsPerKm,
                        intervals: movedWorkout.intervals,
                        exerciseProgram: movedWorkout.exerciseProgram,
                        warmupBlock: movedWorkout.warmupBlock,
                        cooldownBlock: movedWorkout.cooldownBlock
                    )
                    updatedWorkouts.append(movedWorkout)
                } else {
                    // Can't fit in this week, drop lowest priority workouts
                    if shouldDropWorkout(workout) {
                        print("⚠️ Dropped workout: \(workout.title) on \(workout.date)")
                    } else {
                        // Important workout - try to keep in future weeks
                        // For now, we'll drop it but this could be enhanced
                        print("⚠️ Unable to reschedule: \(workout.title)")
                    }
                }
            }
            
            // Sort workouts by date
            week.workouts = updatedWorkouts.sorted { $0.date < $1.date }
            plan.weeks[weekIndex] = week
        }
        
        if madeChanges {
            // Update plan with new availability
            plan = TrainingPlan(
                id: plan.id,
                goalId: plan.goalId,
                createdAt: plan.createdAt,
                lastModified: Date(),
                startDate: plan.startDate,
                eventDate: plan.eventDate,
                generationMethod: plan.generationMethod,
                totalWeeks: plan.totalWeeks,
                weeklyRunDays: plan.weeklyRunDays,
                weeklyGymDays: plan.weeklyGymDays,
                    availability: newAvailability,
                    phases: plan.phases,
                    weeks: plan.weeks,
                    generationContext: plan.generationContext
                )
            
            try storageManager.saveTrainingPlan(plan)
            activePlan = plan
            
            print("✅ Adjusted plan for new availability")
        }
        
        // Update preferences
        var preferences = storageManager.loadTrainingPreferences()
        preferences.availability = newAvailability
        try storageManager.saveTrainingPreferences(preferences)
    }
    
    /// Find next available day in a week
    private func findNextAvailableDay(
        in week: WeekPlan,
        availability: TrainingAvailability,
        takenDays: Set<Int>,
        calendar: Calendar
    ) -> Date? {
        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: week.startDate) else {
                continue
            }
            let dayOfWeek = calendar.component(.weekday, from: date) - 1
            
            if availability.availableDays.contains(dayOfWeek) && !takenDays.contains(dayOfWeek) {
                return date
            }
        }
        return nil
    }
    
    /// Check if workout should be dropped (low priority)
    private func shouldDropWorkout(_ workout: PlannedWorkout) -> Bool {
        // Drop easy runs and gym first, keep quality and long runs
        switch workout.type {
        case .easyRun, .recoveryRun, .gym:
            return true
        case .longRun, .tempoRun, .intervalWorkout, .raceSimulation:
            return false
        default:
            return true
        }
    }
    
    /// Generate a rest day marker for a specific date
    private func generateRestDayForDate(_ date: Date) -> PlannedWorkout {
        return PlannedWorkout(
            date: date,
            type: .rest,
            title: "Rest Day",
            description: "Complete rest or light stretching. Allow your body to recover and adapt."
        )
    }
    
    // MARK: - Gym Workout Validation
    
    /// Validate that all gym workouts have exercise programs
    private func validateGymWorkouts(in plan: TrainingPlan) -> [UUID] {
        var emptyWorkoutIds: [UUID] = []
        
        for week in plan.weeks {
            for workout in week.workouts where workout.type == .gym {
                if !workout.hasExerciseProgram {
                    emptyWorkoutIds.append(workout.id)
                    print("⚠️ Gym workout '\(workout.title)' on \(workout.date) has no exercises")
                }
            }
        }
        
        return emptyWorkoutIds
    }
    
    /// Regenerate gym workouts that have no exercises
    private func regenerateEmptyGymWorkouts(
        plan: TrainingPlan,
        emptyWorkoutIds: [UUID],
        userProfile: UserTrainingProfile
    ) -> TrainingPlan {
        var updatedPlan = plan
        
        for weekIndex in 0..<updatedPlan.weeks.count {
            var week = updatedPlan.weeks[weekIndex]
            
            for workoutIndex in 0..<week.workouts.count {
                let workout = week.workouts[workoutIndex]
                
                if emptyWorkoutIds.contains(workout.id) {
                    print("🔄 Regenerating gym workout: \(workout.title)")
                    
                    // Force bodyweight fallback for regeneration
                    var fallbackEquipment = userProfile.availableEquipment
                    fallbackEquipment.insert(.none)
                    
                    // Use ExerciseSelector directly with fallback settings
                    let selector = ExerciseSelector()
                    
                    // Determine phase from plan based on week number
                    let phase = updatedPlan.phases.first { phase in
                        phase.weekRange.contains(week.weekNumber)
                    } ?? updatedPlan.phases.first!
                    
                    let exerciseProgram = selector.selectExercises(
                        for: phase,
                        goalType: .general,  // Use general to maximize options
                        availableEquipment: fallbackEquipment,
                        recentExercises: []  // Clear rotation for fallback
                    )
                    
                    if !exerciseProgram.isEmpty {
                        // Create new workout with exercises
                        let regeneratedWorkout = PlannedWorkout(
                            id: workout.id,
                            date: workout.date,
                            type: workout.type,
                            title: workout.title,
                            description: workout.description,
                            completed: workout.completed,
                            actualWorkoutId: workout.actualWorkoutId,
                            targetDistanceKm: workout.targetDistanceKm,
                            targetDurationSeconds: workout.targetDurationSeconds,
                            targetPaceSecondsPerKm: workout.targetPaceSecondsPerKm,
                            intervals: workout.intervals,
                            exerciseProgram: exerciseProgram,
                            warmupBlock: workout.warmupBlock,
                            cooldownBlock: workout.cooldownBlock
                        )
                        
                        week.workouts[workoutIndex] = regeneratedWorkout
                        print("✅ Regenerated with \(exerciseProgram.count) exercises")
                    } else {
                        print("❌ Failed to regenerate exercises for \(workout.title)")
                    }
                }
            }
            
            updatedPlan.weeks[weekIndex] = week
        }
        
        return updatedPlan
    }
}

// MARK: - Error Types

enum PlanError: LocalizedError {
    case noPlan
    case workoutNotFound
    case generationFailed
    case aiRequired
    
    var errorDescription: String? {
        switch self {
        case .noPlan:
            return "No active training plan"
        case .workoutNotFound:
            return "Workout not found in plan"
        case .generationFailed:
            return "Failed to generate training plan. Please try again."
        case .aiRequired:
            return "AI Coach is required to generate training plans. Please configure your OpenAI API key in Settings."
        }
    }
}
