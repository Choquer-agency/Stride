import XCTest
@testable import Stride

/// Tests for gym workout generation with fallback logic
final class GymWorkoutGenerationTests: XCTestCase {
    
    var generator: TrainingPlanGenerator!
    var selector: ExerciseSelector!
    
    override func setUp() {
        super.setUp()
        generator = TrainingPlanGenerator()
        selector = ExerciseSelector()
    }
    
    override func tearDown() {
        generator = nil
        selector = nil
        super.tearDown()
    }
    
    // MARK: - Empty Equipment Tests
    
    func testEmptyEquipment_GeneratesBodyweightExercises() {
        // Given: Empty equipment set
        let emptyEquipment: Set<GymEquipment> = []
        let phase = TrainingPhase(
            name: "Base Building",
            startDate: Date(),
            endDate: Date().addingTimeInterval(4 * 7 * 24 * 60 * 60),
            weeklyMileageKm: 30
        )
        
        // When: Selecting exercises
        let exercises = selector.selectExercises(
            for: phase,
            goalType: .general,
            availableEquipment: emptyEquipment,
            recentExercises: []
        )
        
        // Then: Should have exercises (from fallback)
        XCTAssertFalse(exercises.isEmpty, "Should generate exercises even with empty equipment")
        XCTAssertGreaterThanOrEqual(exercises.count, 4, "Should have at least 4 exercises")
        
        // Verify all exercises can work with bodyweight
        let library = ExerciseLibrary.shared
        for assignment in exercises {
            if let exercise = library.getExercise(slug: assignment.exerciseSlug) {
                XCTAssertTrue(
                    exercise.requiredEquipment.contains(.none) || exercise.requiredEquipment.isEmpty,
                    "Exercise \(exercise.name) should be bodyweight-compatible"
                )
            }
        }
    }
    
    func testBodyweightOnlyEquipment_GeneratesExercises() {
        // Given: Only bodyweight equipment
        let bodyweightOnly: Set<GymEquipment> = [.none]
        let phase = TrainingPhase(
            name: "Build Up",
            startDate: Date(),
            endDate: Date().addingTimeInterval(4 * 7 * 24 * 60 * 60),
            weeklyMileageKm: 40
        )
        
        // When: Selecting exercises
        let exercises = selector.selectExercises(
            for: phase,
            goalType: .tenK,
            availableEquipment: bodyweightOnly,
            recentExercises: []
        )
        
        // Then: Should have minimum exercises
        XCTAssertGreaterThanOrEqual(exercises.count, 5, "Build Up phase should have at least 5 exercises")
    }
    
    // MARK: - Limited Equipment Tests
    
    func testLimitedEquipment_GeneratesAdequateProgram() {
        // Given: Limited equipment (dumbbells only)
        let limitedEquipment: Set<GymEquipment> = [.none, .dumbbells]
        let phase = TrainingPhase(
            name: "Peak Training",
            startDate: Date(),
            endDate: Date().addingTimeInterval(2 * 7 * 24 * 60 * 60),
            weeklyMileageKm: 50
        )
        
        // When: Selecting exercises
        let exercises = selector.selectExercises(
            for: phase,
            goalType: .halfMarathon,
            availableEquipment: limitedEquipment,
            recentExercises: []
        )
        
        // Then: Should have minimum exercises for Peak phase
        XCTAssertGreaterThanOrEqual(exercises.count, 4, "Peak Training should have at least 4 exercises")
    }
    
    // MARK: - Exercise Rotation Tests
    
    func testExerciseRotation_WithLargeRecentList() {
        // Given: Large recent exercise list
        let equipment: Set<GymEquipment> = [.none, .dumbbells, .resistanceBands]
        let phase = TrainingPhase(
            name: "Base Building",
            startDate: Date(),
            endDate: Date().addingTimeInterval(4 * 7 * 24 * 60 * 60),
            weeklyMileageKm: 30
        )
        
        // Simulate many recent exercises
        let recentExercises = [
            "bulgarian_split_squat", "goblet_squat", "single_leg_rdl",
            "hip_thrust", "glute_bridge", "plank", "side_plank",
            "dead_bug", "lateral_band_walk", "clamshell",
            "leg_swings_forward", "world_greatest_stretch"
        ]
        
        // When: Selecting exercises
        let exercises = selector.selectExercises(
            for: phase,
            goalType: .marathon,
            availableEquipment: equipment,
            recentExercises: recentExercises
        )
        
        // Then: Should still generate exercises (using fallback)
        XCTAssertFalse(exercises.isEmpty, "Should generate exercises despite rotation filter")
        XCTAssertGreaterThanOrEqual(exercises.count, 6, "Base Building should have at least 6 exercises")
    }
    
    // MARK: - All Phases Tests
    
