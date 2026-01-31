import Foundation

/// Smart exercise selection engine with equipment filtering and muscle balance
class ExerciseSelector {
    private let library = ExerciseLibrary.shared
    
    // MARK: - Main Selection Method
    
    /// Select exercises for a specific phase and goal
    func selectExercises(
        for phase: TrainingPhase,
        goalType: ExerciseGoalType,
        availableEquipment: Set<GymEquipment>,
        recentExercises: [String] = []
    ) -> [ExerciseAssignment] {
        
        let phaseName = phase.name
        var assignments: [ExerciseAssignment] = []
        var order = 1
        
        // Get phase-specific exercise distribution
        let distribution = getExerciseDistribution(for: phaseName, goalType: goalType)
        
        // Track muscle groups to ensure balance
        var usedMuscleGroups: [MuscleGroup] = []
        
        // Select exercises for each category with fallback logic
        for (category, count) in distribution {
            let selected = selectExercisesWithFallback(
                for: category,
                count: count,
                goalType: goalType,
                availableEquipment: availableEquipment,
                recentExercises: recentExercises,
                usedMuscleGroups: &usedMuscleGroups
            )
            
            // Create assignments
            for exercise in selected {
                let assignment = createAssignment(
                    for: exercise,
                    order: order,
                    phase: phaseName
                )
                assignments.append(assignment)
                order += 1
                
                // Track muscle groups
                usedMuscleGroups.append(contentsOf: exercise.primaryMuscles)
            }
        }
        
        return assignments
    }
    
    // MARK: - Phase Distribution
    
    private func getExerciseDistribution(for phaseName: String, goalType: ExerciseGoalType) -> [(ExerciseCategory, Int)] {
        switch phaseName {
        case "Base Building":
            // Focus on foundational strength + mobility
            return [
                (.strength, 4),
                (.mobility, 2),
                (.prehab, 2)
            ]
            
        case "Build Up":
            // Add intensity + plyometrics
            if goalType == .fiveK || goalType == .tenK {
                return [
                    (.strength, 3),
                    (.plyometrics, 2),
                    (.stability, 1),
                    (.prehab, 1)
                ]
            } else {
                return [
                    (.strength, 4),
                    (.plyometrics, 1),
                    (.stability, 1),
                    (.prehab, 1)
                ]
            }
            
        case "Peak Training":
            // Maintain + sharpen
            if goalType == .fiveK || goalType == .tenK {
                return [
                    (.strength, 2),
                    (.plyometrics, 2),
                    (.prehab, 2)
                ]
            } else {
                return [
                    (.strength, 3),
                    (.plyometrics, 1),
                    (.prehab, 2)
                ]
            }
            
        case "Taper":
            // Light maintenance only
            return [
                (.strength, 2),
                (.mobility, 2)
            ]
            
        default:
            // Fallback: balanced approach
            return [
                (.strength, 3),
                (.stability, 1),
                (.mobility, 1),
                (.prehab, 1)
            ]
        }
    }
    
    // MARK: - Fallback Selection
    
    /// Select exercises with tiered fallback strategy to ensure we always get exercises
    private func selectExercisesWithFallback(
        for category: ExerciseCategory,
        count: Int,
        goalType: ExerciseGoalType,
        availableEquipment: Set<GymEquipment>,
        recentExercises: [String],
        usedMuscleGroups: inout [MuscleGroup]
    ) -> [Exercise] {
        
        // Attempt 1: Full filters (equipment + goal + rotation)
        var candidates = library.filterByCategory(category)
            .filter { Set($0.requiredEquipment).isSubset(of: availableEquipment) }
            .filter { $0.supportsGoals.contains(goalType) || $0.supportsGoals.contains(.general) }
            .filter { !recentExercises.contains($0.slug) }
        
        var selected = selectBalancedExercises(
            from: candidates,
            count: count,
            usedMuscleGroups: &usedMuscleGroups
        )
        
        if selected.count >= count {
            return selected
        }
        
        // Attempt 2: Relax recent exercise filter
        print("⚠️ Insufficient exercises for \(category) with rotation filter, relaxing...")
        candidates = library.filterByCategory(category)
            .filter { Set($0.requiredEquipment).isSubset(of: availableEquipment) }
            .filter { $0.supportsGoals.contains(goalType) || $0.supportsGoals.contains(.general) }
        
        selected = selectBalancedExercises(
            from: candidates,
            count: count,
            usedMuscleGroups: &usedMuscleGroups
        )
        
        if selected.count >= count {
            return selected
        }
        
        // Attempt 3: Relax goal-type filter (use all exercises for category)
        print("⚠️ Insufficient exercises for \(category) with goal filter, using all exercises...")
        candidates = library.filterByCategory(category)
            .filter { Set($0.requiredEquipment).isSubset(of: availableEquipment) }
        
        selected = selectBalancedExercises(
            from: candidates,
            count: count,
            usedMuscleGroups: &usedMuscleGroups
        )
        
        if selected.count >= count {
            return selected
        }
        
        // Attempt 4: Add bodyweight exercises as last resort
        print("⚠️ Insufficient exercises for \(category), adding bodyweight fallback...")
        var expandedEquipment = availableEquipment
        expandedEquipment.insert(.none)
        
        candidates = library.filterByCategory(category)
            .filter { Set($0.requiredEquipment).isSubset(of: expandedEquipment) }
        
        selected = selectBalancedExercises(
            from: candidates,
            count: count,
            usedMuscleGroups: &usedMuscleGroups
        )
        
        if selected.count > 0 {
            print("✅ Found \(selected.count) exercises for \(category) with bodyweight fallback")
        } else {
            print("❌ Could not find any exercises for \(category) - this should not happen!")
        }
        
        return selected
    }
    
