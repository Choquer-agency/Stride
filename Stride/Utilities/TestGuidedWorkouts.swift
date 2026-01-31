import Foundation

/// Test data generator for guided workouts
extension TestDataGenerator {
    /// Generate a test planned workout with intervals for guided workout testing
    static func generateTestGuidedWorkout() -> PlannedWorkout {
        let intervals = [
            PlannedWorkout.Interval(
                order: 1,
                type: .warmup,
                distanceKm: 1.0,
                targetPaceSecondsPerKm: 360,  // 6:00/km
                description: "Easy warmup - build into your run"
            ),
            PlannedWorkout.Interval(
                order: 2,
                type: .work,
                distanceKm: 0.8,
                targetPaceSecondsPerKm: 280,  // 4:40/km
                description: "800m repeat #1 - steady effort"
            ),
            PlannedWorkout.Interval(
                order: 3,
                type: .recovery,
                distanceKm: 0.4,
                targetPaceSecondsPerKm: 400,  // 6:40/km
                description: "400m recovery jog"
            ),
            PlannedWorkout.Interval(
                order: 4,
                type: .work,
                distanceKm: 0.8,
                targetPaceSecondsPerKm: 280,  // 4:40/km
                description: "800m repeat #2 - maintain pace"
            ),
            PlannedWorkout.Interval(
                order: 5,
                type: .recovery,
                distanceKm: 0.4,
                targetPaceSecondsPerKm: 400,  // 6:40/km
                description: "400m recovery jog"
            ),
            PlannedWorkout.Interval(
                order: 6,
                type: .work,
                distanceKm: 0.8,
                targetPaceSecondsPerKm: 280,  // 4:40/km
                description: "800m repeat #3 - push through fatigue"
            ),
            PlannedWorkout.Interval(
                order: 7,
                type: .cooldown,
                distanceKm: 1.0,
                targetPaceSecondsPerKm: 360,  // 6:00/km
                description: "Easy cooldown - slow it down"
            )
        ]
        
        return PlannedWorkout(
            date: Date(),
            type: .intervalWorkout,
            title: "Test Interval Workout",
            description: "3x800m with recovery - test guided workout features",
            targetDistanceKm: 5.2,
            targetPaceSecondsPerKm: 320,
            intervals: intervals
        )
    }
    
    /// Generate a simple test workout without intervals
    static func generateTestSimpleWorkout() -> PlannedWorkout {
        return PlannedWorkout(
            date: Date(),
            type: .easyRun,
            title: "Test Easy Run",
            description: "Simple 5K easy run without intervals",
            targetDistanceKm: 5.0,
            targetPaceSecondsPerKm: 360  // 6:00/km
        )
    }
    
    /// Generate a rest day workout
    static func generateTestRestDay() -> PlannedWorkout {
        return PlannedWorkout(
            date: Date(),
            type: .rest,
            title: "Rest Day",
            description: "Recovery day - let your body adapt"
        )
    }
}
