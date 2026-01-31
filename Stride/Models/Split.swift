import Foundation

/// Represents a kilometer split during a workout with all necessary metrics
struct Split: Codable, Identifiable {
    let id: UUID
    let kmIndex: Int // 1, 2, 3, etc.
    let splitTimeSeconds: Double // time taken for this kilometer
    let avgPaceSecondsPerKm: Double
    let avgHeartRate: Int? // average heart rate for this kilometer
    let avgCadence: Double? // average cadence for this kilometer
    let avgSpeedMps: Double? // average speed in meters per second
    
    init(kmIndex: Int, splitTimeSeconds: Double, avgHeartRate: Int? = nil, avgCadence: Double? = nil, avgSpeedMps: Double? = nil) {
        self.id = UUID()
        self.kmIndex = kmIndex
        self.splitTimeSeconds = splitTimeSeconds
        self.avgPaceSecondsPerKm = splitTimeSeconds // for 1km, split time = pace
        self.avgHeartRate = avgHeartRate
        self.avgCadence = avgCadence
        self.avgSpeedMps = avgSpeedMps
    }
}

