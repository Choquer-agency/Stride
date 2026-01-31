import Foundation

/// Intermediate parsed data from FTMS 0x2ACD characteristic
struct ParsedTreadmillSample {
    let timestamp: Date
    let rawHex: String
    
    // Parsed FTMS fields
    let flags: UInt16
    let instantaneousSpeedKmh: Double? // km/h
    let averageSpeedKmh: Double?
    let totalDistanceMeters: Double?
    let inclinationPercent: Double?
    let rampAngleDegrees: Double?
    let positiveElevationGain: Double?
    let negativeElevationGain: Double?
    let instantaneousPace: Double? // seconds per km
    let averagePace: Double?
    let totalEnergy: Int?
    let energyPerHour: Int?
    let energyPerMinute: Int?
    let heartRate: Int?
    let metabolicEquivalent: Double?
    let elapsedTime: Int?
    let remainingTime: Int?
    
    // Computed properties
    var speedMps: Double? {
        guard let kmh = instantaneousSpeedKmh else { return nil }
        return kmh / 3.6 // convert km/h to m/s
    }
    
    var paceSecPerKm: Double? {
        guard let mps = speedMps, mps > 0 else { return nil }
        return 1000.0 / mps
    }
    
    /// Convert to WorkoutSample
    func toWorkoutSample() -> WorkoutSample? {
        guard let speedMps = speedMps,
              let distanceMeters = totalDistanceMeters else {
            return nil
        }
        
        return WorkoutSample(
            timestamp: timestamp,
            speedMps: speedMps,
            totalDistanceMeters: distanceMeters,
            cadenceSpm: nil, // FTMS doesn't always include cadence
            steps: nil,
            heartRate: heartRate
        )
    }
}

