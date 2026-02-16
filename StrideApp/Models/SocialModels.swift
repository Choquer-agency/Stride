import Foundation

// MARK: - User Search Result

struct UserSearchResult: Codable, Identifiable {
    let id: String
    let displayName: String
    let profilePhotoBase64: String?
    let bio: String?
    var isFollowing: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case profilePhotoBase64 = "profile_photo_base64"
        case bio
        case isFollowing = "is_following"
    }
}

// MARK: - User Profile Response

struct UserProfileResponse: Codable {
    let id: String
    let displayName: String
    let profilePhotoBase64: String?
    let bio: String?
    var isFollowing: Bool
    let followerCount: Int
    let followingCount: Int
    let totalDistanceKm: Double
    let totalRuns: Int
    let recentActivities: [ActivityFeedItem]

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case profilePhotoBase64 = "profile_photo_base64"
        case bio
        case isFollowing = "is_following"
        case followerCount = "follower_count"
        case followingCount = "following_count"
        case totalDistanceKm = "total_distance_km"
        case totalRuns = "total_runs"
        case recentActivities = "recent_activities"
    }
}

// MARK: - Activity Feed Item

struct ActivityFeedItem: Codable, Identifiable {
    let id: String
    let userId: String
    let displayName: String
    let profilePhotoBase64: String?
    let activityType: String
    let activityData: [String: AnyCodableValue]
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case displayName = "display_name"
        case profilePhotoBase64 = "profile_photo_base64"
        case activityType = "activity_type"
        case activityData = "activity_data"
        case createdAt = "created_at"
    }

    var parsedDate: Date? {
        ISO8601DateFormatter().date(from: createdAt)
    }

    var timeAgo: String {
        guard let date = parsedDate else { return "" }
        let components = Calendar.current.dateComponents([.day, .hour, .minute], from: date, to: Date())
        if let days = components.day, days > 0 {
            return days == 1 ? "1d ago" : "\(days)d ago"
        }
        if let hours = components.hour, hours > 0 {
            return hours == 1 ? "1h ago" : "\(hours)h ago"
        }
        if let minutes = components.minute, minutes > 0 {
            return minutes == 1 ? "1m ago" : "\(minutes)m ago"
        }
        return "just now"
    }

    var activityDescription: String {
        switch activityType {
        case "run":
            let distance = activityData["distance_km"]?.doubleValue ?? 0
            let duration = activityData["duration_seconds"]?.doubleValue ?? 0
            let minutes = Int(duration) / 60
            return "Ran \(String(format: "%.1f", distance)) km in \(minutes) min"
        case "achievement":
            let title = activityData["title"]?.stringValue ?? "an achievement"
            return "Unlocked \(title)"
        case "pb":
            let category = activityData["category"]?.stringValue ?? ""
            let timeSeconds = activityData["time_seconds"]?.doubleValue ?? 0
            let minutes = Int(timeSeconds) / 60
            let seconds = Int(timeSeconds) % 60
            return "New \(category) PB: \(minutes):\(String(format: "%02d", seconds))"
        case "follow":
            return "Started following a runner"
        default:
            return "Activity"
        }
    }

    var activityIcon: String {
        switch activityType {
        case "run": return "figure.run"
        case "achievement": return "trophy.fill"
        case "pb": return "bolt.fill"
        case "follow": return "person.badge.plus"
        default: return "circle.fill"
        }
    }

    var activityColor: String {
        switch activityType {
        case "run": return "green"
        case "achievement": return "orange"
        case "pb": return "yellow"
        case "follow": return "blue"
        default: return "gray"
        }
    }
}

// MARK: - AnyCodableValue (for flexible activity_data JSON)

enum AnyCodableValue: Codable {
    case string(String)
    case double(Double)
    case int(Int)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode(Int.self) { self = .int(v); return }
        if let v = try? container.decode(Double.self) { self = .double(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if container.decodeNil() { self = .null; return }
        throw DecodingError.typeMismatch(AnyCodableValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unsupported type"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    var doubleValue: Double? {
        switch self {
        case .double(let v): return v
        case .int(let v): return Double(v)
        default: return nil
        }
    }
}

// MARK: - Team Response

struct TeamResponse: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let photoUrl: String?
    let inviteCode: String?
    let memberCount: Int
    let isMember: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case photoUrl = "photo_url"
        case inviteCode = "invite_code"
        case memberCount = "member_count"
        case isMember = "is_member"
    }
}

// MARK: - Team Member Response

struct TeamMemberResponse: Codable, Identifiable {
    var id: String { userId }
    let userId: String
    let displayName: String
    let profilePhotoBase64: String?
    let role: String
    let totalDistanceKm: Double

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case profilePhotoBase64 = "profile_photo_base64"
        case role
        case totalDistanceKm = "total_distance_km"
    }
}

// MARK: - Team Detail Response

struct TeamDetailResponse: Codable {
    let id: String
    let name: String
    let description: String?
    let photoUrl: String?
    let inviteCode: String?
    let memberCount: Int
    let isMember: Bool
    let members: [TeamMemberResponse]
    let leaderboard: [TeamMemberResponse]

    enum CodingKeys: String, CodingKey {
        case id, name, description, members, leaderboard
        case photoUrl = "photo_url"
        case inviteCode = "invite_code"
        case memberCount = "member_count"
        case isMember = "is_member"
    }
}

// MARK: - Create/Join request models

struct TeamCreateRequest: Codable {
    let name: String
    let description: String?
}

struct TeamJoinRequestBody: Codable {
    let inviteCode: String

    enum CodingKeys: String, CodingKey {
        case inviteCode = "invite_code"
    }
}
