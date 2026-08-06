import Foundation
import SwiftData

/// Local SwiftData mirror of backend hydration_logs.
@Model
final class HydrationLog {
    /// Compound id `userId:YYYY-MM-DD` so SwiftData enforces one-per-day locally.
    @Attribute(.unique) var id: String

    var date: String  // ISO yyyy-MM-dd
    var glassesLogged: Int
    var estimatedMl: Int
    var electrolyteServings: Int
    var updatedAt: Date

    init(
        id: String,
        date: String,
        glassesLogged: Int = 0,
        estimatedMl: Int = 0,
        electrolyteServings: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.glassesLogged = glassesLogged
        self.estimatedMl = estimatedMl
        self.electrolyteServings = electrolyteServings
        self.updatedAt = updatedAt
    }
}
