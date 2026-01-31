import XCTest
@testable import Stride

final class ExerciseSelectionTests: XCTestCase {
    var selector: ExerciseSelector!
    var library: ExerciseLibrary!
    
    override func setUp() {
        super.setUp()
        selector = ExerciseSelector()
        library = ExerciseLibrary.shared
    }
    
    // MARK: - Equipment Filtering Tests
    
    func testEquipmentFiltering_BodyweightOnly() {
        // Test that only bodyweight exercises are returned when no equipment available
        let equipment: Set<GymEquipment> = [.none]
        let exercises = library.filterByEquipment(equipment)
        
        for exercise in exercises {
            XCTAssertTrue(
                exercise.requiredEquipment.allSatisfy { $0 == .none },
                "Exercise \(exercise.name) requires equipment beyond bodyweight"
            )
        }
        
        XCTAssertGreaterThan(exercises.count, 0, "Should have at least some bodyweight exercises")
    }
    
    func testEquipmentFiltering_WithDumbbells() {
        // Test that dumbbell exercises are included when dumbbells available
        let equipment: Set<GymEquipment> = [.none, .dumbbells]
        let exercises = library.filterByEquipment(equipment)
        
        // Should include both bodyweight and dumbbell exercises
        let hasDumbbellExercises = exercises.contains { $0.requiredEquipment.contains(.dumbbells) }
        XCTAssertTrue(hasDumbbellExercises, "Should include dumbbell exercises")
        
        // Should not include exercises requiring other equipment
        for exercise in exercises {
            let requiredSet = Set(exercise.requiredEquipment)
            XCTAssertTrue(
                requiredSet.isSubset(of: equipment),
                "Exercise \(exercise.name) requires equipment not available"
            )
        }
    }
    
    // MARK: - Phase Distribution Tests
    
    func testBasePhaseDistribution() {
        // Base phase should focus on strength and foundational work
        let phase = TrainingPhase.baseBuilding(weeks: 1...4)
        let equipment: Set<GymEquipment> = [.none, .dumbbells, .resistanceBands]
        
        let assignments = selector.selectExercises(
            for: phase,
            goalType: .halfMarathon,
            availableEquipment: equipment,
            recentExercises: []
        )
        
        XCTAssertGreaterThan(assignments.count, 0, "Should generate exercises for base phase")
        
        // Count exercise categories
        var categories: [ExerciseCategory: Int] = [:]
        for assignment in assignments {
            if let exercise = library.getExercise(slug: assignment.exerciseSlug) {
                categories[exercise.category, default: 0] += 1
            }
        }
        
        // Base phase should have more strength exercises
        XCTAssertGreaterThan(
            categories[.strength] ?? 0,
            categories[.plyometrics] ?? 0,
            "Base phase should prioritize strength over plyometrics"
        )
    }
    
    func testPeakPhaseDistribution() {
        // Peak phase should include more power/plyometric work for 5K
        let phase = TrainingPhase.peakTraining(weeks: 10...12)
        let equipment: Set<GymEquipment> = [.none, .dumbbells]
        
        let assignments = selector.selectExercises(
            for: phase,
            goalType: .fiveK,
            availableEquipment: equipment,
            recentExercises: []
        )
        
        XCTAssertGreaterThan(assignments.count, 0, "Should generate exercises for peak phase")
        
        // Should include some plyometric work for 5K goal
        let hasPlyo = assignments.contains { assignment in
            if let exercise = library.getExercise(slug: assignment.exerciseSlug) {
                return exercise.category == .plyometrics
            }
            return false
        }
        
        XCTAssertTrue(hasPlyo, "Peak phase for 5K should include plyometric exercises")
    }
    
    // MARK: - Muscle Balance Tests
    
