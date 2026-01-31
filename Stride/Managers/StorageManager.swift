import Foundation
import Combine

/// Manages cloud storage of workout sessions and goals using the backend API
class StorageManager: ObservableObject {
    @Published var workouts: [WorkoutSession] = []
    @Published var isLoading: Bool = false
    @Published var lastError: APIError?
    
    private let api = APIClient.shared
    
    init() {
        // Load workouts asynchronously on init if authenticated
        if api.isAuthenticated {
            Task {
                await loadWorkoutsAsync()
            }
        }
    }
    
    // MARK: - Workout Management
    
    /// Save a completed workout session
    func saveWorkout(_ session: WorkoutSession) {
        Task {
            await saveWorkoutAsync(session)
        }
    }
    
    /// Save a completed workout session (async)
    func saveWorkoutAsync(_ session: WorkoutSession) async {
        guard api.isAuthenticated else {
            print("⚠️ Not authenticated, cannot save workout")
            return
        }
        
        await MainActor.run { isLoading = true }
        
        do {
            let body: [String: Any] = [
                "id": session.id.uuidString,
                "startTime": ISO8601DateFormatter().string(from: session.startTime),
                "endTime": ISO8601DateFormatter().string(from: session.endTime),
                "accumulatedActiveTime": session.accumulatedActiveTime,
                "pauseIntervalsJson": session.pauseIntervals.map { ["start": ISO8601DateFormatter().string(from: $0.0), "end": ISO8601DateFormatter().string(from: $0.1)] },
                "workoutTitle": session.workoutTitle as Any,
                "effortRating": session.effortRating as Any,
                "notes": session.notes as Any,
                "fatigueLevel": session.fatigueLevel as Any,
                "injuryFlag": session.injuryFlag as Any,
                "injuryNotes": session.injuryNotes as Any,
                "plannedWorkoutId": session.plannedWorkoutId?.uuidString as Any,
                "splits": session.splits.map { split in
                    [
                        "id": split.id.uuidString,
                        "kmIndex": split.kmIndex,
                        "splitTimeSeconds": split.splitTimeSeconds,
                        "avgPaceSecondsPerKm": split.avgPaceSecondsPerKm,
                        "avgHeartRate": split.avgHeartRate as Any,
                        "avgCadence": split.avgCadence as Any,
                        "avgSpeedMps": split.avgSpeedMps as Any
                    ]
                },
                "samples": session.recentSamples.map { sample in
                    [
                        "id": sample.id.uuidString,
                        "timestamp": ISO8601DateFormatter().string(from: sample.timestamp),
                        "speedMps": sample.speedMps,
                        "paceSecPerKm": sample.paceSecPerKm,
                        "totalDistanceMeters": sample.totalDistanceMeters,
                        "cadenceSpm": sample.cadenceSpm as Any,
                        "steps": sample.steps as Any,
                        "heartRate": sample.heartRate as Any
                    ]
                }
            ]
            
            _ = try await api.post("/workouts", body: body)
            
            // Update local cache
            await MainActor.run {
                if let index = workouts.firstIndex(where: { $0.id == session.id }) {
                    workouts[index] = session
                } else {
                    workouts.append(session)
                }
                workouts.sort { $0.startTime > $1.startTime }
            }
            
            print("✅ Saved workout to API: \(session.id)")
        } catch let error as APIError {
            await MainActor.run { lastError = error }
            print("❌ Error saving workout: \(error.localizedDescription)")
        } catch {
            print("❌ Error saving workout: \(error)")
        }
        
        await MainActor.run { isLoading = false }
    }
    
    /// Load all workouts from storage
    func loadWorkouts() {
        Task {
            await loadWorkoutsAsync()
        }
    }
    
