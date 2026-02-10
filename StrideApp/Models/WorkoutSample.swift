import Foundation

struct WorkoutSample: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let speedMps: Double          // meters per second
    let paceSecPerKm: Double      // seconds per kilometer
    let totalDistanceMeters: Double
    let heartRate: Int?           // bpm (optional)

    init(timestamp: Date, speedMps: Double, totalDistanceMeters: Double, heartRate: Int? = nil) {
        self.id = UUID()
        self.timestamp = timestamp
        self.speedMps = speedMps
        self.totalDistanceMeters = totalDistanceMeters
        self.heartRate = heartRate

        if speedMps > 0 {
            self.paceSecPerKm = 1000.0 / speedMps
        } else {
            self.paceSecPerKm = 0
        }
    }
}
