import Foundation

// MARK: - Leaderboard Type

enum LeaderboardType: String, CaseIterable {
    case distance = "Distance"
    case fiveK = "5K"
    case tenK = "10K"
    case halfMarathon = "HM"
    case marathon = "FM"
    case ultra = "50K"

    var isDistanceBased: Bool { self == .distance }

    /// API category param for best-time leaderboards
    var categoryParam: String { rawValue }
}

// MARK: - Leaderboard Filter

enum LeaderboardFilter: String, CaseIterable {
    case all = "All"
    case men = "Men"
    case women = "Women"
    case myAgeGroup = "My Age"

    var genderParam: String? {
        switch self {
        case .men: return "male"
        case .women: return "female"
        default: return nil
        }
    }

    var isAgeGroup: Bool { self == .myAgeGroup }
}

// MARK: - API Response Models

struct LeaderboardEntry: Codable, Identifiable {
    let rank: Int
    let userId: String
    let displayName: String
    let profilePhotoBase64: String?
    let value: Double

    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case rank
        case userId = "user_id"
        case displayName = "display_name"
        case profilePhotoBase64 = "profile_photo_base64"
        case value
    }

    /// Format value for display based on leaderboard type
    func formattedValue(isDistance: Bool) -> String {
        if isDistance {
            return "\(Int(value)) km"
        } else {
            // Time in seconds → H:MM:SS or M:SS
            let totalSeconds = Int(value)
            let h = totalSeconds / 3600
            let m = (totalSeconds % 3600) / 60
            let s = totalSeconds % 60
            if h > 0 {
                return String(format: "%d:%02d:%02d", h, m, s)
            }
            return String(format: "%d:%02d", m, s)
        }
    }
}

struct LeaderboardResponse: Codable {
    let entries: [LeaderboardEntry]
    let yourRank: Int?
    let yourValue: Double?
    let totalParticipants: Int

    enum CodingKeys: String, CodingKey {
        case entries
        case yourRank = "your_rank"
        case yourValue = "your_value"
        case totalParticipants = "total_participants"
    }
}
