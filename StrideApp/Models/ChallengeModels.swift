import Foundation

// MARK: - Challenge Response

struct ChallengeResponse: Codable, Identifiable {
    let id: String
    let title: String
    let challengeType: String
    let distanceCategory: String?
    let cumulativeTargetKm: Double?
    let startsAt: String
    let endsAt: String
    let participantCount: Int
    let isJoined: Bool
    let yourBestTimeSeconds: Int?
    let yourTotalDistanceKm: Double?

    enum CodingKeys: String, CodingKey {
        case id, title
        case challengeType = "challenge_type"
        case distanceCategory = "distance_category"
        case cumulativeTargetKm = "cumulative_target_km"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case participantCount = "participant_count"
        case isJoined = "is_joined"
        case yourBestTimeSeconds = "your_best_time_seconds"
        case yourTotalDistanceKm = "your_total_distance_km"
    }

    var isRace: Bool { challengeType == "weekly_race" }

    var typeLabel: String {
        switch challengeType {
        case "weekly_race": return "Weekly Race"
        case "monthly_distance": return "Monthly"
        default: return "Challenge"
        }
    }

    var typeIcon: String {
        isRace ? "flag.checkered" : "figure.run"
    }

    var parsedStartDate: Date? {
        ISO8601DateFormatter().date(from: startsAt)
    }

    var parsedEndDate: Date? {
        ISO8601DateFormatter().date(from: endsAt)
    }

    var timeRemaining: String {
        guard let endDate = parsedEndDate else { return "" }
        let now = Date()
        if endDate < now { return "Ended" }

        let components = Calendar.current.dateComponents([.day, .hour, .minute], from: now, to: endDate)
        if let days = components.day, days > 0 {
            return "\(days)d \(components.hour ?? 0)h left"
        }
        if let hours = components.hour, hours > 0 {
            return "\(hours)h \(components.minute ?? 0)m left"
        }
        return "\(components.minute ?? 0)m left"
    }

    var formattedYourResult: String? {
        if isRace, let seconds = yourBestTimeSeconds {
            return formatTime(seconds: seconds)
        } else if let km = yourTotalDistanceKm {
            return String(format: "%.1f km", km)
        }
        return nil
    }

    var distanceProgress: Double? {
        guard let target = cumulativeTargetKm, target > 0, let current = yourTotalDistanceKm else { return nil }
        return min(current / target, 1.0)
    }
}

// MARK: - Challenge Detail Response

struct ChallengeDetailResponse: Codable {
    let id: String
    let title: String
    let challengeType: String
    let distanceCategory: String?
    let cumulativeTargetKm: Double?
    let startsAt: String
    let endsAt: String
    let participantCount: Int
    let isJoined: Bool
    let yourBestTimeSeconds: Int?
    let yourTotalDistanceKm: Double?
    let leaderboard: [LeaderboardEntry]

    enum CodingKeys: String, CodingKey {
        case id, title, leaderboard
        case challengeType = "challenge_type"
        case distanceCategory = "distance_category"
        case cumulativeTargetKm = "cumulative_target_km"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case participantCount = "participant_count"
        case isJoined = "is_joined"
        case yourBestTimeSeconds = "your_best_time_seconds"
        case yourTotalDistanceKm = "your_total_distance_km"
    }

    var isRace: Bool { challengeType == "weekly_race" }

    var parsedEndDate: Date? {
        ISO8601DateFormatter().date(from: endsAt)
    }

    var timeRemaining: String {
        guard let endDate = parsedEndDate else { return "" }
        let now = Date()
        if endDate < now { return "Ended" }
        let components = Calendar.current.dateComponents([.day, .hour, .minute], from: now, to: endDate)
        if let days = components.day, days > 0 {
            return "\(days)d \(components.hour ?? 0)h left"
        }
        if let hours = components.hour, hours > 0 {
            return "\(hours)h \(components.minute ?? 0)m left"
        }
        return "\(components.minute ?? 0)m left"
    }
}

// MARK: - Join Response

struct JoinChallengeResponse: Codable {
    let joined: Bool
}

// MARK: - Helpers

func formatTime(seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    }
    return String(format: "%d:%02d", m, s)
}
