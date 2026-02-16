import Foundation

// MARK: - Run Sync Request/Response

struct RunSyncPayload: Codable {
    let id: String
    let completedAt: String
    let distanceKm: Double
    let durationSeconds: Double
    let avgPaceSecPerKm: Double
    let kmSplitsJson: String?
    let feedbackRating: Int?
    let notes: String?
    let plannedWorkoutTitle: String?
    let plannedWorkoutType: String?
    let plannedDistanceKm: Double?
    let completionScore: Int?
    let planName: String?
    let weekNumber: Int?
    let dataSource: String
    let treadmillBrand: String?
    let shoeId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case completedAt = "completed_at"
        case distanceKm = "distance_km"
        case durationSeconds = "duration_seconds"
        case avgPaceSecPerKm = "avg_pace_sec_per_km"
        case kmSplitsJson = "km_splits_json"
        case feedbackRating = "feedback_rating"
        case notes
        case plannedWorkoutTitle = "planned_workout_title"
        case plannedWorkoutType = "planned_workout_type"
        case plannedDistanceKm = "planned_distance_km"
        case completionScore = "completion_score"
        case planName = "plan_name"
        case weekNumber = "week_number"
        case dataSource = "data_source"
        case treadmillBrand = "treadmill_brand"
        case shoeId = "shoe_id"
    }
}

struct RunBatchSyncRequest: Codable {
    let runs: [RunSyncPayload]
}

struct RunBatchSyncResponse: Codable {
    let syncedCount: Int
    let alreadyExisted: Int
    var newlyUnlocked: [NewlyUnlockedAchievement] = []

    enum CodingKeys: String, CodingKey {
        case syncedCount = "synced_count"
        case alreadyExisted = "already_existed"
        case newlyUnlocked = "newly_unlocked"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        syncedCount = try container.decode(Int.self, forKey: .syncedCount)
        alreadyExisted = try container.decode(Int.self, forKey: .alreadyExisted)
        newlyUnlocked = (try? container.decode([NewlyUnlockedAchievement].self, forKey: .newlyUnlocked)) ?? []
    }
}
