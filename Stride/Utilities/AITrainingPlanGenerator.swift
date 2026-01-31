import Foundation

/// AI-powered training plan generator using ChatGPT as the primary coach
class AITrainingPlanGenerator {
    private let apiKey: String?
    
    // MARK: - Initialization
    
    init(apiKey: String?) {
        // Only store non-empty keys
        if let key = apiKey, !key.isEmpty {
            self.apiKey = key
        } else {
            self.apiKey = nil
        }
    }
    
    // MARK: - Main Generation Method
    
    /// Generate a complete training plan using AI as the primary coach
    func generateCompletePlan(
        goal: Goal,
        baseline: BaselineAssessment?,
        preferences: TrainingPreferences,
        userProfile: UserTrainingProfile
    ) async throws -> TrainingPlan {
        print("🤖 AI Coach: Generating training plan with ChatGPT...")
        
        // Build comprehensive coaching prompt
        let prompt = buildCoachingPrompt(
            goal: goal,
            baseline: baseline,
            preferences: preferences,
            userProfile: userProfile
        )
        
        print("📊 Prompt length: \(prompt.count) characters")
        print("🎯 Goal: \(goal.displayName), Distance: \(String(format: "%.1f", goal.distanceKm ?? 0))km")
        if let baseline = baseline {
            print("💪 Baseline VDOT: \(String(format: "%.1f", baseline.vdot))")
        }
        
        // Call OpenAI API
        print("🌐 Sending request to OpenAI API...")
        let jsonResponse = try await callOpenAIAPI(prompt: prompt)
        print("✅ Received response from OpenAI API")
        
        // Parse response into TrainingPlan
        let plan = try parseAIPlanResponse(
            jsonString: jsonResponse,
            goal: goal,
            baseline: baseline,
            preferences: preferences
        )
        
        print("✅ AI Coach: Successfully generated \(plan.totalWeeks)-week plan with \(plan.allWorkouts.count) workouts")
        print("📈 Plan phases: \(plan.phases.map { $0.name }.joined(separator: " → "))")
        
        return plan
    }
    
    /// Generate complete plan as JSON dictionary (for validation before parsing)
    func generateCompletePlanJSON(
        goal: Goal,
        baseline: BaselineAssessment?,
        preferences: TrainingPreferences,
        userProfile: UserTrainingProfile
    ) async throws -> [String: Any] {
        print("📝 ========== STEP 1: Starting Plan Generation ==========")
        print("   Goal: \(goal.displayName)")
        print("   Distance: \(goal.distanceKm ?? 0)km")
        print("   Target Time: \(goal.targetTime.map { String(format: "%.0fs", $0) } ?? "completion")")
        print("   Event Date: \(goal.eventDate)")
        print("   Weeks Available: \(goal.weeksRemaining)")
        print("   Has Baseline: \(baseline != nil)")
        if let baseline = baseline {
            print("   VDOT: \(baseline.vdot ?? 0)")
        }
        
        // Check API key is configured
        guard apiKey != nil else {
            print("❌ API key not configured")
            throw AIGeneratorError.aiNotConfigured
        }
        print("✅ API key configured")
        
        print("\n📝 ========== STEP 2: Building Prompt ==========")
        let prompt = buildCoachingPrompt(
            goal: goal,
            baseline: baseline,
            preferences: preferences,
            userProfile: userProfile
        )
        print("   Prompt length: \(prompt.count) characters")
        print("   Prompt preview (first 500 chars):")
        print("   \(prompt.prefix(500))")
        
        print("\n📝 ========== STEP 3: Calling OpenAI API ==========")
        let jsonResponse = try await callOpenAIAPI(prompt: prompt)
        print("✅ Received response from OpenAI")
        print("   Response length: \(jsonResponse.count) characters")
        print("   Response preview (first 500 chars):")
        print("   \(jsonResponse.prefix(500))")
        print("   Response preview (last 200 chars):")
        print("   ...\(jsonResponse.suffix(200))")
        
        print("\n📝 ========== STEP 4: Cleaning JSON Response ==========")
        // Parse as JSON
        var cleanedJSON = jsonResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        let hadMarkdown = cleanedJSON.hasPrefix("```")
        if cleanedJSON.hasPrefix("```json") {
            cleanedJSON = cleanedJSON.replacingOccurrences(of: "```json", with: "")
        }
        if cleanedJSON.hasPrefix("```") {
            cleanedJSON = cleanedJSON.replacingOccurrences(of: "```", with: "")
        }
        if cleanedJSON.hasSuffix("```") {
            cleanedJSON = String(cleanedJSON.dropLast(3))
        }
        cleanedJSON = cleanedJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        print("   Had markdown wrappers: \(hadMarkdown)")
        print("   Cleaned JSON length: \(cleanedJSON.count) characters")
        
        print("\n📝 ========== STEP 5: Parsing JSON ==========")
        guard let jsonData = cleanedJSON.data(using: .utf8) else {
            print("❌ Failed to convert cleaned JSON to Data")
            throw AIGeneratorError.parseError(details: "Unable to convert cleaned JSON to Data")
        }
        print("   Converted to Data (\(jsonData.count) bytes)")
        
        guard let planData = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            print("❌ Failed to parse JSON from AI response")
            print("   Response preview: \(cleanedJSON.prefix(500))")
            throw AIGeneratorError.parseError(details: "Unable to convert response to JSON dictionary")
        }
        
        print("✅ Successfully parsed JSON")
        print("   Top-level keys: \(planData.keys.joined(separator: ", "))")
        if let days = planData["days"] as? [[String: Any]] {
            print("   Days array: \(days.count) entries")
        }
        if let phases = planData["phases"] as? [[String: Any]] {
            print("   Phases array: \(phases.count) entries")
        }
        