    func testAllPhases_GenerateMinimumExercises() {
        let phases = [
            ("Base Building", 6),
            ("Build Up", 5),
            ("Peak Training", 4),
            ("Taper", 3)
        ]
        
        let equipment: Set<GymEquipment> = [.none, .dumbbells, .resistanceBands]
        
        for (phaseName, minCount) in phases {
            // Given: A specific phase
            let phase = TrainingPhase(
                name: phaseName,
                startDate: Date(),
                endDate: Date().addingTimeInterval(4 * 7 * 24 * 60 * 60),
                weeklyMileageKm: 40
            )
            
            // When: Selecting exercises
            let exercises = selector.selectExercises(
                for: phase,
                goalType: .halfMarathon,
                availableEquipment: equipment,
                recentExercises: []
            )
            
            // Then: Should meet minimum count
            XCTAssertGreaterThanOrEqual(
                exercises.count,
                minCount,
                "\(phaseName) should have at least \(minCount) exercises, got \(exercises.count)"
            )
        }
    }
    
    func testTaperPhase_GeneratesLighterWorkload() {
        // Given: Taper phase
        let equipment: Set<GymEquipment> = [.none, .dumbbells]
        let phase = TrainingPhase(
            name: "Taper",
            startDate: Date(),
            endDate: Date().addingTimeInterval(2 * 7 * 24 * 60 * 60),
            weeklyMileageKm: 20
        )
        
        // When: Selecting exercises
        let exercises = selector.selectExercises(
            for: phase,
            goalType: .marathon,
            availableEquipment: equipment,
            recentExercises: []
        )
        
        // Then: Should have exercises but fewer than base phase
        XCTAssertGreaterThanOrEqual(exercises.count, 3, "Taper should have at least 3 exercises")
        XCTAssertLessThanOrEqual(exercises.count, 5, "Taper should be lighter workload")
    }
    
    // MARK: - Goal-Specific Tests
    
    func testDifferentGoals_GenerateAppropriateExercises() {
        let goals: [ExerciseGoalType] = [.fiveK, .tenK, .halfMarathon, .marathon]
        let equipment: Set<GymEquipment> = [.none, .dumbbells, .resistanceBands, .bench]
        let phase = TrainingPhase(
            name: "Build Up",
            startDate: Date(),
            endDate: Date().addingTimeInterval(4 * 7 * 24 * 60 * 60),
            weeklyMileageKm: 40
        )
        
        for goal in goals {
            // When: Selecting exercises for each goal
            let exercises = selector.selectExercises(
                for: phase,
                goalType: goal,
                availableEquipment: equipment,
                recentExercises: []
            )
            
            // Then: Should have adequate exercises
            XCTAssertGreaterThanOrEqual(
                exercises.count,
                5,
                "Goal \(goal.displayName) should have at least 5 exercises in Build Up"
            )
        }
    }
    
    // MARK: - Fallback Strategy Tests
    
    func testFallbackStrategy_RelaxesFiltersProgressively() {
        // Given: Very restrictive scenario
        let equipment: Set<GymEquipment> = [.barbell, .squatRack]  // No .none initially
        let phase = TrainingPhase(
            name: "Base Building",
            startDate: Date(),
            endDate: Date().addingTimeInterval(4 * 7 * 24 * 60 * 60),
            weeklyMileageKm: 30
        )
        
        // Large recent list + specific goal
        let recentExercises = Array(repeating: "test_exercise", count: 20)
        
        // When: Selecting exercises
        let exercises = selector.selectExercises(
            for: phase,
            goalType: .fiveK,
            availableEquipment: equipment,
            recentExercises: recentExercises
        )
        
        // Then: Should still generate exercises via fallback
        XCTAssertFalse(exercises.isEmpty, "Fallback should prevent empty exercise list")
    }
    
    // MARK: - Exercise Assignment Tests
    
    func testExerciseAssignments_HaveValidParameters() {
        // Given: Standard setup
        let equipment: Set<GymEquipment> = [.none, .dumbbells, .resistanceBands]
        let phase = TrainingPhase(
            name: "Base Building",
            startDate: Date(),
            endDate: Date().addingTimeInterval(4 * 7 * 24 * 60 * 60),
            weeklyMileageKm: 30
        )
        
        // When: Selecting exercises
        let exercises = selector.selectExercises(
            for: phase,
            goalType: .general,
            availableEquipment: equipment,
            recentExercises: []
        )
        
        // Then: All assignments should have valid parameters
        for assignment in exercises {
            XCTAssertGreaterThan(assignment.sets, 0, "Sets should be positive")
            XCTAssertGreaterThan(assignment.order, 0, "Order should be positive")
            
            if let reps = assignment.reps {
                XCTAssertGreaterThan(reps.lowerBound, 0, "Reps lower bound should be positive")
                XCTAssertGreaterThanOrEqual(reps.upperBound, reps.lowerBound, "Reps upper bound should be >= lower bound")
            }
            
            if let rest = assignment.restSeconds {
                XCTAssertGreaterThanOrEqual(rest, 0, "Rest seconds should be non-negative")
            }
        }
    }
    
    // MARK: - UserTrainingProfile Tests
    
    func testUserTrainingProfile_AlwaysIncludesBodyweight() {
        // Given: Various equipment configurations
        let configs: [Set<GymEquipment>] = [
            [],
            [.dumbbells],
            [.barbell, .squatRack],
            [.resistanceBands, .bench]
        ]
        
        for config in configs {
            // When: Creating profile
            let profile = UserTrainingProfile(availableEquipment: config)
            
            // Then: Should always have .none
            XCTAssertTrue(
                profile.availableEquipment.contains(.none),
                "Profile should always include bodyweight option (.none)"
            )
        }
    }
}
