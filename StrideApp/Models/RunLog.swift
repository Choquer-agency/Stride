import Foundation
import SwiftData

@Model
final class RunLog {
    var id: UUID
    var completedAt: Date

    // Actual run data (immutable after creation)
    var distanceKm: Double
    var durationSeconds: Double
    var avgPaceSecPerKm: Double
    var kmSplitsJSON: String?

    // User feedback
    var feedbackRating: Int?
    var notes: String?

    // Sync & verification
    var syncedToServer: Bool = false
    var dataSource: String = "manual"  // "bluetooth_ftms" | "manual"
    var treadmillBrand: String?

    // Shoe context (denormalized — survives shoe deletion)
    var shoeId: UUID?
    var shoeName: String?

    // Plan context snapshot (denormalized — survives plan deletion)
    var plannedWorkoutId: UUID?
    var plannedWorkoutTitle: String?
    var plannedWorkoutTypeRaw: String?
    var plannedDistanceKm: Double?
    var plannedDurationMinutes: Int?
    var plannedPaceDescription: String?
    var completionScore: Int?
    var planName: String?
    var weekNumber: Int?

    // MARK: - Computed Properties

    var isFreeRun: Bool {
        plannedWorkoutId == nil
    }

    var plannedWorkoutType: WorkoutType? {
        guard let raw = plannedWorkoutTypeRaw else { return nil }
        return WorkoutType(rawValue: raw)
    }

    var effectiveTitle: String {
        if let title = plannedWorkoutTitle, !title.isEmpty {
            return title
        }
        return isFreeRun ? "Free Run" : "Run"
    }

    /// Formatted actual pace string (M:SS /km)
    var actualPaceDisplay: String? {
        guard avgPaceSecPerKm > 0, avgPaceSecPerKm < 3600 else { return nil }
        let minutes = Int(avgPaceSecPerKm) / 60
        let seconds = Int(avgPaceSecPerKm) % 60
        return "\(minutes):\(String(format: "%02d", seconds)) /km"
    }

    /// Decoded km splits from JSON
    var decodedKmSplits: [CodableKilometerSplit] {
        guard let json = kmSplitsJSON,
              let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([CodableKilometerSplit].self, from: data)) ?? []
    }

    /// Formatted date string like "Feb 7"
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: completedAt)
    }

    /// Distance display string
    var distanceDisplay: String {
        if distanceKm == floor(distanceKm) {
            return "\(Int(distanceKm)) km"
        }
        return String(format: "%.1f km", distanceKm)
    }

    /// Duration display string
    var durationDisplay: String {
        let totalSec = Int(durationSeconds)
        let h = totalSec / 3600
        let m = (totalSec % 3600) / 60
        let s = totalSec % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Initializer

    init(
        distanceKm: Double,
        durationSeconds: Double,
        avgPaceSecPerKm: Double,
        kmSplitsJSON: String? = nil,
        feedbackRating: Int? = nil,
        notes: String? = nil,
        dataSource: String = "manual",
        treadmillBrand: String? = nil,
        shoeId: UUID? = nil,
        shoeName: String? = nil,
        plannedWorkoutId: UUID? = nil,
        plannedWorkoutTitle: String? = nil,
        plannedWorkoutTypeRaw: String? = nil,
        plannedDistanceKm: Double? = nil,
        plannedDurationMinutes: Int? = nil,
        plannedPaceDescription: String? = nil,
        completionScore: Int? = nil,
        planName: String? = nil,
        weekNumber: Int? = nil
    ) {
        self.id = UUID()
        self.completedAt = Date()
        self.distanceKm = distanceKm
        self.durationSeconds = durationSeconds
        self.avgPaceSecPerKm = avgPaceSecPerKm
        self.kmSplitsJSON = kmSplitsJSON
        self.feedbackRating = feedbackRating
        self.notes = notes
        self.dataSource = dataSource
        self.treadmillBrand = treadmillBrand
        self.shoeId = shoeId
        self.shoeName = shoeName
        self.plannedWorkoutId = plannedWorkoutId
        self.plannedWorkoutTitle = plannedWorkoutTitle
        self.plannedWorkoutTypeRaw = plannedWorkoutTypeRaw
        self.plannedDistanceKm = plannedDistanceKm
        self.plannedDurationMinutes = plannedDurationMinutes
        self.plannedPaceDescription = plannedPaceDescription
        self.completionScore = completionScore
        self.planName = planName
        self.weekNumber = weekNumber
    }
}