    // MARK: - Balanced Selection
    
    private func selectBalancedExercises(
        from candidates: [Exercise],
        count: Int,
        usedMuscleGroups: inout [MuscleGroup]
    ) -> [Exercise] {
        guard count > 0 && !candidates.isEmpty else { return [] }
        
        var selected: [Exercise] = []
        var remaining = candidates
        
        for _ in 0..<count {
            if remaining.isEmpty { break }
            
            // Score each candidate based on muscle group balance
            let scored = remaining.map { exercise -> (Exercise, Int) in
                let muscleCount = usedMuscleGroups.filter { exercise.primaryMuscles.contains($0) }.count
                // Prefer exercises that work less-used muscle groups (lower score is better)
                return (exercise, muscleCount)
            }
            
            // Sort by score (ascending) and take the best
            let sortedByBalance = scored.sorted { $0.1 < $1.1 }
            
            if let best = sortedByBalance.first {
                selected.append(best.0)
                usedMuscleGroups.append(contentsOf: best.0.primaryMuscles)
                remaining.removeAll { $0.slug == best.0.slug }
            }
        }
        
        // If we didn't get enough, allow repeating muscle groups
        while selected.count < count && !remaining.isEmpty {
            if let next = remaining.first {
                selected.append(next)
                remaining.removeFirst()
            }
        }
        
        return selected
    }
    
    // MARK: - Assignment Creation
    
    private func createAssignment(for exercise: Exercise, order: Int, phase: String) -> ExerciseAssignment {
        // Adjust sets/reps based on phase
        var sets = exercise.defaultSets
        var reps = exercise.defaultReps
        var rpeTarget: Double? = nil
        
        switch phase {
        case "Base Building":
            // Higher reps, lower intensity
            if let defaultReps = reps {
                reps = (defaultReps.lowerBound + 2)...(defaultReps.upperBound + 3)
            }
            rpeTarget = 6.5
            
        case "Build Up":
            // Standard volume
            rpeTarget = 7.5
            
        case "Peak Training":
            // Maintain strength
            if let defaultReps = reps {
                reps = (defaultReps.lowerBound - 1)...(defaultReps.upperBound - 2)
            }
            rpeTarget = 7.0
            
        case "Taper":
            // Reduced volume
            sets = max(2, sets - 1)
            rpeTarget = 6.0
            
        default:
            rpeTarget = 7.0
        }
        
        return ExerciseAssignment(
            exerciseSlug: exercise.slug,
            order: order,
            sets: sets,
            reps: reps,
            durationSeconds: exercise.defaultDurationSeconds,
            restSeconds: exercise.defaultRestSeconds,
            loadType: exercise.loadType,
            rpeTarget: rpeTarget
        )
    }
    
    // MARK: - Find Alternative
    
    /// Find the best alternative for an exercise based on equipment and pattern
    func findBestAlternative(
        for exerciseSlug: String,
        availableEquipment: Set<GymEquipment>
    ) -> Exercise? {
        guard let exercise = library.getExercise(slug: exerciseSlug) else { return nil }
        
        // First try curated alternatives
        let curatedAlternatives = library.findAlternatives(for: exerciseSlug)
            .filter { Set($0.requiredEquipment).isSubset(of: availableEquipment) }
        
        if let best = curatedAlternatives.first {
            return best
        }
        
        // Fallback to movement pattern matching
        let patternAlternatives = library.findAlternativesByPattern(
            exercise.movementPattern,
            equipment: availableEquipment,
            excluding: [exerciseSlug]
        )
        
        // Prefer alternatives that work similar muscles
        let scoredAlternatives = patternAlternatives.map { candidate -> (Exercise, Int) in
            let muscleOverlap = Set(exercise.primaryMuscles).intersection(Set(candidate.primaryMuscles)).count
            return (candidate, muscleOverlap)
        }
        
        // Return the one with most muscle overlap
        return scoredAlternatives.max(by: { $0.1 < $1.1 })?.0
    }
}
