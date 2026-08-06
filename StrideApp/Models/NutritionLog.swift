import Foundation
import SwiftData

/// Local SwiftData mirror of backend nutrition_logs.
/// Source of truth is the server; we cache so Today view stays snappy offline.
@Model
final class NutritionLog {
    @Attribute(.unique) var id: String

    var loggedAt: Date
    var mealType: String          // breakfast / lunch / dinner / snack / pre_workout / post_workout / other
    var entryMethod: String       // photo / text / manual / template

    var photoUrl: String?
    var rawDescription: String?

    /// JSON-encoded `[{name, qty, calories, carbs_g, protein_g, fat_g}]`
    var itemsJSON: String

    var totalCalories: Int
    var totalCarbsG: Double
    var totalProteinG: Double
    var totalFatG: Double

    var confidence: Double?

    init(
        id: String,
        loggedAt: Date,
        mealType: String,
        entryMethod: String,
        photoUrl: String? = nil,
        rawDescription: String? = nil,
        itemsJSON: String = "[]",
        totalCalories: Int = 0,
        totalCarbsG: Double = 0,
        totalProteinG: Double = 0,
        totalFatG: Double = 0,
        confidence: Double? = nil
    ) {
        self.id = id
        self.loggedAt = loggedAt
        self.mealType = mealType
        self.entryMethod = entryMethod
        self.photoUrl = photoUrl
        self.rawDescription = rawDescription
        self.itemsJSON = itemsJSON
        self.totalCalories = totalCalories
        self.totalCarbsG = totalCarbsG
        self.totalProteinG = totalProteinG
        self.totalFatG = totalFatG
        self.confidence = confidence
    }
}