    /// Load all workouts (async)
    func loadWorkoutsAsync() async {
        guard api.isAuthenticated else {
            print("⚠️ Not authenticated, cannot load workouts")
            return
        }
        
        await MainActor.run { isLoading = true }
        
        do {
            let response = try await api.get("/workouts")
            
            if let workoutsData = response["data"] as? [[String: Any]] ?? (response as? [[String: Any]]) {
                let loadedWorkouts = workoutsData.compactMap { parseWorkoutSession($0) }
                
                await MainActor.run {
                    workouts = loadedWorkouts
                }
                
                print("✅ Loaded \(loadedWorkouts.count) workouts from API")
            }
        } catch let error as APIError {
            await MainActor.run { lastError = error }
            print("❌ Error loading workouts: \(error.localizedDescription)")
        } catch {
            print("❌ Error loading workouts: \(error)")
        }
        
        await MainActor.run { isLoading = false }
    }
    
    private func parseWorkoutSession(_ dict: [String: Any]) -> WorkoutSession? {
        guard let idString = dict["id"] as? String,
              let startTimeString = dict["start_time"] as? String,
              let endTimeString = dict["end_time"] as? String,
              let startTime = ISO8601DateFormatter().date(from: startTimeString),
              let endTime = ISO8601DateFormatter().date(from: endTimeString) else {
            return nil
        }
        
        var session = WorkoutSession(startTime: startTime)
        session.endTime = endTime
        session.accumulatedActiveTime = dict["accumulated_active_time"] as? TimeInterval ?? 0
        session.workoutTitle = dict["workout_title"] as? String
        session.effortRating = dict["effort_rating"] as? Int
        session.notes = dict["notes"] as? String
        session.fatigueLevel = dict["fatigue_level"] as? Int
        session.injuryFlag = dict["injury_flag"] as? Bool
        session.injuryNotes = dict["injury_notes"] as? String
        
        if let plannedIdStr = dict["planned_workout_id"] as? String {
            session.plannedWorkoutId = UUID(uuidString: plannedIdStr)
        }
        
        return session
    }
    
    /// Load a specific workout by ID
    func loadWorkout(id: UUID) -> WorkoutSession? {
        return workouts.first { $0.id == id }
    }
    
    /// Load a specific workout by ID (async from API)
    func loadWorkoutAsync(id: UUID) async -> WorkoutSession? {
        guard api.isAuthenticated else { return nil }
        
        do {
            let response = try await api.get("/workouts/\(id.uuidString)")
            return parseWorkoutSession(response)
        } catch {
            print("❌ Error loading workout: \(error)")
            return nil
        }
    }
    
    /// Delete a workout
    func deleteWorkout(id: UUID) {
        Task {
            await deleteWorkoutAsync(id: id)
        }
    }
    
    func deleteWorkoutAsync(id: UUID) async {
        guard api.isAuthenticated else { return }
        
        do {
            _ = try await api.delete("/workouts/\(id.uuidString)")
            
            await MainActor.run {
                workouts.removeAll { $0.id == id }
            }
            
            print("✅ Deleted workout: \(id)")
        } catch {
            print("❌ Error deleting workout: \(error)")
        }
    }
    
    /// Update an existing workout
    func updateWorkout(_ session: WorkoutSession) {
        saveWorkout(session)
    }
    
    // MARK: - Goal Management
    
    /// Save a goal (creates or updates)
    func saveGoal(_ goal: Goal) throws {
        Task {
            try await saveGoalAsync(goal)
        }
    }
    
