import Foundation

/// Generates realistic test workout data for development and testing
class TestDataGenerator {
    
    /// Generate and save test workouts to storage
    static func generateTestWorkouts(storageManager: StorageManager) {
        let workouts = [
            generateTempoRun(),
            generateIntervalWorkout(),
            generateMarathon(),
            generateSteadyRun()
        ]
        
        for workout in workouts {
            storageManager.saveWorkout(workout)
        }
        
        print("✅ Generated \(workouts.count) test workouts")
    }
    
    // MARK: - Workout Generators
    
    /// 30-minute tempo run (medium-hard pace)
    private static func generateTempoRun() -> WorkoutSession {
        let startTime = Date().addingTimeInterval(-7 * 24 * 3600) // 7 days ago
        var session = WorkoutSession(startTime: startTime)
        
        let durationSeconds = 30 * 60.0 // 30 minutes
        let targetPace = 4.5 * 60.0 // 4:30 min/km (tempo pace)
        let targetSpeed = 1000.0 / targetPace // m/s
        
        var currentDistance = 0.0
        var currentTime = 0.0
        let sampleInterval = 1.0 // 1 second intervals
        
        var allSamples: [WorkoutSample] = [] // Temporary array for split calculation
        
        while currentTime < durationSeconds {
            // Add some natural variation (±5%)
            let speedVariation = Double.random(in: 0.95...1.05)
            let speed = targetSpeed * speedVariation
            
            currentDistance += speed * sampleInterval
            let timestamp = startTime.addingTimeInterval(currentTime)
            
            let sample = WorkoutSample(
                timestamp: timestamp,
                speedMps: speed,
                totalDistanceMeters: currentDistance,
                cadenceSpm: Double.random(in: 165...175),
                steps: Int(currentTime * 2.8) // ~168 spm average
            )
            
            allSamples.append(sample)
            currentTime += sampleInterval
        }
        
        session.endTime = startTime.addingTimeInterval(durationSeconds)
        
        // Calculate splits from all samples with enhanced metrics
        session.splits = calculateEnhancedSplits(samples: allSamples, startTime: startTime)
        
        // Only keep last 5 minutes of samples
        let keepAfter = session.endTime.addingTimeInterval(-300)
        session.recentSamples = allSamples.filter { $0.timestamp >= keepAfter }
        
        return session
    }
    
    /// Interval workout: alternating tempo pace and sprint bursts
    private static func generateIntervalWorkout() -> WorkoutSession {
        let startTime = Date().addingTimeInterval(-3 * 24 * 3600) // 3 days ago
        var session = WorkoutSession(startTime: startTime)
        
        let durationSeconds = 25 * 60.0 // 25 minutes
        let tempoPace = 4.5 * 60.0 // 4:30 min/km
        let tempoSpeed = 1000.0 / tempoPace
        let sprintSpeed = tempoSpeed * 1.5 // 50% faster for sprints
        
        var currentDistance = 0.0
        var currentTime = 0.0
        let sampleInterval = 1.0
        
        // Sprint every 2 minutes for 15 seconds
        let intervalDuration = 2 * 60.0
        let sprintDuration = 15.0
        
        var allSamples: [WorkoutSample] = []
        
        while currentTime < durationSeconds {
            let timeInCycle = currentTime.truncatingRemainder(dividingBy: intervalDuration)
            let isSprinting = timeInCycle < sprintDuration
            
            let baseSpeed = isSprinting ? sprintSpeed : tempoSpeed
            let speedVariation = Double.random(in: 0.98...1.02)
            let speed = baseSpeed * speedVariation
            
            currentDistance += speed * sampleInterval
            let timestamp = startTime.addingTimeInterval(currentTime)
            
            let cadence = isSprinting ? Double.random(in: 185...195) : Double.random(in: 165...175)
            
            let sample = WorkoutSample(
                timestamp: timestamp,
                speedMps: speed,
                totalDistanceMeters: currentDistance,
                cadenceSpm: cadence,
                steps: Int(currentTime * 2.9)
            )
            
            allSamples.append(sample)
            currentTime += sampleInterval
        }
        
        session.endTime = startTime.addingTimeInterval(durationSeconds)
        session.splits = calculateEnhancedSplits(samples: allSamples, startTime: startTime)
        
        let keepAfter = session.endTime.addingTimeInterval(-300)
        session.recentSamples = allSamples.filter { $0.timestamp >= keepAfter }
        
        return session
    }
    
