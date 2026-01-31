import Foundation

/// Generates warmup and cooldown movement blocks for workouts
class MovementBlockGenerator {
    private let library = ExerciseLibrary.shared
    
    // MARK: - Warmup Generation
    
    /// Generate warmup block based on workout type
    func generateWarmup(for workoutType: PlannedWorkout.WorkoutType) -> MovementBlock? {
        let items: [MovementBlockItem]
        let context: String
        
        switch workoutType {
        case .intervalWorkout, .tempoRun:
            // Dynamic mobility for high-intensity workouts
            items = [
                MovementBlockItem(exerciseSlug: "leg_swings_forward", reps: 10),
                MovementBlockItem(exerciseSlug: "leg_swings_lateral", reps: 10),
                MovementBlockItem(exerciseSlug: "hip_circles", reps: 10),
                MovementBlockItem(exerciseSlug: "ankle_mobility_drill", reps: 10)
            ]
            context = "Pre-workout activation - Prepare for high intensity"
            
        case .longRun:
            // Gentle activation for long runs
            items = [
                MovementBlockItem(exerciseSlug: "glute_bridge", reps: 12),
                MovementBlockItem(exerciseSlug: "leg_swings_forward", reps: 8),
                MovementBlockItem(exerciseSlug: "calf_stretch", durationSeconds: 20)
            ]
            context = "Pre-run activation - Wake up key muscles"
            
        case .easyRun, .recoveryRun:
            // Minimal warmup
            items = [
                MovementBlockItem(exerciseSlug: "leg_swings_forward", reps: 8),
                MovementBlockItem(exerciseSlug: "ankle_mobility_drill", reps: 8)
            ]
            context = "Light activation - Easy effort"
            
        case .raceSimulation:
            // Race-specific warmup
            items = [
                MovementBlockItem(exerciseSlug: "leg_swings_forward", reps: 12),
                MovementBlockItem(exerciseSlug: "hip_circles", reps: 10),
                MovementBlockItem(exerciseSlug: "skipping", reps: 20),
                MovementBlockItem(exerciseSlug: "ankle_mobility_drill", reps: 10)
            ]
            context = "Pre-race warmup - Get ready to perform"
            
        case .gym:
            // Gym-specific warmup
            items = [
                MovementBlockItem(exerciseSlug: "hip_circles", reps: 10),
                MovementBlockItem(exerciseSlug: "bodyweight_squat", reps: 12),
                MovementBlockItem(exerciseSlug: "glute_bridge", reps: 12),
                MovementBlockItem(exerciseSlug: "plank", durationSeconds: 30)
            ]
            context = "Pre-strength warmup - Activate major muscle groups"
            
        case .rest, .crossTraining:
            // No structured warmup needed
            return nil
        }
        
        return MovementBlock(items: items, context: context)
    }
    
    // MARK: - Cooldown Generation
    
    /// Generate cooldown block based on workout type
    func generateCooldown(for workoutType: PlannedWorkout.WorkoutType) -> MovementBlock? {
        let items: [MovementBlockItem]
        let context: String
        
        switch workoutType {
        case .intervalWorkout, .tempoRun, .raceSimulation:
            // Extended cooldown for high-intensity workouts
            items = [
                MovementBlockItem(exerciseSlug: "calf_stretch", durationSeconds: 30),
                MovementBlockItem(exerciseSlug: "hip_flexor_stretch", durationSeconds: 30),
                MovementBlockItem(exerciseSlug: "world_greatest_stretch", reps: 5),
                MovementBlockItem(exerciseSlug: "glute_bridge", reps: 10)
            ]
            context = "Post-workout recovery - Let your body cool down"
            
        case .longRun:
            // Focus on major muscle groups after long run
            items = [
                MovementBlockItem(exerciseSlug: "calf_stretch", durationSeconds: 30),
                MovementBlockItem(exerciseSlug: "hip_flexor_stretch", durationSeconds: 30),
                MovementBlockItem(exerciseSlug: "walking_leg_cradle", reps: 8),
                MovementBlockItem(exerciseSlug: "thoracic_rotation", reps: 8)
            ]
            context = "Post-long run recovery - Release tightness"
            
        case .easyRun, .recoveryRun:
            // Light stretching
            items = [
                MovementBlockItem(exerciseSlug: "calf_stretch", durationSeconds: 20),
                MovementBlockItem(exerciseSlug: "hip_flexor_stretch", durationSeconds: 20)
            ]
            context = "Light cooldown - Stay loose"
            
        case .gym:
            // Post-strength mobility
            items = [
                MovementBlockItem(exerciseSlug: "world_greatest_stretch", reps: 5),
                MovementBlockItem(exerciseSlug: "thoracic_rotation", reps: 10),
                MovementBlockItem(exerciseSlug: "hip_flexor_stretch", durationSeconds: 30),
                MovementBlockItem(exerciseSlug: "calf_stretch", durationSeconds: 30)
            ]
            context = "Post-strength mobility - Maintain range of motion"
            
        case .rest, .crossTraining:
            // No structured cooldown needed
            return nil
        }
        
        return MovementBlock(items: items, context: context)
    }
    
    // MARK: - Helper to add warmup/cooldown to workout
    
    /// Add warmup and cooldown blocks to a workout
    func addMovementBlocks(to workout: PlannedWorkout) -> PlannedWorkout {
        let warmup = generateWarmup(for: workout.type)
        let cooldown = generateCooldown(for: workout.type)
        
        // Return updated workout with movement blocks
        return PlannedWorkout(
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
            exerciseProgram: workout.exerciseProgram,
            warmupBlock: warmup,
            cooldownBlock: cooldown
        )
    }
}

// MARK: - Helper Exercise (bodyweight squat not in library)

extension MovementBlockGenerator {
    /// Get bodyweight squat as a warmup exercise (not in main library)
    private func createBodyweightSquat() -> MovementBlockItem {
        return MovementBlockItem(
            exerciseSlug: "bodyweight_squat",
            reps: 12
        )
    }
}
