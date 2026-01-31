import Foundation

/// Refines rule-based training plans using LLM for personalization
class LLMPlanRefiner {
    private let apiKey: String
    
    // MARK: - Initialization
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    // MARK: - Public Methods
    
    /// Refine a complete training plan with LLM
    func refinePlan(
        _ basePlan: TrainingPlan,
        goal: Goal,
        baseline: BaselineAssessment?
    ) async throws -> TrainingPlan {
        // Build context for LLM
        let context = buildContext(basePlan, goal: goal, baseline: baseline)
        
        // Call LLM API with structured prompt
        let refinedWorkouts = try await refineWorkouts(
            workouts: basePlan.allWorkouts,
            context: context
        )
        
        // Merge refinements back into plan
        return mergeLLMRefinements(basePlan, refinedWorkouts: refinedWorkouts)
    }
    
    // MARK: - Context Building
    
    private func buildContext(
        _ plan: TrainingPlan,
        goal: Goal,
        baseline: BaselineAssessment?
    ) -> String {
        var context = """
        Goal: \(goal.displayName)
        """
        
        if let targetTime = goal.formattedTargetTime {
            context += "\nTarget Time: \(targetTime)"
        } else {
            context += "\nGoal Type: Completion (no time goal)"
        }
        
        context += """
        
        Event Date: \(formatDate(goal.eventDate))
        Distance: \(String(format: "%.1f km", goal.distanceKm ?? 0))
        """
        
        if let baseline = baseline {
            context += "\nRunner's VDOT: \(String(format: "%.1f", baseline.vdot))"
        }
        
        context += "\nWeeks until race: \(goal.weeksRemaining)"
        
        if let notes = goal.notes, !notes.isEmpty {
            context += "\nGoal Notes: \(notes)"
        }
        
        context += "\n\nTraining Plan: \(plan.totalWeeks) weeks, \(plan.weeklyRunDays) run days per week"
        context += "\nPhases: \(plan.phases.map { $0.name }.joined(separator: " → "))"
        
        return context
    }
    
    // MARK: - LLM API Call
    
    private func refineWorkouts(
        workouts: [PlannedWorkout],
        context: String
    ) async throws -> [WorkoutRefinement] {
        // Batch workouts for efficiency (process 10 at a time)
        let batchSize = 10
        var allRefinements: [WorkoutRefinement] = []
        
        for batchStart in stride(from: 0, to: workouts.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, workouts.count)
            let batch = Array(workouts[batchStart..<batchEnd])
            
            let batchRefinements = try await refineBatch(batch, context: context)
            allRefinements.append(contentsOf: batchRefinements)
        }
        