        print("\n📝 ========== STEP 6: Returning Parsed Plan ==========")
        return planData
    }
    
    /// Repair plan by regenerating days array
    func repairPlan(
        repairPrompt: String,
        originalJSON: [String: Any]
    ) async throws -> [String: Any] {
        print("🔄 Sending repair request to AI...")
        
        let jsonResponse = try await callOpenAIAPI(prompt: repairPrompt)
        
        // Parse repaired response
        var cleanedJSON = jsonResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedJSON.hasPrefix("```json") {
            cleanedJSON = cleanedJSON.replacingOccurrences(of: "```json", with: "")
        }
        if cleanedJSON.hasPrefix("```") {
            cleanedJSON = cleanedJSON.replacingOccurrences(of: "```", with: "")
        }
        if cleanedJSON.hasSuffix("```") {
            cleanedJSON = String(cleanedJSON.dropLast(3))
        }
        cleanedJSON = cleanedJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let jsonData = cleanedJSON.data(using: .utf8),
              var repairedData = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            print("❌ Failed to parse repair response JSON")
            print("   Response preview: \(cleanedJSON.prefix(500))")
            throw AIGeneratorError.parseError(details: "Unable to convert repair response to JSON")
        }
        
        // Merge: keep original metadata/feasibility/phases, replace days
        if let days = repairedData["days"] as? [[String: Any]] {
            var mergedData = originalJSON
            mergedData["days"] = days
            return mergedData
        }
        
        return repairedData
    }
    
    /// Parse plan from validated JSON
    func parsePlanFromJSON(
        planJSON: [String: Any],
        goal: Goal,
        baseline: BaselineAssessment?,
        preferences: TrainingPreferences
    ) throws -> TrainingPlan {
        // Convert to JSON string for parseAIPlanResponse
        guard let jsonData = try? JSONSerialization.data(withJSONObject: planJSON, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw AIGeneratorError.parseError(details: "Unable to convert validated JSON back to string")
        }
        
        var plan = try parseAIPlanResponse(
            jsonString: jsonString,
            goal: goal,
            baseline: baseline,
            preferences: preferences
        )
        
        // Parse goal feasibility
        if let feasibility = planJSON["goal_feasibility"] as? [String: Any] {
            plan.goalFeasibility = parseGoalFeasibility(feasibility)
        }
        
        return plan
    }
    
    /// Parse goal feasibility from JSON
    private func parseGoalFeasibility(_ data: [String: Any]) -> GoalFeasibility? {
        guard let ratingString = data["rating"] as? String,
              let rating = GoalFeasibility.Rating(rawValue: ratingString),
              let isRealistic = data["is_realistic"] as? Bool,
              let reasoning = data["reasoning"] as? String,
              let confidenceString = data["confidence"] as? String,
              let confidence = GoalFeasibility.Confidence(rawValue: confidenceString) else {
            return nil
        }
        
        let recommendedTime = data["recommended_target_time_seconds"] as? Double
        
        return GoalFeasibility(
            rating: rating,
            isRealistic: isRealistic,
            recommendedTargetTime: recommendedTime,
            reasoning: reasoning,
            confidence: confidence
        )
    }
    
    // MARK: - Prompt Building
    
    private func buildCoachingPrompt(
        goal: Goal,
        baseline: BaselineAssessment?,
        preferences: TrainingPreferences,
        userProfile: UserTrainingProfile
    ) -> String {
        // Calculate dates
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: Date())
        let dateFormatter = ISO8601DateFormatter()
        let startDateString = dateFormatter.string(from: startDate)
        let raceDateString = dateFormatter.string(from: goal.eventDate)
        
        // Calculate paces
        var easyPace: Double = 390.0
        var tempoPace: Double = 345.0
        var intervalPace: Double = 320.0
        var vdot: Double? = nil
        
        if let baseline = baseline {
            easyPace = baseline.trainingPaces.easy.midpoint
            tempoPace = baseline.trainingPaces.threshold
            intervalPace = baseline.trainingPaces.interval
            vdot = baseline.vdot
        }
        
        var goalPace: Double? = nil
        if let targetTime = goal.targetTime, let distance = goal.distanceKm {
            goalPace = targetTime / distance
        }
        
        // Build availability info
        let availability = preferences.getEffectiveAvailability()
        let restDays = availability.restDays.sorted()
        let availableDays = availability.availableDays.sorted()
        
        // Build rest days as names for clarity
        let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let restDayNames = restDays.map { "\(dayNames[$0]) (day \($0))" }.joined(separator: ", ")
        
        var prompt = """
        SYSTEM ROLE:
        You are an elite endurance training planner that produces structured, machine-readable plans.
        Your output is deterministic JSON. Coaching tone belongs in coach_message only.
        
        INPUTS:
        
        athlete:
          baseline:
            source: \(baseline?.method.rawValue ?? "none")
            vdot: \(vdot.map { String(format: "%.1f", $0) } ?? "null")
            test_date: \(baseline.map { formatDate($0.assessmentDate) } ?? "null")
            easy_pace_sec_per_km: \(String(format: "%.0f", easyPace))
            tempo_pace_sec_per_km: \(String(format: "%.0f", tempoPace))
            interval_pace_sec_per_km: \(String(format: "%.0f", intervalPace))
        
        goal:
          race_name: \(goal.displayName)
          distance_km: \(String(format: "%.2f", goal.distanceKm ?? 5.0))
          goal_type: \(goal.type.rawValue)
        """
        
        if let targetTime = goal.targetTime, let gp = goalPace {
            prompt += """
          
          target_time_seconds: \(Int(targetTime))
          goal_pace_sec_per_km: \(String(format: "%.0f", gp))
        """
        } else {
            prompt += """
          
          target_time_seconds: null
          goal_type: completion
        """
        }
        
            prompt += """
            
          race_date: \(raceDateString)
        
        plan_window:
          start_date: \(startDateString)
          end_date: \(raceDateString)
          weeks_available: \(goal.weeksRemaining)
        
        availability:
          training_days: \(availableDays)
          rest_days: \(restDays) ⛔️ HARD CONSTRAINT: \(restDayNames) MUST be type "rest"
          long_run_day: \(availability.preferredLongRunDay ?? 0)
        
        preferences:
          weekly_run_days: \(preferences.weeklyRunDays)
          weekly_gym_days: \(preferences.weeklyGymDays)
        """
        
        // Add equipment info
        if preferences.weeklyGymDays > 0 {
            let equipment = userProfile.availableEquipment.map { $0.rawValue }.sorted().joined(separator: ", ")
                prompt += """
                
            available_equipment: \(equipment.isEmpty ? "none (bodyweight only)" : equipment)
            """
        }
        
                prompt += """
                
                
        CRITICAL RULES (MUST FOLLOW):
        - You MUST output JSON only. No markdown, no code blocks, no explanations.
        - The days array MUST contain one entry per calendar day between start_date and race_date.
        - Day types: "run" | "gym" | "rest" | "unavailable" (explicit, never null)
        - Define pace_context once with easy/tempo/interval/goal paces (VDOT-derived).
        - Workouts reference these paces; do not redefine pace logic per day.
        - Tempo pace must be at least 15 sec/km faster than easy pace.
        - Interval pace must be at least 10 sec/km faster than tempo pace.
        - Peak phase MUST include goal-pace exposure for time-based goals.
        - Even if goal is unrealistic, output a FULL plan + mark rating=unrealistic + provide recommended_target_time_seconds.
        - Days marked "unavailable" have no workout scheduled.
        - Days marked "rest" have no workout scheduled.
        - NEVER schedule gym workouts on consecutive days - minimum 48 hours between strength sessions.
        
        ⛔️ REST DAY ENFORCEMENT (PLAN WILL BE REJECTED IF VIOLATED):
        - Rest days are: \(restDayNames)
        - These days MUST have type "rest" - NO EXCEPTIONS
        - ANY run or gym workout on a rest day will cause IMMEDIATE plan rejection
        - This constraint overrides all other scheduling logic
        
        PRIMARY OBJECTIVE:
        Create a complete, date-by-date training plan from start_date → race_date that:
        1. Directly serves the goal
        2. Respects availability and rest days
        3. Uses realistic paces based on baseline fitness
        4. Progresses intensity and volume intelligently
        5. Outputs every planned day explicitly
        
        PACING RULES:
        - All run workouts must include explicit target paces
        - Paces must derive from baseline VDOT when available
        - Tempo ≠ easy pace (minimum 15 sec/km difference)
        - Interval pace ≠ tempo pace (minimum 10 sec/km difference)
        - For aggressive goals, build progressive "bridge paces" between current and goal
        
        GOAL FEASIBILITY:
        - Evaluate if the goal is realistic given baseline fitness and timeline
        - Rating: "realistic" | "ambitious" | "aggressive" | "unrealistic"
        - If goal pace is >20% faster than current threshold, likely unrealistic
        - If goal pace is 10-20% faster than threshold, ambitious or aggressive
        - If goal pace is <10% faster than threshold, realistic
        - Provide recommended_target_time_seconds if goal seems unrealistic
        - Always output a complete plan regardless of feasibility
        
        
        OUTPUT FORMAT (STRICT JSON):
        
        {
          "plan_metadata": {
            "generation_method": "ai_primary",
            "llm_provider": "openai",
            "llm_used": true,
            "baseline_used": {
              "source": "guided_test|recent_race|time_trial|none",
              "vdot": 42.5,
              "date": "2026-01-15"
            },
            "generated_at": "2026-01-25T14:30:00Z",
            "coach_message": "This 12-week plan builds progressively from your current fitness..."
          },
          
          "pace_context": {
            "easy_pace_sec_per_km": 390,
            "tempo_pace_sec_per_km": 345,
            "interval_pace_sec_per_km": 320,
            "goal_pace_sec_per_km": 300,
            "source": "vdot_derived"
          },
          
          "goal_feasibility": {
            "rating": "realistic|ambitious|aggressive|unrealistic",
            "is_realistic": true,
            "recommended_target_time_seconds": 1350,
            "reasoning": "Your goal requires a 15% pace improvement over 12 weeks, which is achievable with consistent training.",
            "confidence": "high|medium|low"
          },
          
          "phases": [
            {
              "name": "Base Building",
              "week_range": [1, 5],
              "focus": "Aerobic foundation and movement efficiency"
            },
            {
              "name": "Build Phase",
              "week_range": [6, 10],
              "focus": "Threshold and race-specific development"
            },
            {
              "name": "Peak Phase",
              "week_range": [11, 13],
              "focus": "Race readiness and intensity sharpening"
            },
            {
              "name": "Taper",
              "week_range": [14, 15],
              "focus": "Fatigue reduction and freshness"
            }
          ],
          
          "days": [
            {
              "date": "2026-01-27",
              "day_of_week": 1,
              "week_number": 1,
              "phase": "Base Building",
              "type": "run",
              "workout": {
                "run_type": "easy",
                "title": "Easy Monday Run",
                "description": "Comfortable aerobic pace, conversational effort",
                "target_distance_km": 8.0,
                "target_pace_sec_per_km": 390
              }
            },
            {
              "date": "2026-01-28",
              "day_of_week": 2,
              "week_number": 1,
              "phase": "Base Building",
              "type": "rest"
            },
            {
              "date": "2026-01-29",
              "day_of_week": 3,
              "week_number": 1,
              "phase": "Base Building",
              "type": "unavailable"
            }
          ]
        }
        
        IMPORTANT NOTES:
        - Every date from \(startDateString) to \(raceDateString) must be included
        - For run type: include workout object with run_type, title, description, target_distance_km, target_pace_sec_per_km
        - For gym type: NO workout object needed. Just date and type. App handles gym workout display.
        - For rest type: no workout object
        - For unavailable type: no workout object
        - Use ISO 8601 date format (YYYY-MM-DD) for all dates
        - Day of week: 0=Sunday, 1=Monday, 2=Tuesday, 3=Wednesday, 4=Thursday, 5=Friday, 6=Saturday
        - Run types: "easy", "long", "tempo", "intervals", "recovery", "race", "goal_pace"
        - Paces in seconds per kilometer (e.g., 360 = 6:00/km)
        
        Create the complete plan now. Output ONLY the JSON, no other text.
        """
        
        return prompt
    }
    
    // MARK: - Skeleton Generation (Fast, ~3 seconds)
    
    /// Generate plan skeleton for fast summary display.
    /// Returns only high-level metadata, no daily workouts.
    func generatePlanSkeleton(
        goal: Goal,
        baseline: BaselineAssessment?,
        preferences: TrainingPreferences
    ) async throws -> PlanSkeleton {
        print("⚡ ========== SKELETON GENERATION: Starting ==========")
        print("   Goal: \(goal.displayName)")
        print("   Weeks: \(goal.weeksRemaining)")
        
        guard apiKey != nil else {
            throw AIGeneratorError.aiNotConfigured
        }
        
        let prompt = buildSkeletonPrompt(
            goal: goal,
            baseline: baseline,
            preferences: preferences
        )
        
        print("   Prompt length: \(prompt.count) characters")
        
        // Use fast API call with lower token limit
        let jsonResponse = try await callOpenAIAPIFast(prompt: prompt, maxTokens: 1500)
        
        // Parse JSON response
        var cleanedJSON = jsonResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedJSON.hasPrefix("```json") {
            cleanedJSON = cleanedJSON.replacingOccurrences(of: "```json", with: "")
        }
        if cleanedJSON.hasPrefix("```") {
            cleanedJSON = cleanedJSON.replacingOccurrences(of: "```", with: "")
        }
        if cleanedJSON.hasSuffix("```") {
            cleanedJSON = String(cleanedJSON.dropLast(3))
        }
        cleanedJSON = cleanedJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let jsonData = cleanedJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw AIGeneratorError.parseError(details: "Failed to parse skeleton JSON")
        }
        
        let skeleton = try PlanSkeleton.parse(from: json)
        
        print("✅ Skeleton generated: \(skeleton.phases.count) phases, \(skeleton.weeklyTargets.count) weeks")
        print("⚡ ========== SKELETON GENERATION: Complete ==========")
        
        return skeleton
    }
    
    /// Build minimal prompt for skeleton generation.
    /// Fixed response size - does NOT scale with plan length.
    private func buildSkeletonPrompt(
        goal: Goal,
        baseline: BaselineAssessment?,
        preferences: TrainingPreferences
    ) -> String {
        // Calculate paces
        var easyPace: Double = 390.0
        var tempoPace: Double = 345.0
        var intervalPace: Double = 320.0
        var vdot: Double? = nil
        
        if let baseline = baseline {
            easyPace = baseline.trainingPaces.easy.midpoint
            tempoPace = baseline.trainingPaces.threshold
            intervalPace = baseline.trainingPaces.interval
            vdot = baseline.vdot
        }
        
        var goalPace: Double? = nil
        var goalPaceStr = "N/A (completion goal)"
        if let targetTime = goal.targetTime, let distance = goal.distanceKm {
            goalPace = targetTime / distance
            let minutes = Int(goalPace!) / 60
            let seconds = Int(goalPace!) % 60
            goalPaceStr = "\(minutes):\(String(format: "%02d", seconds))/km (\(Int(goalPace!))s/km)"
        }
        
        // Calculate pace gap for feasibility context
        var paceGapContext = ""
        if let gp = goalPace {
            let gapFromTempo = tempoPace - gp
            if gapFromTempo > 30 {
                paceGapContext = "Goal is \(Int(gapFromTempo))s/km faster than current tempo - aggressive target"
            } else if gapFromTempo > 15 {
                paceGapContext = "Goal is \(Int(gapFromTempo))s/km faster than current tempo - ambitious but achievable"
            } else if gapFromTempo > 0 {
                paceGapContext = "Goal is \(Int(gapFromTempo))s/km faster than current tempo - realistic"
            } else {
                paceGapContext = "Goal pace is slower than current tempo - very achievable"
            }
        }
        
        return """
        You are a running coach. Return ONLY valid JSON, no markdown.
        
        INPUTS:
        - Goal: \(goal.displayName), \(String(format: "%.1f", goal.distanceKm ?? 5.0))km
        - Target time: \(goal.targetTime.map { "\(Int($0))s" } ?? "completion")
        - GOAL PACE: \(goalPaceStr) - this is the target race pace
        - Weeks available: \(goal.weeksRemaining)
        - VDOT: \(vdot.map { String(format: "%.1f", $0) } ?? "unknown")
        - Current paces: easy=\(Int(easyPace))s/km, tempo=\(Int(tempoPace))s/km, interval=\(Int(intervalPace))s/km
        - Pace gap analysis: \(paceGapContext)
        - Run days/week: \(preferences.weeklyRunDays)
        - Gym days/week: \(preferences.weeklyGymDays)
        
        OUTPUT (JSON only, no explanations):
        {
          "phases": [
            { "name": "Base Building", "weeks": [1, 4] },
            { "name": "Build Up", "weeks": [5, 7] },
            { "name": "Peak", "weeks": [8, 8] },
            { "name": "Taper", "weeks": [9, 9] }
          ],
          "goal_feasibility": {
            "rating": "realistic|ambitious|aggressive|unrealistic",
            "is_realistic": true,
            "reasoning": "One sentence explaining pace gap analysis."
          },
          "pace_context": {
            "easy": \(Int(easyPace)),
            "tempo": \(Int(tempoPace)),
            "interval": \(Int(intervalPace)),
            "goal": \(goalPace.map { String(Int($0)) } ?? "null")
          },
          "weekly_targets": [
            { "week": 1, "km": 25, "runs": 4, "gym": 2 }
          ],
          "coach_message": "One or two sentences max."
        }
        
        RULES:
        - phases: 2-4 phases covering all \(goal.weeksRemaining) weeks
        - MUST include Peak phase in final weeks (before taper) for goal-pace work
        - weekly_targets: one entry per week (week 1 to \(goal.weeksRemaining))
        - feasibility: based on comparing goal pace (\(goalPace.map { String(Int($0)) } ?? "N/A")s/km) to current tempo (\(Int(tempoPace))s/km)
        - NO days array, NO workout details, NO descriptions
        - Response must be under 1000 tokens
        """
    }
    
    // MARK: - Daily Schedule Generation (Deferred)
    
    /// Generate daily workout schedule. Called only when user taps "View Full Plan".
    func generateDailySchedule(
        skeleton: PlanSkeleton,
        goal: Goal,
        baseline: BaselineAssessment?,
        preferences: TrainingPreferences
    ) async throws -> [[String: Any]] {
        print("📅 ========== DAILY SCHEDULE GENERATION: Starting ==========")
        print("   Weeks: \(goal.weeksRemaining)")
        
        guard apiKey != nil else {
            throw AIGeneratorError.aiNotConfigured
        }
        
        let prompt = buildDailySchedulePrompt(
            skeleton: skeleton,
            goal: goal,
            baseline: baseline,
            preferences: preferences
        )
        
        print("   Prompt length: \(prompt.count) characters")
        
        let jsonResponse = try await callOpenAIAPI(prompt: prompt)
        
        // Parse JSON response
        var cleanedJSON = jsonResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedJSON.hasPrefix("```json") {
            cleanedJSON = cleanedJSON.replacingOccurrences(of: "```json", with: "")
        }
        if cleanedJSON.hasPrefix("```") {
            cleanedJSON = cleanedJSON.replacingOccurrences(of: "```", with: "")
        }
        if cleanedJSON.hasSuffix("```") {
            cleanedJSON = String(cleanedJSON.dropLast(3))
        }
        cleanedJSON = cleanedJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let jsonData = cleanedJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let days = json["days"] as? [[String: Any]] else {
            throw AIGeneratorError.parseError(details: "Failed to parse daily schedule JSON")
        }
        
        print("✅ Daily schedule generated: \(days.count) days")
        print("📅 ========== DAILY SCHEDULE GENERATION: Complete ==========")
        
        return days
    }
    
    /// Build prompt for daily schedule generation.
    private func buildDailySchedulePrompt(
        skeleton: PlanSkeleton,
        goal: Goal,
        baseline: BaselineAssessment?,
        preferences: TrainingPreferences
    ) -> String {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: Date())
        let dateFormatter = ISO8601DateFormatter()
        let startDateString = dateFormatter.string(from: startDate)
        let raceDateString = dateFormatter.string(from: goal.eventDate)
        
        let availability = preferences.getEffectiveAvailability()
        let restDays = availability.restDays.sorted()
        
        // Build phases string
        let phasesStr = skeleton.phases.map { phase in
            "\(phase.name): weeks \(phase.weekRange.lowerBound)-\(phase.weekRange.upperBound)"
        }.joined(separator: ", ")
        
        // Build rest days as names for clarity
        let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let restDayNames = restDays.map { "\(dayNames[$0]) (day \($0))" }.joined(separator: ", ")
        
        // Calculate goal pace if time-based goal
        var goalPaceStr = "N/A (completion goal)"
        if let targetTime = goal.targetTime, let distance = goal.distanceKm {
            let goalPace = targetTime / distance
            let minutes = Int(goalPace) / 60
            let seconds = Int(goalPace) % 60
            goalPaceStr = "\(minutes):\(String(format: "%02d", seconds))/km (\(Int(goalPace))s/km)"
        }
        
        return """
        You are a running coach. Return ONLY valid JSON with a days array.
        
        CONTEXT:
        - Goal: \(goal.displayName), \(String(format: "%.1f", goal.distanceKm ?? 5.0))km
        - GOAL PACE: \(goalPaceStr) - athlete must reach this pace by race day
        - Phases: \(phasesStr)
        - Current paces: easy=\(Int(skeleton.paceContext.easyPace))s/km, tempo=\(Int(skeleton.paceContext.tempoPace))s/km, interval=\(Int(skeleton.paceContext.intervalPace))s/km
        - Run days/week: \(preferences.weeklyRunDays), Gym days/week: \(preferences.weeklyGymDays)
        
        ⛔️ HARD CONSTRAINT - REST DAYS:
        The following days MUST have type "rest": \(restDayNames)
        ANY workout (run or gym) on these days is INVALID and will cause plan rejection.
        
        OUTPUT FORMAT (JSON only):
        {
          "days": [
            { "date": "2026-01-25", "type": "run", "run_type": "easy", "distance_km": 6.0, "pace": 385 },
            { "date": "2026-01-26", "type": "gym" },
            { "date": "2026-01-27", "type": "rest" }
          ]
        }
        
        RULES:
        - Generate one entry per day from \(startDateString) to \(raceDateString)
        - Date format: YYYY-MM-DD
        - type: "run" | "gym" | "rest"
        - For gym: ONLY include date and type. No duration, no title, no description.
        - For run: include run_type, distance_km, pace
        - run_type: "easy" | "long" | "tempo" | "intervals" | "recovery" | "goal_pace"
        - NO descriptions, NO titles, NO prose
        - No gym on consecutive days (minimum 48 hours between strength sessions)
        
        PACE PROGRESSION (CRITICAL):
        - Week 1-3: Focus on easy pace (\(Int(skeleton.paceContext.easyPace))s/km) and tempo (\(Int(skeleton.paceContext.tempoPace))s/km)
        - Week 4+: Introduce interval work at \(Int(skeleton.paceContext.intervalPace))s/km
        - Final 3-4 weeks before taper: Include 2-3 "goal_pace" workouts at target race pace
        - Tempo pace should decrease by ~5s/km every 2-3 weeks as fitness builds
        """
    }
    
    // MARK: - API Calls
    
    /// Fast API call for skeleton generation (lower token limit, faster response)
    private func callOpenAIAPIFast(prompt: String, maxTokens: Int) async throws -> String {
        guard let apiKey = apiKey else {
            throw AIGeneratorError.aiNotConfigured
        }
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30  // 30 second timeout for fast calls
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o",  // Best quality model for all generation
            "messages": [
                ["role": "system", "content": "Return only valid JSON, no markdown."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.5,
            "max_tokens": maxTokens
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        print("⚡ Fast API call: gpt-4o, max_tokens=\(maxTokens)")
        
        let startTime = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let elapsedTime = Date().timeIntervalSince(startTime)
        
        print("⚡ Response in \(String(format: "%.2f", elapsedTime))s")
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AIGeneratorError.apiError(statusCode: statusCode, message: "Fast API call failed")
        }
        
        guard let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = jsonResponse["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIGeneratorError.parseError(details: "Failed to parse OpenAI response")
        }
        
        return content
    }
    
    private func callOpenAIAPI(prompt: String) async throws -> String {
        print("\n🌐 ========== API CALL: Starting ==========")
        
        // Check API key is available
        guard let apiKey = apiKey else {
            print("❌ No API key available")
            throw AIGeneratorError.aiNotConfigured
        }
        print("✅ API key present (length: \(apiKey.count) chars)")
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        // Use GPT-4o for best quality training plans
        let modelName = "gpt-4o"
        
        let requestBody: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": "You are an elite endurance training planner. Return only valid JSON, no markdown, no explanations."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": 8000
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        print("📤 Making HTTP request to OpenAI API...")
        print("   Model: \(modelName)")
        print("   Temperature: 0.7")
        print("   Max Tokens: 8000")
        print("   Request body size: \(request.httpBody?.count ?? 0) bytes")
        print("   Timestamp: \(Date())")
        
        let startTime = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let elapsedTime = Date().timeIntervalSince(startTime)
        
        print("📥 Received response from OpenAI")
        print("   Elapsed time: \(String(format: "%.2f", elapsedTime))s")
        print("   Response data size: \(data.count) bytes")
        
        print("📥 Received response from OpenAI API")
        print("   Response size: \(data.count) bytes")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid HTTP response from OpenAI API")
            throw AIGeneratorError.invalidResponse
        }
        
        print("   HTTP Status Code: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            print("❌ OpenAI API returned error status: \(httpResponse.statusCode)")
            var errorMessage: String?
            
            // Try to parse error message
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                errorMessage = message
                print("   Error message: \(message)")
                print("   Error type: \(error["type"] ?? "unknown")")
                if let code = error["code"] as? String {
                    print("   Error code: \(code)")
                }
            } else {
                // Try to print raw response
                if let responseString = String(data: data, encoding: .utf8) {
                    print("   Raw response: \(responseString.prefix(500))")
                    errorMessage = responseString
                }
            }
            
            throw AIGeneratorError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        print("✅ HTTP 200 - Success")
        print("📦 Parsing JSON response structure...")
        
        let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = jsonResponse?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            print("❌ Failed to parse OpenAI response structure")
            if let jsonResponse = jsonResponse {
                print("   Response keys: \(jsonResponse.keys.joined(separator: ", "))")
                if let choices = jsonResponse["choices"] as? [[String: Any]] {
                    print("   Choices count: \(choices.count)")
                }
            }
            throw AIGeneratorError.parseError(details: "Missing 'choices' or 'message' in API response")
        }
        
        print("✅ Successfully extracted content from OpenAI response")
        print("   Content length: \(content.count) chars")
        print("   Estimated tokens used: ~\(content.count / 4)")
        
        if let usage = jsonResponse?["usage"] as? [String: Any] {
            print("   Actual tokens:")
            if let prompt_tokens = usage["prompt_tokens"] as? Int {
                print("     - Prompt: \(prompt_tokens)")
            }
            if let completion_tokens = usage["completion_tokens"] as? Int {
                print("     - Completion: \(completion_tokens)")
            }
            if let total_tokens = usage["total_tokens"] as? Int {
                print("     - Total: \(total_tokens)")
            }
        }
        
        print("\n🌐 ========== API CALL: Complete ==========\n")
        return content
    }
    
    // MARK: - Response Parsing
    
    private func parseAIPlanResponse(
        jsonString: String,
        goal: Goal,
        baseline: BaselineAssessment?,
        preferences: TrainingPreferences
    ) throws -> TrainingPlan {
        // Extract JSON from potential markdown code blocks
        var cleanedJSON = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove markdown code blocks if present
        if cleanedJSON.hasPrefix("```json") {
            cleanedJSON = cleanedJSON.replacingOccurrences(of: "```json", with: "")
        }
        if cleanedJSON.hasPrefix("```") {
            cleanedJSON = cleanedJSON.replacingOccurrences(of: "```", with: "")
        }
        if cleanedJSON.hasSuffix("```") {
            cleanedJSON = String(cleanedJSON.dropLast(3))
        }
        cleanedJSON = cleanedJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Parse JSON
        guard let jsonData = cleanedJSON.data(using: .utf8),
              let planData = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            print("❌ Failed to parse AI response as JSON")
            print("   Response preview: \(cleanedJSON.prefix(500))")
            throw AIGeneratorError.parseError(details: "Invalid JSON in AI response")
        }
        
        // Parse days array (required)
        guard let daysArray = planData["days"] as? [[String: Any]] else {
            print("❌ Missing 'days' array in AI response")
            print("   Available keys: \(planData.keys)")
            throw AIGeneratorError.parseError(details: "Missing 'days' array in response")
        }
        
        // Parse phases array (required)
        guard let phasesArray = planData["phases"] as? [[String: Any]] else {
            print("❌ Missing 'phases' array in AI response")
            print("   Available keys: \(planData.keys)")
            throw AIGeneratorError.parseError(details: "Missing 'phases' array in response")
        }
        
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: Date())
        
        // Primary: ISO8601 full format (2026-01-25T00:00:00Z)
        let isoFormatter = ISO8601DateFormatter()
        
        // Fallback: Date-only format (2026-01-25) - AI often returns this
        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        dateOnlyFormatter.timeZone = TimeZone.current
        
        print("📋 Parsing \(daysArray.count) days into workouts...")
        
        // Parse all days into workouts
        var allWorkouts: [PlannedWorkout] = []
        var skippedDays = 0
        var restDays = 0
        var unavailableDays = 0
        var parseErrors: [String] = []
        
        for (index, dayData) in daysArray.enumerated() {
            guard let dateString = dayData["date"] as? String else {
                parseErrors.append("Day \(index): Missing 'date' field")
                skippedDays += 1
                continue
            }
            
            // Try ISO8601 first, then fallback to YYYY-MM-DD
            guard let date = isoFormatter.date(from: dateString) 
                  ?? dateOnlyFormatter.date(from: dateString) else {
                parseErrors.append("Day \(index): Invalid date format '\(dateString)'")
                skippedDays += 1
                continue
            }
            
            guard let typeString = dayData["type"] as? String else {
                parseErrors.append("Day \(index) (\(dateString)): Missing 'type' field")
                skippedDays += 1
                continue
            }
            
            // Parse based on type
            let type = typeString.lowercased()
            
            if type == "rest" || type == "unavailable" {
                // Rest or unavailable days - create placeholder (optional, or skip)
                if type == "rest" {
                    restDays += 1
                    allWorkouts.append(PlannedWorkout(
                        date: date,
                        type: .rest,
                        title: "Rest Day",
                        description: "Complete rest or light stretching. Allow your body to recover and adapt."
                    ))
                } else {
                    unavailableDays += 1
                }
                // Unavailable days are not added to workouts
                continue
            }
            
            // For run/gym types, parse workout details
            guard let workoutData = dayData["workout"] as? [String: Any] else {
                parseErrors.append("Day \(index) (\(dateString), type=\(type)): Missing 'workout' object")
                skippedDays += 1
                continue
            }
            
            if type == "run" {
                guard let runType = workoutData["run_type"] as? String else {
                    parseErrors.append("Day \(index) (\(dateString)): Missing 'run_type' in workout")
                    skippedDays += 1
                    continue
                }
                
                guard let title = workoutData["title"] as? String else {
                    parseErrors.append("Day \(index) (\(dateString)): Missing 'title' in workout")
                    skippedDays += 1
                    continue
                }
                
                guard let description = workoutData["description"] as? String else {
                    parseErrors.append("Day \(index) (\(dateString)): Missing 'description' in workout")
                    skippedDays += 1
                    continue
                }
                
                guard let distanceKm = workoutData["target_distance_km"] as? Double else {
                    parseErrors.append("Day \(index) (\(dateString)): Missing or invalid 'target_distance_km' (got: \(workoutData["target_distance_km"] ?? "nil"))")
                    skippedDays += 1
                    continue
                }
                
                guard let paceSecondsPerKm = workoutData["target_pace_sec_per_km"] as? Double else {
                    parseErrors.append("Day \(index) (\(dateString)): Missing or invalid 'target_pace_sec_per_km' (got: \(workoutData["target_pace_sec_per_km"] ?? "nil"))")
                    skippedDays += 1
                    continue
                }
                
                let workoutType = mapRunType(runType)
                
                allWorkouts.append(PlannedWorkout(
                    date: date,
                    type: workoutType,
                    title: title,
                    description: description,
                    targetDistanceKm: distanceKm,
                    targetPaceSecondsPerKm: paceSecondsPerKm
                ))
                
            } else if type == "gym" {
                // Gym workouts are simplified - just "Strength Training" with no exercise details
                allWorkouts.append(PlannedWorkout(
                    date: date,
                    type: .gym,
                    title: "Strength Training",
                    description: nil
                ))
            } else {
                parseErrors.append("Day \(index) (\(dateString)): Unknown type '\(type)'")
                skippedDays += 1
            }
        }
        
        print("   Total days processed: \(daysArray.count)")
        print("   Rest days: \(restDays)")
        print("   Unavailable days: \(unavailableDays)")
        print("   Workouts created: \(allWorkouts.count)")
        print("   Days skipped due to errors: \(skippedDays)")
        
        if !parseErrors.isEmpty {
            print("   ⚠️ Parse errors (\(parseErrors.count)):")
            for (i, error) in parseErrors.prefix(10).enumerated() {
                print("     \(i+1). \(error)")
            }
            if parseErrors.count > 10 {
                print("     ... and \(parseErrors.count - 10) more errors")
            }
        }
        
        // Group workouts into weeks
        var weeks: [WeekPlan] = []
        var currentWeekNumber = 1
        var currentWeekStart = startDate
        
        while currentWeekStart <= goal.eventDate {
            guard let weekEnd = calendar.date(byAdding: .day, value: 6, to: currentWeekStart) else {
                break
            }
            
            // Get workouts for this week
            let weekWorkouts = allWorkouts.filter { workout in
                workout.date >= currentWeekStart && workout.date <= weekEnd
            }.sorted { $0.date < $1.date }
            
            // Calculate target weekly km
            let targetWeeklyKm = weekWorkouts.reduce(0.0) { sum, workout in
                sum + (workout.targetDistanceKm ?? 0)
            }
            
            // Determine phase for this week
            let phase = determinePhase(weekNumber: currentWeekNumber, phases: phasesArray)
            
            weeks.append(WeekPlan(
                weekNumber: currentWeekNumber,
                startDate: currentWeekStart,
                endDate: weekEnd,
                phase: phase,
                targetWeeklyKm: targetWeeklyKm,
                workouts: weekWorkouts
            ))
            
            currentWeekNumber += 1
            guard let nextWeekStart = calendar.date(byAdding: .weekOfYear, value: 1, to: currentWeekStart) else {
                break
            }
            currentWeekStart = nextWeekStart
            
            // Safety break
            if currentWeekNumber > 52 {
                break
            }
        }
        
        // Parse phases for context
        let phases = phasesArray.compactMap { phaseData -> TrainingPhase? in
            guard let name = phaseData["name"] as? String,
                  let weekRange = phaseData["week_range"] as? [Int],
                  weekRange.count == 2,
                  let focus = phaseData["focus"] as? String else {
                return nil
            }
            
            let range = weekRange[0]...weekRange[1]
            
            if name.lowercased().contains("base") {
                return .baseBuilding(weeks: range)
            } else if name.lowercased().contains("build") {
                return .buildUp(weeks: range)
            } else if name.lowercased().contains("peak") {
                return .peakTraining(weeks: range)
            } else if name.lowercased().contains("taper") {
                return .taper(weeks: range)
            } else {
                return .baseBuilding(weeks: range)
            }
        }
        
        // Build generation context
        let generationContext = PlanGenerationContext(
            generationMethod: .aiEnhanced,
            baselineSource: baseline != nil ? .guidedTest : .none,
            baselineVDOT: baseline?.vdot,
            baselineDate: baseline?.assessmentDate,
            goalInfluence: determineGoalInfluence(goal: goal, baseline: baseline),
            confidenceLevel: baseline != nil ? .high : .medium,
            constraintsApplied: ["AI-generated day-by-day plan", "Goal feasibility analysis"],
            llmStatus: .enabled,
            generatedAt: Date()
        )
        
        return TrainingPlan(
            goalId: goal.id,
            startDate: startDate,
            eventDate: goal.eventDate,
            generationMethod: .llmGenerated,
            totalWeeks: weeks.count,
            weeklyRunDays: preferences.weeklyRunDays,
            weeklyGymDays: preferences.weeklyGymDays,
            availability: preferences.getEffectiveAvailability(),
            phases: phases,
            weeks: weeks,
            generationContext: generationContext
        )
    }
    
    // Helper to map run_type strings to WorkoutType
    private func mapRunType(_ runType: String) -> PlannedWorkout.WorkoutType {
        switch runType.lowercased() {
        case "easy": return .easyRun
        case "long": return .longRun
        case "tempo": return .tempoRun
        case "intervals": return .intervalWorkout
        case "recovery": return .recoveryRun
        case "race": return .raceSimulation
        default: return .easyRun
        }
    }
    
    // Helper to determine phase for a week
    private func determinePhase(weekNumber: Int, phases: [[String: Any]]) -> TrainingPhase {
        for phaseData in phases {
            guard let weekRange = phaseData["week_range"] as? [Int],
                  weekRange.count == 2 else {
                continue
            }
            
            if weekNumber >= weekRange[0] && weekNumber <= weekRange[1] {
                guard let name = phaseData["name"] as? String else {
                    continue
                }
                
                let range = weekRange[0]...weekRange[1]
        
        if name.lowercased().contains("base") {
                    return .baseBuilding(weeks: range)
        } else if name.lowercased().contains("build") {
                    return .buildUp(weeks: range)
        } else if name.lowercased().contains("peak") {
                    return .peakTraining(weeks: range)
        } else if name.lowercased().contains("taper") {
                    return .taper(weeks: range)
                }
            }
        }
        
        // Default fallback
        return .baseBuilding(weeks: 1...4)
    }
    
    private func parsePhase(name: String, weekNumber: Int) -> TrainingPhase {
        let weekRange = weekNumber...weekNumber
        
        if name.lowercased().contains("base") {
            return TrainingPhase.baseBuilding(weeks: weekRange)
        } else if name.lowercased().contains("build") {
            return TrainingPhase.buildUp(weeks: weekRange)
        } else if name.lowercased().contains("peak") {
            return TrainingPhase.peakTraining(weeks: weekRange)
        } else if name.lowercased().contains("taper") {
            return TrainingPhase.taper(weeks: weekRange)
        } else {
            return TrainingPhase.baseBuilding(weeks: weekRange)
        }
    }
    
    private func determineGoalInfluence(goal: Goal, baseline: BaselineAssessment?) -> PlanGenerationContext.GoalInfluence {
        if goal.type == .completion {
            return .noTimeGoal
        }
        
        guard let baseline = baseline,
              let goalPace = goal.trainingPaces?.racePace ?? (goal.targetTime.map { $0 / (goal.distanceKm ?? 5.0) }),
              let goalDistance = goal.distanceKm else {
            return .pacesConstrained
        }
        
        let predictedTime = VDOTCalculator.predictRaceTime(vdot: baseline.vdot, distanceKm: goalDistance)
        let predictedPace = predictedTime / goalDistance
        
        let paceRatio = goalPace / predictedPace
        if paceRatio < 0.9 {
            return .pacesConstrained
        } else {
            return .pacesAligned
        }
    }
    
    // MARK: - Helpers
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    private func formatPace(_ secondsPerKm: Double) -> String {
        let totalSeconds = Int(secondsPerKm)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d/km", minutes, seconds)
    }
    
    private func dayName(for dayOfWeek: Int) -> String {
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return days[dayOfWeek % 7]
    }
}

// MARK: - Supporting Types

enum AIGeneratorError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, message: String?)
    case parseError(details: String?)
    case aiNotConfigured
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from AI API"
        case .apiError(let code, let message):
            if let message = message {
                return "AI API error (HTTP \(code)): \(message)"
            }
            return "AI API error: HTTP \(code)"
        case .parseError(let details):
            if let details = details {
                return "Failed to parse AI response: \(details)"
            }
            return "Failed to parse AI response"
        case .aiNotConfigured:
            return "AI Coach is not configured. Please add your OpenAI API key in Settings."
        }
    }
}

// MARK: - Extensions

extension PlannedWorkout.WorkoutType {
    static func from(string: String) -> PlannedWorkout.WorkoutType {
        switch string.lowercased() {
        case "easyrun": return .easyRun
        case "longrun": return .longRun
        case "temporun": return .tempoRun
        case "intervalworkout": return .intervalWorkout
        case "racesimulation": return .raceSimulation
        case "gym": return .gym
        case "rest": return .rest
        case "recoveryrun": return .recoveryRun
        default: return .easyRun
        }
    }
}
