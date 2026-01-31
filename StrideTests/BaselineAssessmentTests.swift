import XCTest
@testable import Stride

/// Unit tests for baseline fitness assessment functionality
final class BaselineAssessmentTests: XCTestCase {
    
    var storageManager: StorageManager!
    var hrZonesManager: HeartRateZonesManager!
    var baselineManager: BaselineAssessmentManager!
    
    override func setUp() async throws {
        try await super.setUp()
        storageManager = StorageManager()
        hrZonesManager = HeartRateZonesManager()
        baselineManager = await BaselineAssessmentManager(
            storageManager: storageManager,
            hrZonesManager: hrZonesManager
        )
    }
    
    override func tearDown() async throws {
        // Clean up any test data
        let assessments = storageManager.loadAllBaselineAssessments()
        for assessment in assessments {
            try storageManager.deleteBaselineAssessment(id: assessment.id)
        }
        
        storageManager = nil
        hrZonesManager = nil
        baselineManager = nil
        try await super.tearDown()
    }
    
    // MARK: - VDOT Calculation Tests
    
    func testVDOTCalculation5K() throws {
        // Test 5K in 20:00 should give VDOT ~52.5
        let vdot = VDOTCalculator.calculateVDOT(distanceKm: 5.0, timeSeconds: 20 * 60)
        
        XCTAssertGreaterThan(vdot, 51.0, "VDOT for 5K in 20:00 should be > 51")
        XCTAssertLessThan(vdot, 54.0, "VDOT for 5K in 20:00 should be < 54")
    }
    
    func testVDOTCalculation10K() throws {
        // Test 10K in 45:00 should give VDOT ~48.5
        let vdot = VDOTCalculator.calculateVDOT(distanceKm: 10.0, timeSeconds: 45 * 60)
        
        XCTAssertGreaterThan(vdot, 47.0, "VDOT for 10K in 45:00 should be > 47")
        XCTAssertLessThan(vdot, 50.0, "VDOT for 10K in 45:00 should be < 50")
    }
    
    func testVDOTCalculationMarathon() throws {
        // Test Marathon in 3:30:00 should give VDOT ~44.5
        let vdot = VDOTCalculator.calculateVDOT(distanceKm: 42.195, timeSeconds: 3.5 * 3600)
        
        XCTAssertGreaterThan(vdot, 43.0, "VDOT for Marathon in 3:30:00 should be > 43")
        XCTAssertLessThan(vdot, 46.0, "VDOT for Marathon in 3:30:00 should be < 46")
    }
    
    func testVDOTCalculationInvalidInputs() throws {
        // Test with invalid inputs
        let vdotZeroDistance = VDOTCalculator.calculateVDOT(distanceKm: 0, timeSeconds: 20 * 60)
        XCTAssertEqual(vdotZeroDistance, 0, "VDOT should be 0 for zero distance")
        
        let vdotZeroTime = VDOTCalculator.calculateVDOT(distanceKm: 5.0, timeSeconds: 0)
        XCTAssertEqual(vdotZeroTime, 0, "VDOT should be 0 for zero time")
    }
    
    // MARK: - Training Paces Tests
    
    func testTrainingPacesCalculation() throws {
        let vdot = 50.0
        let paces = VDOTCalculator.calculateTrainingPaces(vdot: vdot, goalDistanceKm: 21.0975)
        
        // Easy pace should be slower than threshold
        XCTAssertGreaterThan(paces.easy.min, paces.threshold,
                           "Easy pace should be slower (higher sec/km) than threshold")
        
        // Threshold should be slower than interval
        XCTAssertGreaterThan(paces.threshold, paces.interval,
                           "Threshold should be slower than interval")
        
        // Interval should be slower than repetition
        XCTAssertGreaterThan(paces.interval, paces.repetition,
                           "Interval should be slower than repetition")
        
        // Race pace should exist for goal distance
        XCTAssertNotNil(paces.racePace, "Race pace should be calculated for goal distance")
        
        // Long run should be faster than easy
        XCTAssertLessThan(paces.longRun.min, paces.easy.max,
                         "Long run min should be faster than easy max")
    }
    
    func testTrainingPacesWithoutGoalDistance() throws {
        let vdot = 50.0
        let paces = VDOTCalculator.calculateTrainingPaces(vdot: vdot, goalDistanceKm: nil)
        
        // Race pace should be nil without goal distance
        XCTAssertNil(paces.racePace, "Race pace should be nil without goal distance")
        
        // Other paces should still be calculated
        XCTAssertGreaterThan(paces.threshold, 0, "Threshold pace should be calculated")
        XCTAssertGreaterThan(paces.interval, 0, "Interval pace should be calculated")
        XCTAssertGreaterThan(paces.repetition, 0, "Repetition pace should be calculated")
    }
    
    // MARK: - Race Quality Effort Detection Tests
    