    /// Full marathon (42.195 km)
    private static func generateMarathon() -> WorkoutSession {
        let startTime = Date().addingTimeInterval(-30 * 24 * 3600) // 30 days ago
        var session = WorkoutSession(startTime: startTime)
        
        let targetDistance = 42195.0 // meters
        let targetTimeSeconds = 4 * 3600.0 // 4 hour marathon
        let baseSpeed = targetDistance / targetTimeSeconds // avg m/s
        
        var currentDistance = 0.0
        var currentTime = 0.0
        let sampleInterval = 2.0 // 2 second intervals for efficiency
        
        var allSamples: [WorkoutSample] = []
        
        while currentDistance < targetDistance {
            // Simulate fatigue: gradually slow down
            let progressRatio = currentDistance / targetDistance
            let fatigueMultiplier = 1.0 - (progressRatio * 0.15) // 15% slower by the end
            
            // Add variation
            let speedVariation = Double.random(in: 0.95...1.05)
            let speed = baseSpeed * fatigueMultiplier * speedVariation
            
            currentDistance += speed * sampleInterval
            let timestamp = startTime.addingTimeInterval(currentTime)
            
            // Cadence decreases with fatigue
            let cadence = 170 - (progressRatio * 10) + Double.random(in: -2...2)
            
            let sample = WorkoutSample(
                timestamp: timestamp,
                speedMps: speed,
                totalDistanceMeters: currentDistance,
                cadenceSpm: cadence,
                steps: Int(currentTime * 2.7)
            )
            
            allSamples.append(sample)
            currentTime += sampleInterval
        }
        
        session.endTime = startTime.addingTimeInterval(currentTime)
        session.splits = calculateEnhancedSplits(samples: allSamples, startTime: startTime)
        
        let keepAfter = session.endTime.addingTimeInterval(-300)
        session.recentSamples = allSamples.filter { $0.timestamp >= keepAfter }
        
        return session
    }
    
    /// Average steady-state run (8km, easy pace)
    private static func generateSteadyRun() -> WorkoutSession {
        let startTime = Date().addingTimeInterval(-1 * 24 * 3600) // Yesterday
        var session = WorkoutSession(startTime: startTime)
        
        let targetDistance = 8000.0 // 8 km
        let easyPace = 5.5 * 60.0 // 5:30 min/km (easy pace)
        let targetSpeed = 1000.0 / easyPace
        
        var currentDistance = 0.0
        var currentTime = 0.0
        let sampleInterval = 1.0
        
        var allSamples: [WorkoutSample] = []
        
        while currentDistance < targetDistance {
            // Minimal variation for steady run
            let speedVariation = Double.random(in: 0.97...1.03)
            let speed = targetSpeed * speedVariation
            
            currentDistance += speed * sampleInterval
            let timestamp = startTime.addingTimeInterval(currentTime)
            
            let sample = WorkoutSample(
                timestamp: timestamp,
                speedMps: speed,
                totalDistanceMeters: currentDistance,
                cadenceSpm: Double.random(in: 160...168),
                steps: Int(currentTime * 2.7)
            )
            
            allSamples.append(sample)
            currentTime += sampleInterval
        }
        
        session.endTime = startTime.addingTimeInterval(currentTime)
        session.splits = calculateEnhancedSplits(samples: allSamples, startTime: startTime)
        
        let keepAfter = session.endTime.addingTimeInterval(-300)
        session.recentSamples = allSamples.filter { $0.timestamp >= keepAfter }
        
        return session
    }
    
    // MARK: - Helper Methods
    
    /// Calculate kilometer splits from samples with enhanced metrics
    private static func calculateEnhancedSplits(samples: [WorkoutSample], startTime: Date) -> [Split] {
        var splits: [Split] = []
        var lastKmDistance = 0.0
        var lastKmTime = startTime
        var currentKmSamples: [WorkoutSample] = []
        
        for sample in samples {
            let currentKm = Int(sample.totalDistanceMeters / 1000.0)
            let lastKm = Int(lastKmDistance / 1000.0)
            
            currentKmSamples.append(sample)
            
            if currentKm > lastKm {
                // Calculate split time
                let splitTime = sample.timestamp.timeIntervalSince(lastKmTime)
                
                // Calculate aggregate metrics from samples in this kilometer
                let avgHeartRate: Int? = {
                    let hrs = currentKmSamples.compactMap { $0.heartRate }
                    guard !hrs.isEmpty else { return nil }
                    return hrs.reduce(0, +) / hrs.count
                }()
                
                let avgCadence: Double? = {
                    let cadences = currentKmSamples.compactMap { $0.cadenceSpm }
                    guard !cadences.isEmpty else { return nil }
                    return cadences.reduce(0, +) / Double(cadences.count)
                }()
                
                let avgSpeed: Double? = {
                    let speeds = currentKmSamples.map { $0.speedMps }
                    guard !speeds.isEmpty else { return nil }
                    return speeds.reduce(0, +) / Double(speeds.count)
                }()
                
                let split = Split(
                    kmIndex: currentKm,
                    splitTimeSeconds: splitTime,
                    avgHeartRate: avgHeartRate,
                    avgCadence: avgCadence,
                    avgSpeedMps: avgSpeed
                )
                splits.append(split)
                
                lastKmDistance = sample.totalDistanceMeters
                lastKmTime = sample.timestamp
                currentKmSamples = []
            }
        }
        
        return splits
    }
}