    func saveGoalAsync(_ goal: Goal) async throws {
        guard api.isAuthenticated else {
            throw APIError.notAuthenticated
        }
        
        var body: [String: Any] = [
            "id": goal.id.uuidString,
            "type": goal.type.rawValue,
            "eventDate": ISO8601DateFormatter().string(from: goal.eventDate),
            "isActive": goal.isActive
        ]
        
        if let targetTime = goal.targetTime {
            body["targetTimeSeconds"] = targetTime
        }
        if let title = goal.title {
            body["title"] = title
        }
        if let notes = goal.notes {
            body["notes"] = notes
        }
        if let raceDistance = goal.raceDistance {
            body["raceDistance"] = raceDistance.rawValue
        }
        if let customDistanceKm = goal.customDistanceKm {
            body["customDistanceKm"] = customDistanceKm
        }
        body["baselineStatus"] = goal.baselineStatus.rawValue
        
        if let assessmentId = goal.baselineAssessmentId {
            body["baselineAssessmentId"] = assessmentId.uuidString
        }
        if let vdot = goal.estimatedVDOT {
            body["estimatedVdot"] = vdot
        }
        
        if let paces = goal.trainingPaces {
            body["easyPaceMin"] = paces.easy.min
            body["easyPaceMax"] = paces.easy.max
            body["longRunPaceMin"] = paces.longRun.min
            body["longRunPaceMax"] = paces.longRun.max
            body["thresholdPace"] = paces.threshold
            body["intervalPace"] = paces.interval
            body["repetitionPace"] = paces.repetition
            if let racePace = paces.racePace {
                body["racePace"] = racePace
            }
        }
        
        _ = try await api.post("/goals", body: body)
        print("✅ Saved goal: \(goal.displayName)")
    }
    
    /// Load the ID of the currently active goal
    func loadActiveGoalId() -> UUID? {
        return nil  // Use async version
    }
    
    func loadActiveGoalIdAsync() async -> UUID? {
        guard api.isAuthenticated else { return nil }
        
        do {
            let response = try await api.get("/goals/active")
            if let idString = response["id"] as? String {
                return UUID(uuidString: idString)
            }
        } catch {
            // No active goal is not an error
        }
        
        return nil
    }
    
    /// Load a specific goal by ID
    func loadGoal(id: UUID) -> Goal? {
        return nil  // Use async version
    }
    
    func loadGoalAsync(id: UUID) async -> Goal? {
        guard api.isAuthenticated else { return nil }
        
        do {
            let response = try await api.get("/goals/\(id.uuidString)")
            return parseGoal(response)
        } catch {
            print("❌ Error loading goal: \(error)")
            return nil
        }
    }
    
    /// Load all goals
    func loadAllGoals() -> [Goal] {
        return []  // Use async version
    }
    
