import Foundation

/// Individual data point captured during a workout
struct WorkoutSample: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let speedMps: Double // meters per second
    let paceSecPerKm: Double // seconds per kilometer
    let totalDistanceMeters: Double
    let cadenceSpm: Double? // steps per minute (optional)
    let steps: Int? // total steps (optional)
    let heartRate: Int? // heart rate in BPM (optional)
    
    init(timestamp: Date, speedMps: Double, totalDistanceMeters: Double, cadenceSpm: Double? = nil, steps: Int? = nil, heartRate: Int? = nil) {
        self.id = UUID()
        self.timestamp = timestamp
        self.speedMps = speedMps
        self.totalDistanceMeters = totalDistanceMeters
        self.cadenceSpm = cadenceSpm
        self.steps = steps
        self.heartRate = heartRate
        
        // Calculate pace from speed (avoid division by zero)
        if speedMps > 0 {
            self.paceSecPerKm = 1000.0 / speedMps
        } else {
            self.paceSecPerKm = 0
        }
    }
}