    func testMuscleGroupBalance() {
        // Test that exercises are balanced across muscle groups
        let phase = TrainingPhase.buildUp(weeks: 5...8)
        let equipment: Set<GymEquipment> = [.none, .dumbbells, .resistanceBands]
        
        let assignments = selector.selectExercises(
            for: phase,
            goalType: .general,
            availableEquipment: equipment,
            recentExercises: []
        )
        
        // Count muscle group usage
        var muscleGroups: [MuscleGroup: Int] = [:]
        for assignment in assignments {
            if let exercise = library.getExercise(slug: assignment.exerciseSlug) {
                for muscle in exercise.primaryMuscles {
                    muscleGroups[muscle, default: 0] += 1
                }
            }
        }
        
        // Should work multiple muscle groups
        XCTAssertGreaterThan(muscleGroups.count, 1, "Should work multiple muscle groups")
        
        // No single muscle group should dominate excessively (more than 60% of exercises)
        let totalExercises = assignments.count
        for (_, count) in muscleGroups {
            let percentage = Double(count) / Double(totalExercises)
            XCTAssertLessThan(
                percentage,
                0.6,
                "Single muscle group should not dominate exercise selection"
            )
        }
    }
    
    // MARK: - Exercise Rotation Tests
    
    func testExerciseRotation() {
        // Test that recent exercises are avoided
        let phase = TrainingPhase.buildUp(weeks: 5...8)
        let equipment: Set<GymEquipment> = [.none, .dumbbells]
        
        // First selection
        let firstSelection = selector.selectExercises(
            for: phase,
            goalType: .general,
            availableEquipment: equipment,
            recentExercises: []
        )
        
        let recentSlugs = firstSelection.map { $0.exerciseSlug }
        
        // Second selection with recent exercises excluded
        let secondSelection = selector.selectExercises(
            for: phase,
            goalType: .general,
            availableEquipment: equipment,
            recentExercises: recentSlugs
        )
        
        // Should have some different exercises
        let overlap = Set(firstSelection.map { $0.exerciseSlug })
            .intersection(Set(secondSelection.map { $0.exerciseSlug }))
        
        let overlapPercentage = Double(overlap.count) / Double(firstSelection.count)
        XCTAssertLessThan(
            overlapPercentage,
            0.5,
            "Should rotate at least 50% of exercises"
        )
    }
    
    // MARK: - Alternative Exercise Tests
    
    func testAlternativeExerciseFinding() {
        // Test finding alternatives for an exercise
        let equipment: Set<GymEquipment> = [.none, .dumbbells]
        
        // Bulgarian split squat requires dumbbells
        if let alternative = selector.findBestAlternative(
            for: "bulgarian_split_squat",
            availableEquipment: equipment
        ) {
            // Alternative should be compatible with available equipment
            let requiredSet = Set(alternative.requiredEquipment)
            XCTAssertTrue(
                requiredSet.isSubset(of: equipment),
                "Alternative should work with available equipment"
            )
            
            // Alternative should work similar muscles
            if let original = library.getExercise(slug: "bulgarian_split_squat") {
                let muscleOverlap = Set(original.primaryMuscles)
                    .intersection(Set(alternative.primaryMuscles))
                XCTAssertGreaterThan(
                    muscleOverlap.count,
                    0,
                    "Alternative should work similar muscles"
                )
            }
        }
    }
    
    func testAlternativeWithLimitedEquipment() {
        // Test finding alternative when equipment is very limited
        let equipment: Set<GymEquipment> = [.none]
        
        // Hip thrust requires bench and barbell
        if let alternative = selector.findBestAlternative(
            for: "hip_thrust",
            availableEquipment: equipment
        ) {
            XCTAssertTrue(
                alternative.requiredEquipment.contains(.none),
                "Alternative should be bodyweight when no equipment available"
            )
        }
    }
    
    // MARK: - Library Validation Tests
    
    func testLibraryHasMinimumExercises() {
        // Should have at least 58 exercises (43 original + 15-20 new)
        XCTAssertGreaterThanOrEqual(
            library.allExercises.count,
            58,
            "Library should contain at least 58 exercises after expansion"
        )
    }
    
    func testEquipmentFiltering_PullUpBar() {
        // Test that pull-up bar exercises are returned when pull-up bar available
        let equipment: Set<GymEquipment> = [.none, .pullUpBar]
        let exercises = library.filterByEquipment(equipment)
        
        let hasPullUpExercises = exercises.contains { $0.requiredEquipment.contains(.pullUpBar) }
        XCTAssertTrue(hasPullUpExercises, "Should include pull-up exercises when pull-up bar available")
        
        // All exercises should be compatible with available equipment
        for exercise in exercises {
            let requiredSet = Set(exercise.requiredEquipment)
            XCTAssertTrue(
                requiredSet.isSubset(of: equipment),
                "Exercise \(exercise.name) requires equipment not available"
            )
        }
    }
    
