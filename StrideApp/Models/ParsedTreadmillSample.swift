import Foundation

struct ParsedTreadmillSample {
    let timestamp: Date
    let rawHex: String

    // Parsed FTMS fields (nil = not present in this packet)
    let flags: UInt16
    let instantaneousSpeedKmh: Double?   // km/h
    let averageSpeedKmh: Double?         // km/h
    let totalDistanceMeters: Double?     // meters
    let inclinationPercent: Double?      // %
    let rampAngleDegrees: Double?        // degrees
    let positiveElevationGain: Double?   // meters
    let negativeElevationGain: Double?   // meters
    let instantaneousPace: Double?       // seconds per km
    let averagePace: Double?             // seconds per km
    let totalEnergy: Int?                // kcal
    let energyPerHour: Int?              // kcal/h
    let energyPerMinute: Int?            // kcal/min
    let heartRate: Int?                  // bpm
    let metabolicEquivalent: Double?     // MET
    let elapsedTime: Int?                // seconds
    let remainingTime: Int?              // seconds

    // MARK: - Computed Conversions

    /// Speed in meters per second
    var speedMps: Double? {
        guard let kmh = instantaneousSpeedKmh else { return nil }
        return kmh / 3.6
    }

    /// Pace in seconds per kilometer (derived from speed)
    var paceSecPerKm: Double? {
        guard let mps = speedMps, mps > 0 else { return nil }
        return 1000.0 / mps
    }

    /// Convert to a simplified WorkoutSample for downstream use
    func toWorkoutSample() -> WorkoutSample? {
        guard let speedMps = speedMps,
              let distanceMeters = totalDistanceMeters else {
            return nil
        }
        return WorkoutSample(
            timestamp: timestamp,
            speedMps: speedMps,
            totalDistanceMeters: distanceMeters,
            heartRate: heartRate
        )
    }
}
