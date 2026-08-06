import Foundation
import SwiftData

/// Local SwiftData mirror of backend wellness_checkins for offline display +
/// quick re-render on Stats / Run tabs without an extra fetch.
///
/// The server is the source of truth. iOS submits via POST /api/wellness/checkin
/// and inserts the returned row here. Inbox + trends come from /today, /trends,
/// /history endpoints.
@Model
final class WellnessCheckin {
    @Attribute(.unique) var id: String

    /// Server-stamped date of the entry (yyyy-MM-dd).
    var date: String

    /// "morning" | "pre_run" | "post_run" | "manual"
    var entryMethod: String

    var sleepQuality: Int?
    var soreness: Int?
    var motivation: Int?
    var stress: Int?
    var energy: Int?

    var sorenessAreas: [String]
    var notes: String?

    var submittedAt: Date

    init(
        id: String,
        date: String,
        entryMethod: String,
        sleepQuality: Int? = nil,
        soreness: Int? = nil,
        motivation: Int? = nil,
        stress: Int? = nil,
        energy: Int? = nil,
        sorenessAreas: [String] = [],
        notes: String? = nil,
        submittedAt: Date
    ) {
        self.id = id
        self.date = date
        self.entryMethod = entryMethod
        self.sleepQuality = sleepQuality
        self.soreness = soreness
        self.motivation = motivation
        self.stress = stress
        self.energy = energy
        self.sorenessAreas = sorenessAreas
        self.notes = notes
        self.submittedAt = submittedAt
    }
}