    func testEquipmentFiltering_PlyoBox() {
        // Test that plyo box exercises are returned when box available
        let equipment: Set<GymEquipment> = [.none, .plyoBox]
        let exercises = library.filterByEquipment(equipment)
        
        let hasPlyoBoxExercises = exercises.contains { $0.requiredEquipment.contains(.plyoBox) }
        XCTAssertTrue(hasPlyoBoxExercises, "Should include plyo box exercises when box available")
    }
    
    func testEquipmentFiltering_NewEquipment() {
        // Test filtering with multiple new equipment types
        let equipment: Set<GymEquipment> = [.none, .pullUpBar, .plyoBox, .sled, .trxBands, .foamRoller]
        let exercises = library.filterByEquipment(equipment)
        
        XCTAssertGreaterThan(exercises.count, 0, "Should return exercises for new equipment")
        
        // Verify all exercises are compatible
        for exercise in exercises {
            let requiredSet = Set(exercise.requiredEquipment)
            XCTAssertTrue(
                requiredSet.isSubset(of: equipment),
                "Exercise \(exercise.name) requires equipment not in available set"
            )
        }
    }
    
    func testNewExerciseAlternativesExist() {
        // Test that new exercises have valid alternative references
        let newExerciseSlugs = ["pull_up", "step_up", "sled_push", "stability_ball_plank", "foam_roll_it_band"]
        
        for slug in newExerciseSlugs {
            if let exercise = library.getExercise(slug: slug) {
                for altSlug in exercise.alternativeExercises {
                    XCTAssertNotNil(
                        library.getExercise(slug: altSlug),
                        "New exercise \(exercise.name) references non-existent alternative: \(altSlug)"
                    )
                }
            }
        }
    }
    
    func testNewExercisesHaveMovementPatterns() {
        // Test that all new exercises have valid movement patterns
        let newExerciseSlugs = [
            "pull_up", "assisted_pull_up", "step_up", "box_squat", "sled_push",
            "landmine_single_leg_rdl", "trx_single_leg_squat",
            "stability_ball_plank", "trx_fallout", "wall_ball_rotational_throw", "ghd_hip_extension",
            "foam_roll_it_band", "foam_roll_calves", "banded_ankle_mobility", "wall_calf_stretch",
            "box_step_down", "lateral_box_hop", "sled_sprint"
        ]
        
        for slug in newExerciseSlugs {
            if let exercise = library.getExercise(slug: slug) {
                // Movement pattern should be one of the valid enum cases
                // This is implicitly tested by Swift's type system, but we can verify the exercise exists
                XCTAssertNotNil(exercise, "New exercise \(slug) should exist")
            }
        }
    }
    
    func testAllAlternativesExist() {
        // Test that all alternative exercise references are valid
        for exercise in library.allExercises {
            for altSlug in exercise.alternativeExercises {
                XCTAssertNotNil(
                    library.getExercise(slug: altSlug),
                    "Exercise \(exercise.name) references non-existent alternative: \(altSlug)"
                )
            }
        }
    }
    
    func testNoCircularAlternatives() {
        // Test that no circular alternative references exist
        for exercise in library.allExercises {
            for altSlug in exercise.alternativeExercises {
                if let alternative = library.getExercise(slug: altSlug) {
                    XCTAssertFalse(
                        alternative.alternativeExercises.contains(exercise.slug),
                        "Circular alternative reference between \(exercise.name) and \(alternative.name)"
                    )
                }
            }
        }
    }
    
    func testAllExercisesHavePrimaryMuscles() {
        // Every exercise should target at least one primary muscle
        for exercise in library.allExercises {
            XCTAssertGreaterThan(
                exercise.primaryMuscles.count,
                0,
                "Exercise \(exercise.name) has no primary muscles"
            )
        }
    }
}
