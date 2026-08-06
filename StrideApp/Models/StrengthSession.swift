import Foundation
import SwiftData

/// Local mirror of backend strength_sessions row (one logged gym session).
@Model
final class StrengthSession {
    @Attribute(.unique) var id: String

    var date: String  // ISO yyyy-MM-dd
    var quickLogged: Bool
    var perceivedEffort: Int?
    var durationMinutes: Int?
    var notes: String?
    var submittedAt: Date

    init(
        id: String,
        date: String,
        quickLogged: Bool = false,
        perceivedEffort: Int? = nil,
        durationMinutes: Int? = nil,
        notes: String? = nil,
        submittedAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.quickLogged = quickLogged
        self.perceivedEffort = perceivedEffort
        self.durationMinutes = durationMinutes
        self.notes = notes
        self.submittedAt = submittedAt
    }
}