    func loadAllGoalsAsync() async -> [Goal] {
        guard api.isAuthenticated else { return [] }
        
        do {
            let response = try await api.get("/goals")
            if let goalsData = response["data"] as? [[String: Any]] ?? (try? JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: response)) as? [[String: Any]]) {
                return goalsData.compactMap { parseGoal($0) }
            }
        } catch {
            print("❌ Error loading goals: \(error)")
        }
        
        return []
    }
    
    private func parseGoal(_ dict: [String: Any]) -> Goal? {
        guard let idString = dict["id"] as? String,
              let id = UUID(uuidString: idString),
              let typeString = dict["type"] as? String,
              let type = Goal.GoalType(rawValue: typeString),
              let eventDateString = dict["event_date"] as? String,
              let eventDate = ISO8601DateFormatter().date(from: eventDateString) else {
            return nil
        }
        
        let createdAtString = dict["created_at"] as? String
        let createdAt = createdAtString.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
        
        var raceDistance: Goal.RaceDistance?
        if let distanceStr = dict["race_distance"] as? String {
            raceDistance = Goal.RaceDistance(rawValue: distanceStr)
        }
        
        var baselineStatus: Goal.BaselineStatus = .unknown
        if let statusStr = dict["baseline_status"] as? String,
           let status = Goal.BaselineStatus(rawValue: statusStr) {
            baselineStatus = status
        }
        
        var trainingPaces: TrainingPaces?
        if let easyMin = dict["easy_pace_min"] as? Double,
           let easyMax = dict["easy_pace_max"] as? Double,
           let longMin = dict["long_run_pace_min"] as? Double,
           let longMax = dict["long_run_pace_max"] as? Double,
           let threshold = dict["threshold_pace"] as? Double,
           let interval = dict["interval_pace"] as? Double,
           let repetition = dict["repetition_pace"] as? Double {
            trainingPaces = TrainingPaces(
                easy: PaceRange(min: easyMin, max: easyMax),
                longRun: PaceRange(min: longMin, max: longMax),
                threshold: threshold,
                interval: interval,
                repetition: repetition,
                racePace: dict["race_pace"] as? Double
            )
        }
        
        var baselineAssessmentId: UUID?
        if let assessmentIdStr = dict["baseline_assessment_id"] as? String {
            baselineAssessmentId = UUID(uuidString: assessmentIdStr)
        }
        
        return Goal(
            id: id,
            type: type,
            targetTime: dict["target_time_seconds"] as? TimeInterval,
            eventDate: eventDate,
            createdAt: createdAt,
            isActive: dict["is_active"] as? Bool ?? false,
            title: dict["title"] as? String,
            notes: dict["notes"] as? String,
            raceDistance: raceDistance,
            customDistanceKm: dict["custom_distance_km"] as? Double,
            baselineStatus: baselineStatus,
            baselineAssessmentId: baselineAssessmentId,
            trainingPaces: trainingPaces,
            estimatedVDOT: dict["estimated_vdot"] as? Double
        )
    }
    
    /// Set the active goal ID (or nil to clear)
    func setActiveGoal(id: UUID?) throws {
        Task {
            try await setActiveGoalAsync(id: id)
        }
    }
    
    func setActiveGoalAsync(id: UUID?) async throws {
        guard api.isAuthenticated else { throw APIError.notAuthenticated }
        
        if let id = id {
            _ = try await api.post("/goals/\(id.uuidString)/activate")
            print("✅ Set active goal: \(id)")
        } else {
            _ = try await api.post("/goals/deactivate")
            print("✅ Cleared active goal")
        }
    }
    
    /// Delete a goal by ID
    func deleteGoal(id: UUID) throws {
        Task {
            try await deleteGoalAsync(id: id)
        }
    }
    
    func deleteGoalAsync(id: UUID) async throws {
        guard api.isAuthenticated else { throw APIError.notAuthenticated }
        
        _ = try await api.delete("/goals/\(id.uuidString)")
        print("✅ Deleted goal: \(id)")
    }
    
    /// Validate goal storage integrity
    func validateGoalStorage() -> (isValid: Bool, details: String) {
        return (api.isAuthenticated, api.isAuthenticated ? "Connected to API" : "Not authenticated")
    }
    
    // MARK: - Baseline Assessment Management
    
    func saveBaselineAssessment(_ assessment: BaselineAssessment) throws {
        Task {
            try await saveBaselineAssessmentAsync(assessment)
        }
    }
    
    func saveBaselineAssessmentAsync(_ assessment: BaselineAssessment) async throws {
        guard api.isAuthenticated else { throw APIError.notAuthenticated }
        
        let body: [String: Any] = [
            "id": assessment.id.uuidString,
            "method": assessment.method.rawValue,
            "vdot": assessment.vdot,
            "testDistanceKm": assessment.testDistanceKm as Any,
            "testTimeSeconds": assessment.testTimeSeconds as Any,
            "easyPaceMin": assessment.trainingPaces.easy.min,
            "easyPaceMax": assessment.trainingPaces.easy.max,
            "longRunPaceMin": assessment.trainingPaces.longRun.min,
            "longRunPaceMax": assessment.trainingPaces.longRun.max,
            "thresholdPace": assessment.trainingPaces.threshold,
            "intervalPace": assessment.trainingPaces.interval,
            "repetitionPace": assessment.trainingPaces.repetition,
            "racePace": assessment.trainingPaces.racePace as Any
        ]
        
        _ = try await api.post("/plans/assessments", body: body)
        print("✅ Saved baseline assessment: VDOT \(assessment.vdot)")
    }
    
    func loadAllBaselineAssessments() -> [BaselineAssessment] {
        return []  // Use async version
    }
    
    func loadLatestBaselineAssessment() -> BaselineAssessment? {
        return nil  // Use async version
    }
    
    func loadLatestBaselineAssessmentAsync() async -> BaselineAssessment? {
        guard api.isAuthenticated else { return nil }
        
        do {
            let response = try await api.get("/plans/assessments")
            if let assessments = response["data"] as? [[String: Any]],
               let first = assessments.first {
                return parseBaselineAssessment(first)
            }
        } catch {
            print("❌ Error loading assessment: \(error)")
        }
        
        return nil
    }
    
    func loadBaselineAssessment(id: UUID) -> BaselineAssessment? {
        return nil
    }
    
    private func parseBaselineAssessment(_ dict: [String: Any]) -> BaselineAssessment? {
        guard let idString = dict["id"] as? String,
              let id = UUID(uuidString: idString),
              let methodString = dict["method"] as? String,
              let method = BaselineAssessment.AssessmentMethod(rawValue: methodString),
              let vdot = dict["vdot"] as? Double,
              let easyMin = dict["easy_pace_min"] as? Double,
              let easyMax = dict["easy_pace_max"] as? Double,
              let longMin = dict["long_run_pace_min"] as? Double,
              let longMax = dict["long_run_pace_max"] as? Double,
              let threshold = dict["threshold_pace"] as? Double,
              let interval = dict["interval_pace"] as? Double,
              let repetition = dict["repetition_pace"] as? Double else {
            return nil
        }
        
        let assessmentDateString = dict["assessment_date"] as? String
        let assessmentDate = assessmentDateString.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
        
        let trainingPaces = TrainingPaces(
            easy: PaceRange(min: easyMin, max: easyMax),
            longRun: PaceRange(min: longMin, max: longMax),
            threshold: threshold,
            interval: interval,
            repetition: repetition,
            racePace: dict["race_pace"] as? Double
        )
        
        return BaselineAssessment(
            id: id,
            assessmentDate: assessmentDate,
            method: method,
            vdot: vdot,
            trainingPaces: trainingPaces,
            testDistanceKm: dict["test_distance_km"] as? Double,
            testTimeSeconds: dict["test_time_seconds"] as? Double
        )
    }
    
    func deleteBaselineAssessment(id: UUID) throws {
        // Not implemented in API yet
    }
    
    // MARK: - Pace Feedback Management
    
    func savePaceFeedback(assessmentId: UUID, feedback: PaceFeedback) throws {
        // Not implemented in API yet
    }
    
    func loadPaceFeedback(assessmentId: UUID) -> PaceFeedback? {
        return nil
    }
    
    // MARK: - Training Plan Management
    
    func saveTrainingPlan(_ plan: TrainingPlan) throws {
        Task {
            try await saveTrainingPlanAsync(plan)
        }
    }
    
    func saveTrainingPlanAsync(_ plan: TrainingPlan) async throws {
        guard api.isAuthenticated else { throw APIError.notAuthenticated }
        
        // Convert plan to JSON-compatible format
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        var body: [String: Any] = [
            "id": plan.id.uuidString,
            "goalId": plan.goalId.uuidString,
            "startDate": ISO8601DateFormatter().string(from: plan.startDate),
            "eventDate": ISO8601DateFormatter().string(from: plan.eventDate),
            "generationMethod": plan.generationMethod.rawValue,
            "totalWeeks": plan.totalWeeks,
            "weeklyRunDays": plan.weeklyRunDays,
            "weeklyGymDays": plan.weeklyGymDays
        ]
        
        // Encode complex objects as JSON
        if let phasesData = try? encoder.encode(plan.phases),
           let phases = try? JSONSerialization.jsonObject(with: phasesData) {
            body["phasesJson"] = phases
        }
        
        if let availData = try? encoder.encode(plan.availability),
           let avail = try? JSONSerialization.jsonObject(with: availData) {
            body["availabilityJson"] = avail
        }
        
        // Convert weeks
        var weeksArray: [[String: Any]] = []
        for week in plan.weeks {
            var weekDict: [String: Any] = [
                "id": week.id.uuidString,
                "weekNumber": week.weekNumber,
                "startDate": ISO8601DateFormatter().string(from: week.startDate),
                "endDate": ISO8601DateFormatter().string(from: week.endDate),
                "targetWeeklyKm": week.targetWeeklyKm
            ]
            
            if let phaseData = try? encoder.encode(week.phase),
               let phase = try? JSONSerialization.jsonObject(with: phaseData) {
                weekDict["phase"] = phase
            }
            
            // Convert workouts
            var workoutsArray: [[String: Any]] = []
            for workout in week.workouts {
                var workoutDict: [String: Any] = [
                    "id": workout.id.uuidString,
                    "date": ISO8601DateFormatter().string(from: workout.date),
                    "type": workout.type.rawValue,
                    "title": workout.title,
                    "completed": workout.completed
                ]
                
                if let desc = workout.description {
                    workoutDict["description"] = desc
                }
                if let dist = workout.targetDistanceKm {
                    workoutDict["targetDistanceKm"] = dist
                }
                if let dur = workout.targetDurationSeconds {
                    workoutDict["targetDurationSeconds"] = dur
                }
                if let pace = workout.targetPaceSecondsPerKm {
                    workoutDict["targetPaceSecondsPerKm"] = pace
                }
                
                workoutsArray.append(workoutDict)
            }
            weekDict["workouts"] = workoutsArray
            
            weeksArray.append(weekDict)
        }
        body["weeks"] = weeksArray
        
        _ = try await api.post("/plans", body: body)
        print("✅ Saved training plan: \(plan.totalWeeks) weeks")
    }
    
    func loadTrainingPlan() -> TrainingPlan? {
        return nil  // Use async version
    }
    
    func loadTrainingPlanAsync() async -> TrainingPlan? {
        guard api.isAuthenticated else { return nil }
        
        do {
            let response = try await api.get("/plans/current")
            // Plan parsing would go here - complex nested structure
            // For now, return nil and implement full parsing later
            return nil
        } catch {
            // No plan found is not an error
            return nil
        }
    }
    
    func deleteTrainingPlan() throws {
        Task {
            try await deleteTrainingPlanAsync()
        }
    }
    
    func deleteTrainingPlanAsync() async throws {
        guard api.isAuthenticated else { throw APIError.notAuthenticated }
        
        _ = try await api.delete("/plans/current")
        print("✅ Deleted training plan")
    }
    
    // MARK: - Training Preferences Management
    
    func saveTrainingPreferences(_ preferences: TrainingPreferences) throws {
        Task {
            try await saveTrainingPreferencesAsync(preferences)
        }
    }
    
    func saveTrainingPreferencesAsync(_ preferences: TrainingPreferences) async throws {
        guard api.isAuthenticated else { throw APIError.notAuthenticated }
        
        let body: [String: Any] = [
            "weeklyRunDays": preferences.weeklyRunDays,
            "weeklyGymDays": preferences.weeklyGymDays,
            "preferredRestDays": preferences.preferredRestDays,
            "preferredLongRunDay": preferences.preferredLongRunDay,
            "maxWeeklyKm": preferences.maxWeeklyKm as Any,
            "includeCrossTraining": preferences.includeCrossTraining,
            "availableDays": preferences.availability?.availableDays.sorted() ?? [],
            "restDays": preferences.availability?.restDays.sorted() ?? [],
            "allowDoubleDays": preferences.availability?.allowDoubleDays ?? false
        ]
        
        _ = try await api.put("/profile/preferences", body: body)
        print("✅ Saved training preferences")
    }
    
    func loadTrainingPreferences() -> TrainingPreferences {
        return .default  // Use async version
    }
    
    func loadTrainingPreferencesAsync() async -> TrainingPreferences {
        guard api.isAuthenticated else { return .default }
        
        do {
            let response = try await api.get("/profile/preferences")
            
            let availability = TrainingAvailability(
                availableDays: Set((response["available_days"] as? [Int]) ?? []),
                restDays: Set((response["rest_days"] as? [Int]) ?? []),
                preferredLongRunDay: response["preferred_long_run_day"] as? Int,
                allowDoubleDays: response["allow_double_days"] as? Bool ?? false
            )
            
            return TrainingPreferences(
                weeklyRunDays: response["weekly_run_days"] as? Int ?? 4,
                weeklyGymDays: response["weekly_gym_days"] as? Int ?? 2,
                preferredRestDays: response["preferred_rest_days"] as? [Int] ?? [1],
                preferredLongRunDay: response["preferred_long_run_day"] as? Int ?? 0,
                maxWeeklyKm: response["max_weekly_km"] as? Double,
                includeCrossTraining: response["include_cross_training"] as? Bool ?? false,
                availability: availability
            )
        } catch {
            print("❌ Error loading preferences: \(error)")
            return .default
        }
    }
    
    // MARK: - Weekly Adaptation Management
    
    func saveAdaptationRecord(_ record: AdaptationRecord) throws {
        // Adaptation records via API - implement if needed
    }
    
    func loadAdaptationHistory() -> [AdaptationRecord] {
        return []
    }
    
    func loadLatestAdaptation() -> AdaptationRecord? {
        return nil
    }
    
    func updateAdaptationRecord(_ record: AdaptationRecord) throws {
        try saveAdaptationRecord(record)
    }
    
    // MARK: - User Training Profile Management
    
    func saveUserProfile(_ profile: UserTrainingProfile) throws {
        Task {
            try await saveUserProfileAsync(profile)
        }
    }
    
    func saveUserProfileAsync(_ profile: UserTrainingProfile) async throws {
        guard api.isAuthenticated else { throw APIError.notAuthenticated }
        
        let body: [String: Any] = [
            "availableEquipment": profile.availableEquipment.map { $0.rawValue }
        ]
        
        _ = try await api.put("/profile", body: body)
        print("✅ Saved user profile")
    }
    
    func loadUserProfile() -> UserTrainingProfile {
        return .default  // Use async version
    }
    
    func loadUserProfileAsync() async -> UserTrainingProfile {
        guard api.isAuthenticated else { return .default }
        
        do {
            let response = try await api.get("/profile")
            
            if let equipmentArray = response["available_equipment"] as? [String] {
                let equipment = Set(equipmentArray.compactMap { GymEquipment(rawValue: $0) })
                return UserTrainingProfile(availableEquipment: equipment)
            }
        } catch {
            print("❌ Error loading profile: \(error)")
        }
        
        return .default
    }
    
    // MARK: - Workout Feedback Management
    
    func saveWorkoutFeedback(_ feedback: WorkoutFeedback) throws {
        Task {
            try await saveWorkoutFeedbackAsync(feedback)
        }
    }
    
    func saveWorkoutFeedbackAsync(_ feedback: WorkoutFeedback) async throws {
        guard api.isAuthenticated else { throw APIError.notAuthenticated }
        
        let body: [String: Any] = [
            "id": feedback.id.uuidString,
            "plannedWorkoutId": feedback.plannedWorkoutId?.uuidString as Any,
            "completionStatus": feedback.completionStatus.rawValue,
            "paceAdherence": feedback.paceAdherence?.rawValue as Any,
            "perceivedEffort": feedback.perceivedEffort,
            "fatigueLevel": feedback.fatigueLevel,
            "painLevel": feedback.painLevel,
            "painAreas": feedback.painAreas?.map { $0.rawValue } as Any,
            "weightFeel": feedback.weightFeel?.rawValue as Any,
            "formBreakdown": feedback.formBreakdown as Any,
            "notes": feedback.notes as Any
        ]
        
        _ = try await api.post("/workouts/\(feedback.workoutSessionId.uuidString)/feedback", body: body)
        print("✅ Saved workout feedback")
    }
    
    func loadWorkoutFeedback(sessionId: UUID) -> WorkoutFeedback? {
        return nil
    }
    
    func loadAllWorkoutFeedback() -> [WorkoutFeedback] {
        return []
    }
    
    func deleteWorkoutFeedback(sessionId: UUID) throws {
        // Not implemented
    }
}
