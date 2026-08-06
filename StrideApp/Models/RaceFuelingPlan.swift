import Foundation
import SwiftData

/// Local SwiftData mirror of backend race_fueling_plans.
/// Phase 6 stores each phase as raw JSON; the iOS view decodes on render.
@Model
final class RaceFuelingPlan {
    @Attribute(.unique) var id: String

    var eventId: String
    var generatedAt: Date

    /// JSON-encoded phase blobs
    var threeDaysBeforeJSON: String
    var raceMorningJSON: String
    var duringRaceJSON: String
    var postRaceJSON: String

    var weatherForecastJSON: String?
    var courseNotes: String?
    var athleteEditsJSON: String

    init(
        id: String,
        eventId: String,
        generatedAt: Date,
        threeDaysBeforeJSON: String = "{}",
        raceMorningJSON: String = "{}",
        duringRaceJSON: String = "{}",
        postRaceJSON: String = "{}",
        weatherForecastJSON: String? = nil,
        courseNotes: String? = nil,
        athleteEditsJSON: String = "{}"
    ) {
        self.id = id
        self.eventId = eventId
        self.generatedAt = generatedAt
        self.threeDaysBeforeJSON = threeDaysBeforeJSON
        self.raceMorningJSON = raceMorningJSON
        self.duringRaceJSON = duringRaceJSON
        self.postRaceJSON = postRaceJSON
        self.weatherForecastJSON = weatherForecastJSON
        self.courseNotes = courseNotes
        self.athleteEditsJSON = athleteEditsJSON
    }
}
