import Foundation

/// VDOT Calculator using Jack Daniels' Running Formula methodology
/// Source: Jack Daniels' Running Formula (3rd Edition)
class VDOTCalculator {
    
    // MARK: - Public Methods
    
    /// Calculate VDOT from race performance
    /// - Parameters:
    ///   - distanceKm: Race distance in kilometers
    ///   - timeSeconds: Time to complete the distance in seconds
    /// - Returns: VDOT value (typically 30-85 for most runners)
    static func calculateVDOT(distanceKm: Double, timeSeconds: Double) -> Double {
        guard distanceKm > 0 && timeSeconds > 0 else { return 0 }
        
        // Convert distance to meters
        let distanceMeters = distanceKm * 1000.0
        
        // Calculate velocity in meters per minute
        let velocityMPM = (distanceMeters / timeSeconds) * 60.0
        
        // Calculate VO2 using Jack Daniels' formula
        let percentMax = 0.8 + 0.1894393 * exp(-0.012778 * (timeSeconds / 60.0)) + 0.2989558 * exp(-0.1932605 * (timeSeconds / 60.0))
        
        let vo2 = -4.60 + 0.182258 * velocityMPM + 0.000104 * velocityMPM * velocityMPM
        
        // Calculate VDOT
        let vdot = vo2 / percentMax
        
        // Clamp to reasonable range (30-85)
        return max(30.0, min(85.0, vdot))
    }
    
    /// Calculate training paces from VDOT
    /// - Parameters:
    ///   - vdot: VDOT value
    ///   - goalDistanceKm: Optional goal distance for race pace calculation
    /// - Returns: Training paces structure
    static func calculateTrainingPaces(vdot: Double, goalDistanceKm: Double?) -> TrainingPaces {
        // Easy pace range (59-74% of VDOT)
        let easyMin = velocityToSecondsPerKm(velocity: calculateVelocity(vdot: vdot, percent: 0.74))
        let easyMax = velocityToSecondsPerKm(velocity: calculateVelocity(vdot: vdot, percent: 0.59))
        
        // Long run pace range (75-84% of VDOT)
        let longRunMin = velocityToSecondsPerKm(velocity: calculateVelocity(vdot: vdot, percent: 0.84))
        let longRunMax = velocityToSecondsPerKm(velocity: calculateVelocity(vdot: vdot, percent: 0.75))
        
        // Threshold pace (88% of VDOT)
        let threshold = velocityToSecondsPerKm(velocity: calculateVelocity(vdot: vdot, percent: 0.88))
        
        // Interval pace (98% of VDOT)
        let interval = velocityToSecondsPerKm(velocity: calculateVelocity(vdot: vdot, percent: 0.98))
        
        // Repetition pace (105% of VDOT)
        let repetition = velocityToSecondsPerKm(velocity: calculateVelocity(vdot: vdot, percent: 1.05))
        
        // Calculate race pace if goal distance provided
        let racePace = goalDistanceKm.map { calculateRacePace(vdot: vdot, distanceKm: $0) }
        
        return TrainingPaces(
            easy: PaceRange(min: easyMin, max: easyMax),
            longRun: PaceRange(min: longRunMin, max: longRunMax),
            threshold: threshold,
            interval: interval,
            repetition: repetition,
            racePace: racePace
        )
    }
    
    /// Calculate race pace for specific distance
    /// - Parameters:
    ///   - vdot: VDOT value
    ///   - distanceKm: Race distance in kilometers
    /// - Returns: Predicted race pace in seconds per km
    static func calculateRacePace(vdot: Double, distanceKm: Double) -> Double {
        // Estimate race time for the distance
        let raceTimeSeconds = predictRaceTime(vdot: vdot, distanceKm: distanceKm)
        
        // Calculate pace
        return raceTimeSeconds / distanceKm
    }
    
