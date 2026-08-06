import Foundation
import SwiftData

/// Local SwiftData mirror of the backend race_logistics_checklists row.
///
/// Items are stored as raw JSON so the LLM-generated structure can evolve
/// without migrations. iOS decodes on render and writes optimistic updates
/// back via the PATCH endpoint.
@Model
final class RaceLogisticsChecklist {
    @Attribute(.unique) var id: String

    var eventId: String
    var generatedAt: Date

    /// `[{label, detail, category, completed (bool), athlete_note}]` JSON-encoded
    var itemsJSON: String

    var weatherForecastJSON: String?
    var courseIntelJSON: String?

    var aGoalSeconds: Int?
    var bGoalSeconds: Int?
    var cGoalSeconds: Int?

    init(
        id: String,
        eventId: String,
        generatedAt: Date,
        itemsJSON: String = "[]",
        weatherForecastJSON: String? = nil,
        courseIntelJSON: String? = nil,
        aGoalSeconds: Int? = nil,
        bGoalSeconds: Int? = nil,
        cGoalSeconds: Int? = nil
    ) {
        self.id = id
        self.eventId = eventId
        self.generatedAt = generatedAt
        self.itemsJSON = itemsJSON
        self.weatherForecastJSON = weatherForecastJSON
        self.courseIntelJSON = courseIntelJSON
        self.aGoalSeconds = aGoalSeconds
        self.bGoalSeconds = bGoalSeconds
        self.cGoalSeconds = cGoalSeconds
    }
}