        return allRefinements
    }
    
    private func refineBatch(
        _ workouts: [PlannedWorkout],
        context: String
    ) async throws -> [WorkoutRefinement] {
        let prompt = buildPrompt(workouts: workouts, context: context)
        return try await callOpenAIAPI(prompt: prompt, workouts: workouts)
    }
    
    // MARK: - Prompt Building
    
    private func buildPrompt(workouts: [PlannedWorkout], context: String) -> String {
        var prompt = """
        You are a professional running coach creating personalized training plans.
        
        CONTEXT:
        \(context)
        
        TASK:
        Refine the following workouts by providing:
        1. Engaging, motivational workout titles (e.g., "Tuesday Tempo Builder", "Weekend Long Run")
        2. Brief, encouraging descriptions (1-2 sentences)
        3. Ensure variety in language and progression across weeks
        4. Keep technical accuracy - DO NOT change paces, distances, or intervals
        
        WORKOUTS TO REFINE:
        
        """
        
        for (index, workout) in workouts.enumerated() {
            prompt += "\n[\(index + 1)] \(workout.type.displayName)"
            
            if let distance = workout.targetDistanceKm {
                prompt += " - \(String(format: "%.1f km", distance))"
            }
            
            if let pace = workout.targetPaceSecondsPerKm {
                let paceMin = Int(pace) / 60
                let paceSec = Int(pace) % 60
                prompt += " @ \(paceMin):\(String(format: "%02d", paceSec))/km"
            }
            
            if let intervals = workout.intervals, !intervals.isEmpty {
                prompt += "\n   Intervals: \(intervals.count) segments"
            }
            
            prompt += "\n   Current: \(workout.title)"
            if let desc = workout.description {
                prompt += " - \(desc)"
            }
            prompt += "\n"
        }
        
        prompt += """
        
        RESPONSE FORMAT:
        Return a JSON array with objects containing:
        - index: workout number (1-based)
        - title: new engaging title
        - description: motivational description
        
        Example:
        [
          {"index": 1, "title": "Monday Shakeout", "description": "Easy miles to start the week fresh. Keep it conversational."},
          {"index": 2, "title": "Tuesday Tempo Test", "description": "Push the pace at threshold. Feel strong and controlled."}
        ]
        """
        
        return prompt
    }
    
    // MARK: - API Implementation
    
    private func callOpenAIAPI(prompt: String, workouts: [PlannedWorkout]) async throws -> [WorkoutRefinement] {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "system", "content": "You are a professional running coach. Return only valid JSON, no markdown."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": 2000
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw LLMError.apiError(statusCode: httpResponse.statusCode)
        }
        
        // Parse response
        let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = jsonResponse?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.parseError
        }
        
        return try parseRefinements(from: content, workouts: workouts)
    }
    
    // MARK: - Response Parsing
    
    private func parseRefinements(from text: String, workouts: [PlannedWorkout]) throws -> [WorkoutRefinement] {
        // Extract JSON from response (handle markdown code blocks)
        var jsonText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if jsonText.hasPrefix("```json") {
            jsonText = jsonText.replacingOccurrences(of: "```json", with: "")
        }
        if jsonText.hasPrefix("```") {
            jsonText = jsonText.replacingOccurrences(of: "```", with: "")
        }
        if jsonText.hasSuffix("```") {
            jsonText = String(jsonText.dropLast(3))
        }
        
        jsonText = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let jsonData = jsonText.data(using: .utf8),
              let refinementData = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            // If parsing fails, return empty refinements (graceful fallback)
            print("⚠️ Failed to parse LLM response, using original workouts")
            return []
        }
        
        var refinements: [WorkoutRefinement] = []
        
        for item in refinementData {
            guard let index = item["index"] as? Int,
                  index >= 1 && index <= workouts.count else {
                continue
            }
            
            let workout = workouts[index - 1]
            let title = item["title"] as? String
            let description = item["description"] as? String
            
            refinements.append(WorkoutRefinement(
                workoutId: workout.id,
                refinedTitle: title,
                refinedDescription: description
            ))
        }
        
        return refinements
    }
    
    // MARK: - Merge Refinements
    
    private func mergeLLMRefinements(
        _ basePlan: TrainingPlan,
        refinedWorkouts: [WorkoutRefinement]
    ) -> TrainingPlan {
        var updatedPlan = basePlan
        
        // Create lookup dictionary for refinements
        let refinementMap = Dictionary(uniqueKeysWithValues: refinedWorkouts.map { ($0.workoutId, $0) })
        
        // Update each week's workouts
        for weekIndex in 0..<updatedPlan.weeks.count {
            var week = updatedPlan.weeks[weekIndex]
            
            for workoutIndex in 0..<week.workouts.count {
                var workout = week.workouts[workoutIndex]
                
                if let refinement = refinementMap[workout.id] {
                    // Apply refinements
                    if let title = refinement.refinedTitle {
                        workout = PlannedWorkout(
                            id: workout.id,
                            date: workout.date,
                            type: workout.type,
                            title: title,
                            description: refinement.refinedDescription ?? workout.description,
                            completed: workout.completed,
                            actualWorkoutId: workout.actualWorkoutId,
                            targetDistanceKm: workout.targetDistanceKm,
                            targetDurationSeconds: workout.targetDurationSeconds,
                            targetPaceSecondsPerKm: workout.targetPaceSecondsPerKm,
                            intervals: workout.intervals
                        )
                    }
                }
                
                week.workouts[workoutIndex] = workout
            }
            
            updatedPlan.weeks[weekIndex] = week
        }
        
        // Update generation method to hybrid
        updatedPlan = TrainingPlan(
            id: updatedPlan.id,
            goalId: updatedPlan.goalId,
            createdAt: updatedPlan.createdAt,
            lastModified: Date(),
            startDate: updatedPlan.startDate,
            eventDate: updatedPlan.eventDate,
            generationMethod: .hybrid,
            totalWeeks: updatedPlan.totalWeeks,
            weeklyRunDays: updatedPlan.weeklyRunDays,
            weeklyGymDays: updatedPlan.weeklyGymDays,
            availability: updatedPlan.availability,
            phases: updatedPlan.phases,
            weeks: updatedPlan.weeks
        )
        
        return updatedPlan
    }
    
    // MARK: - Helpers
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Types

struct WorkoutRefinement {
    let workoutId: UUID
    let refinedTitle: String?
    let refinedDescription: String?
}

enum LLMError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int)
    case parseError
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from LLM API"
        case .apiError(let code):
            return "LLM API error: HTTP \(code)"
        case .parseError:
            return "Failed to parse LLM response"
        }
    }
}