    func testRaceQualityEffortValid() throws {
        // Create a qualifying workout: 5K in 25 minutes with consistent pace
        var session = WorkoutSession(startTime: Date())
        session.endTime = session.startTime.addingTimeInterval(25 * 60) // 25 minutes
        
        // Add 5 consistent splits
        for i in 1...5 {
            let split = Split(
                kmIndex: i,
                splitTimeSeconds: 5 * 60, // 5:00/km pace
                avgHeartRate: 160,
                avgCadence: 180,
                avgSpeedMps: 3.33
            )
            session.splits.append(split)
        }
        
        // Add effort rating (hard effort)
        session.effortRating = 8
        
        // Create samples
        for i in 0..<150 {
            let sample = WorkoutSample(
                timestamp: session.startTime.addingTimeInterval(Double(i) * 10),
                speedMps: 3.33,
                totalDistanceMeters: Double(i) * 33.3,
                totalTimeSeconds: Double(i) * 10,
                heartRate: 160,
                cadenceSpm: 180
            )
            session.recentSamples.append(sample)
        }
        
        let isRaceQuality = VDOTCalculator.isRaceQualityEffort(workout: session)
        XCTAssertTrue(isRaceQuality, "30min sustained 5K effort should qualify")
    }
    
    func testRaceQualityEffortTooShort() throws {
        // Create a workout that's too short: 10 minutes
        var session = WorkoutSession(startTime: Date())
        session.endTime = session.startTime.addingTimeInterval(10 * 60)
        session.effortRating = 8
        
        let isRaceQuality = VDOTCalculator.isRaceQualityEffort(workout: session)
        XCTAssertFalse(isRaceQuality, "10min run should not qualify (< 20min minimum)")
    }
    
    func testRaceQualityEffortEasyRun() throws {
        // Create a workout marked as easy
        var session = WorkoutSession(startTime: Date())
        session.endTime = session.startTime.addingTimeInterval(30 * 60)
        session.effortRating = 3 // Easy effort
        
        // Add consistent splits
        for i in 1...5 {
            let split = Split(
                kmIndex: i,
                splitTimeSeconds: 6 * 60, // Easy pace
                avgHeartRate: 130,
                avgCadence: 160,
                avgSpeedMps: 2.78
            )
            session.splits.append(split)
        }
        
        let isRaceQuality = VDOTCalculator.isRaceQualityEffort(workout: session)
        XCTAssertFalse(isRaceQuality, "Easy run should not qualify")
    }
    
    func testRaceQualityEffortInconsistentPace() throws {
        // Create a workout with highly variable pace
        var session = WorkoutSession(startTime: Date())
        session.endTime = session.startTime.addingTimeInterval(25 * 60)
        session.effortRating = 8
        
        // Add inconsistent splits (20% pace variation)
        let paces = [4.0, 5.0, 3.5, 6.0, 4.5] // Minutes per km
        for (i, pace) in paces.enumerated() {
            let split = Split(
                kmIndex: i + 1,
                splitTimeSeconds: pace * 60,
                avgHeartRate: 160,
                avgCadence: 180,
                avgSpeedMps: 1000.0 / (pace * 60)
            )
            session.splits.append(split)
        }
        
        let isRaceQuality = VDOTCalculator.isRaceQualityEffort(workout: session)
        XCTAssertFalse(isRaceQuality, "5K with 20% pace variation should not qualify")
    }
    
    // MARK: - Baseline Assessment Manager Tests
    
    func testCreateAssessmentFromRaceResult() async throws {
        let assessment = try await baselineManager.createFromRaceResult(
            distance: 5.0,
            time: 20 * 60, // 20 minutes for 5K
            goalDistance: 21.0975
        )
        
        XCTAssertEqual(assessment.method, .recentRace)
        XCTAssertGreaterThan(assessment.vdot, 50.0)
        XCTAssertNotNil(assessment.trainingPaces.racePace, "Race pace should be calculated")
        
        // Verify it was saved
        let loaded = storageManager.loadBaselineAssessment(id: assessment.id)
        XCTAssertNotNil(loaded, "Assessment should be saved to storage")
    }
    
    func testCreateAssessmentFromTimeTrial() async throws {
        let assessment = try await baselineManager.createFromTimeTrial(
            distance: 10.0,
            time: 45 * 60,
            goalDistance: nil
        )
        
        XCTAssertEqual(assessment.method, .timeTrial)
        XCTAssertGreaterThan(assessment.vdot, 45.0)
        XCTAssertNil(assessment.trainingPaces.racePace, "Race pace should be nil without goal")
    }
    
