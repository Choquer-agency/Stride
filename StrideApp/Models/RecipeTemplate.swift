import Foundation
import SwiftData

/// Local SwiftData mirror of backend recipe_templates.
@Model
final class RecipeTemplate {
    @Attribute(.unique) var id: String

    var name: String
    var itemsJSON: String

    var totalCalories: Int?
    var totalCarbsG: Double?
    var totalProteinG: Double?
    var totalFatG: Double?

    var useCount: Int
    var lastUsedAt: Date?

    init(
        id: String,
        name: String,
        itemsJSON: String = "[]",
        totalCalories: Int? = nil,
        totalCarbsG: Double? = nil,
        totalProteinG: Double? = nil,
        totalFatG: Double? = nil,
        useCount: Int = 0,
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.itemsJSON = itemsJSON
        self.totalCalories = totalCalories
        self.totalCarbsG = totalCarbsG
        self.totalProteinG = totalProteinG
        self.totalFatG = totalFatG
        self.useCount = useCount
        self.lastUsedAt = lastUsedAt
    }
}
