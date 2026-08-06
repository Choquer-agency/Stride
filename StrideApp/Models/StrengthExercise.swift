import Foundation
import SwiftData

/// Cached library entry mirroring backend strength_exercises rows.
/// Synced from `GET /api/strength/library` on app foreground.
@Model
final class StrengthExercise {
    @Attribute(.unique) var id: String

    var name: String
    var category: String
    var equipment: String
    var youtubeDemoUrl: String?
    var defaultSetCount: Int
    var defaultRepRange: String

    init(
        id: String,
        name: String,
        category: String,
        equipment: String,
        youtubeDemoUrl: String? = nil,
        defaultSetCount: Int = 3,
        defaultRepRange: String = "8-12"
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.equipment = equipment
        self.youtubeDemoUrl = youtubeDemoUrl
        self.defaultSetCount = defaultSetCount
        self.defaultRepRange = defaultRepRange
    }
}