    func testEvaluateBaselineRequirement() async throws {
        // Create a goal
        let goal = Goal(
            type: .race,
            targetTime: 90 * 60, // 1:30:00
            eventDate: Date().addingTimeInterval(60 * 24 * 3600), // 60 days from now
            raceDistance: .halfMarathon
        )
        
        // No workouts - should require baseline
        let required = baselineManager.evaluateBaselineRequirement(goal: goal, workouts: [])
        XCTAssertTrue(required, "Should require baseline with no workout history")
        XCTAssertTrue(baselineManager.assessmentRequired, "assessmentRequired should be true")
        XCTAssertFalse(baselineManager.requirementReason.isEmpty, "Should have a reason")
    }
    
    func testEvaluateBaselineWithRecentAssessment() async throws {
        // Create a recent assessment
        let assessment = try await baselineManager.createFromRaceResult(
            distance: 5.0,
            time: 20 * 60,
            goalDistance: 21.0975
        )
        
        // Create a goal
        let goal = Goal(
            type: .race,
            targetTime: 90 * 60,
            eventDate: Date().addingTimeInterval(60 * 24 * 3600),
            raceDistance: .halfMarathon
        )
        
        // Should not require baseline (we have recent assessment)
        let required = baselineManager.evaluateBaselineRequirement(goal: goal, workouts: [])
        XCTAssertFalse(required, "Should not require baseline with recent assessment")
    }
    
    // MARK: - Race Time Predictions Tests
    
    func testRaceTimePredictions() throws {
        let vdot = 50.0
        let predictions = VDOTCalculator.predictRaceTimes(vdot: vdot)
        
        // Should have predictions for all standard distances
        XCTAssertNotNil(predictions["5K"])
        XCTAssertNotNil(predictions["10K"])
        XCTAssertNotNil(predictions["Half Marathon"])
        XCTAssertNotNil(predictions["Marathon"])
        
        // Longer distances should have longer times
        XCTAssertLessThan(predictions["5K"]!, predictions["10K"]!)
        XCTAssertLessThan(predictions["10K"]!, predictions["Half Marathon"]!)
        XCTAssertLessThan(predictions["Half Marathon"]!, predictions["Marathon"]!)
    }
    
    // MARK: - Storage Integration Tests
    
    func testSaveAndLoadBaselineAssessment() throws {
        let paces = TrainingPaces(
            easy: PaceRange(min: 330, max: 390),
            longRun: PaceRange(min: 318, max: 330),
            threshold: 285,
            interval: 255,
            repetition: 240,
            racePace: 270
        )
        
        let assessment = BaselineAssessment(
            method: .recentRace,
            vdot: 52.5,
            trainingPaces: paces,
            testDistanceKm: 5.0,
            testTimeSeconds: 20 * 60
        )
        
        // Save
        try storageManager.saveBaselineAssessment(assessment)
        
        // Load
        let loaded = storageManager.loadBaselineAssessment(id: assessment.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.id, assessment.id)
        XCTAssertEqual(loaded?.vdot, assessment.vdot)
        XCTAssertEqual(loaded?.method, assessment.method)
    }
    
    func testLoadLatestBaselineAssessment() throws {
        // Create two assessments with different dates
        let paces = TrainingPaces(
            easy: PaceRange(min: 330, max: 390),
            longRun: PaceRange(min: 318, max: 330),
            threshold: 285,
            interval: 255,
            repetition: 240,
            racePace: nil
        )
        
        let older = BaselineAssessment(
            assessmentDate: Date().addingTimeInterval(-30 * 24 * 3600), // 30 days ago
            method: .recentRace,
            vdot: 50.0,
            trainingPaces: paces
        )
        
        let newer = BaselineAssessment(
            assessmentDate: Date(),
            method: .timeTrial,
            vdot: 52.0,
            trainingPaces: paces
        )
        
        try storageManager.saveBaselineAssessment(older)
        try storageManager.saveBaselineAssessment(newer)
        
        // Latest should be the newer one
        let latest = storageManager.loadLatestBaselineAssessment()
        XCTAssertNotNil(latest)
        XCTAssertEqual(latest?.id, newer.id)
        XCTAssertEqual(latest?.vdot, 52.0)
    }
    
    func testSavePaceFeedback() throws {
        // Create an assessment first
        let paces = TrainingPaces(
            easy: PaceRange(min: 330, max: 390),
            longRun: PaceRange(min: 318, max: 330),
            threshold: 285,
            interval: 255,
            repetition: 240,
            racePace: nil
        )
        
        let assessment = BaselineAssessment(
            method: .guidedTest,
            vdot: 50.0,
            trainingPaces: paces
        )
        
        try storageManager.saveBaselineAssessment(assessment)
        
        // Save feedback
        let feedback = PaceFeedback(
            assessmentId: assessment.id,
            rating: .justRight,
            notes: "Feels good"
        )
        
        try storageManager.savePaceFeedback(assessmentId: assessment.id, feedback: feedback)
        
        // Load feedback
        let loaded = storageManager.loadPaceFeedback(assessmentId: assessment.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.rating, .justRight)
        XCTAssertEqual(loaded?.notes, "Feels good")
    }
}
