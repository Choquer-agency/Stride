import Foundation

struct RunElevationSample: Codable {
    let t: Double
    let elevationM: Double

    enum CodingKeys: String, CodingKey {
        case t
        case elevationM = "elevation_m"
    }
}

struct RunNumericSample: Codable {
    let t: Double
    let value: Double
}

struct RunMetricSplit: Codable {
    let kilometer: Int
    let pace: String
    let time: String
    let hr: Int?
    let elevationGainM: Double?
    let elevationLossM: Double?
    let elevationM: Double?

    enum CodingKeys: String, CodingKey {
        case kilometer, pace, time, hr
        case elevationGainM = "elevation_gain_m"
        case elevationLossM = "elevation_loss_m"
        case elevationM = "elevation_m"
    }
}

struct RunTreadmillMetrics: Codable {
    let device: String?
    let speedSamples: [RunSpeedSample]?
    let inclineSamples: [RunInclineSample]?

    enum CodingKeys: String, CodingKey {
        case device
        case speedSamples = "speed_samples"
        case inclineSamples = "incline_samples"
    }
}

struct RunSyncMetrics: Codable {
    let routePoints: [RoutePoint]?
    let elevationProfile: [RunElevationSample]?
    let treadmill: RunTreadmillMetrics?
    let splits: [RunMetricSplit]?
    let cadenceSamples: [RunNumericSample]?
    let powerSamples: [RunNumericSample]?
    let weather: AnyJSONDict?
    let coachNotes: String?
    let shoeName: String?
    let plannedWorkoutId: String?
    let plannedDurationMinutes: Int?
    let plannedPaceDescription: String?

    enum CodingKeys: String, CodingKey {
        case treadmill, splits, weather
        case routePoints = "route_points"
        case elevationProfile = "elevation_profile"
        case cadenceSamples = "cadence_samples"
        case powerSamples = "power_samples"
        case coachNotes = "coach_notes"
        case shoeName = "shoe_name"
        case plannedWorkoutId = "planned_workout_id"
        case plannedDurationMinutes = "planned_duration_minutes"
        case plannedPaceDescription = "planned_pace_description"
    }
}

// MARK: - Run Sync Request/Response

struct RunSyncPayload: Codable {
    let id: String
    let completedAt: String
    let distanceKm: Double
    let durationSeconds: Double
    let avgPaceSecPerKm: Double
    let kmSplitsJson: String?
    let elevationGainM: Double?
    let elevationLossM: Double?
    let metricsJson: RunSyncMetrics?
    let metricsBackfillOnly: Bool
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
    let avgHeartRate: Int?
    let maxHeartRate: Int?
    let hrSamplesJson: String?

    enum CodingKeys: String, CodingKey {
        case id
        case completedAt = "completed_at"
        case distanceKm = "distance_km"
        case durationSeconds = "duration_seconds"
        case avgPaceSecPerKm = "avg_pace_sec_per_km"
        case kmSplitsJson = "km_splits_json"
        case elevationGainM = "elevation_gain_m"
        case elevationLossM = "elevation_loss_m"
        case metricsJson = "metrics_json"
        case metricsBackfillOnly = "metrics_backfill_only"
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
        case avgHeartRate = "avg_heart_rate"
        case maxHeartRate = "max_heart_rate"
        case hrSamplesJson = "hr_samples_json"
    }
}

struct RunBatchSyncRequest: Codable {
    let runs: [RunSyncPayload]
}

struct RunBatchSyncResponse: Codable {
    let syncedCount: Int
    let alreadyExisted: Int
    let metricsStored: Bool
    var newlyUnlocked: [NewlyUnlockedAchievement] = []

    enum CodingKeys: String, CodingKey {
        case syncedCount = "synced_count"
        case alreadyExisted = "already_existed"
        case metricsStored = "metrics_stored"
        case newlyUnlocked = "newly_unlocked"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        syncedCount = try container.decode(Int.self, forKey: .syncedCount)
        alreadyExisted = try container.decode(Int.self, forKey: .alreadyExisted)
        metricsStored = (try? container.decode(Bool.self, forKey: .metricsStored)) ?? false
        newlyUnlocked = (try? container.decode([NewlyUnlockedAchievement].self, forKey: .newlyUnlocked)) ?? []
    }
}
