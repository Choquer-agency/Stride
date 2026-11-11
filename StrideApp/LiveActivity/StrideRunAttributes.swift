import ActivityKit
import Foundation

struct StrideRunAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var pace: String
        var distanceKm: Double
        var targetDistanceKm: Double?
        var elapsedSeconds: Int
        var heartRate: Int?
        var isPaused: Bool
        var updatedAt: Date

        var remainingKm: Double? {
            targetDistanceKm.map { max(0, $0 - distanceKm) }
        }

        var distanceText: String { String(format: "%.1f", distanceKm) }
        var remainingText: String? { remainingKm.map { String(format: "%.1f", $0) } }
        var paceText: String { pace.replacingOccurrences(of: " /km", with: "") }
        var timeText: String {
            let seconds = max(0, elapsedSeconds)
            return seconds >= 3600
                ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
                : String(format: "%d:%02d", seconds / 60, seconds % 60)
        }
    }

    var sessionID: String
    var title: String
    var isOutdoor: Bool
}
