import Foundation
import SwiftData

/// Local mirror of backend strength_sets — one set within a detailed strength session.
@Model
final class StrengthSet {
    @Attribute(.unique) var id: String

    var sessionId: String
    var exerciseId: String
    var setNumber: Int
    var reps: Int
    var weightKg: Double?
    var rpe: Int?

    init(
        id: String,
        sessionId: String,
        exerciseId: String,
        setNumber: Int,
        reps: Int,
        weightKg: Double? = nil,
        rpe: Int? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.exerciseId = exerciseId
        self.setNumber = setNumber
        self.reps = reps
        self.weightKg = weightKg
        self.rpe = rpe
    }
}