    /// Predict race time for a given distance and VDOT
    /// - Parameters:
    ///   - vdot: VDOT value
    ///   - distanceKm: Race distance in kilometers
    /// - Returns: Predicted race time in seconds
    static func predictRaceTime(vdot: Double, distanceKm: Double) -> TimeInterval {
        let distanceMeters = distanceKm * 1000.0
        
        // Estimate race duration using iterative approach
        var timeMinutes = 1.0
        var lastTime = timeMinutes
        
        for _ in 0..<20 {
            let percentMax = 0.8 + 0.1894393 * exp(-0.012778 * timeMinutes) + 0.2989558 * exp(-0.1932605 * timeMinutes)
            let vo2 = vdot * percentMax
            
            // Solve for velocity
            let a = 0.000104
            let b = 0.182258
            let c = -4.60 - vo2
            
            let velocity = (-b + sqrt(b * b - 4 * a * c)) / (2 * a)
            
            // Calculate time from velocity (m/min)
            timeMinutes = distanceMeters / velocity
            
            if abs(timeMinutes - lastTime) < 0.01 {
                break
            }
            lastTime = timeMinutes
        }
        
        return timeMinutes * 60.0 // Convert to seconds
    }
    
    /// Predict race times for common distances
    /// - Parameter vdot: VDOT value
    /// - Returns: Dictionary of race names to predicted times
    static func predictRaceTimes(vdot: Double) -> [String: TimeInterval] {
        let distances: [(String, Double)] = [
            ("1500m", 1.5),
            ("3K", 3.0),
            ("5K", 5.0),
            ("10K", 10.0),
            ("15K", 15.0),
            ("Half Marathon", 21.0975),
            ("Marathon", 42.195)
        ]
        
        var predictions: [String: TimeInterval] = [:]
        for (name, distance) in distances {
            predictions[name] = predictRaceTime(vdot: vdot, distanceKm: distance)
        }
        
        return predictions
    }
    
    /// Check if workout qualifies as a race-quality effort
    /// - Parameter workout: Workout session to evaluate
    /// - Returns: True if workout is race-quality
    static func isRaceQualityEffort(workout: WorkoutSession) -> Bool {
        // Must have minimum duration (20 minutes)
        guard workout.durationSeconds >= 20 * 60 else {
            return false
        }
        
        // Must have minimum distance (3km)
        guard workout.totalDistanceKm >= 3.0 else {
            return false
        }
        
        // Must not be marked as easy effort (ratings 1-4 out of 10)
        if let effort = workout.effortRating, effort <= 4 {
            return false
        }
        
        // Check pace consistency (standard deviation < 10% of average)
        guard !workout.splits.isEmpty else {
            return false
        }
        
        let paces = workout.splits.map { $0.avgPaceSecondsPerKm }
        let avgPace = paces.reduce(0.0, +) / Double(paces.count)
        
        // Calculate standard deviation
        let variance = paces.map { pow($0 - avgPace, 2) }.reduce(0.0, +) / Double(paces.count)
        let stdDev = sqrt(variance)
        
        // Pace variability must be less than 10%
        let variability = (stdDev / avgPace) * 100.0
        
        return variability < 10.0
    }
    
    /// Find best race-quality effort from workout history
    /// - Parameter workouts: Array of workout sessions
    /// - Returns: Best qualifying workout, or nil if none found
    static func findBestRaceEffort(from workouts: [WorkoutSession]) -> WorkoutSession? {
        // Filter to race-quality efforts from last 90 days
        let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        
        let qualifyingWorkouts = workouts.filter { workout in
            workout.startTime >= ninetyDaysAgo && isRaceQualityEffort(workout: workout)
        }
        
        // Return workout with best (fastest) average pace
        return qualifyingWorkouts.min { $0.avgPaceSecondsPerKm < $1.avgPaceSecondsPerKm }
    }
    
    // MARK: - Private Helper Methods
    
    /// Calculate velocity from VDOT and percentage
    private static func calculateVelocity(vdot: Double, percent: Double) -> Double {
        let vo2 = vdot * percent
        
        // Solve quadratic equation for velocity
        // vo2 = -4.60 + 0.182258*v + 0.000104*v^2
        let a = 0.000104
        let b = 0.182258
        let c = -4.60 - vo2
        
        // Use quadratic formula (take positive root)
        let velocity = (-b + sqrt(b * b - 4 * a * c)) / (2 * a)
        
        return velocity // meters per minute
    }
    
    /// Convert velocity (m/min) to pace (sec/km)
    private static func velocityToSecondsPerKm(velocity: Double) -> Double {
        guard velocity > 0 else { return 999.0 }
        
        // velocity is in m/min
        // pace is in sec/km
        // pace = (1000 m) / (velocity m/min) * (60 sec/min)
        return (1000.0 / velocity) * 60.0
    }
}
