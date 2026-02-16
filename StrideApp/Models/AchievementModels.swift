import Foundation

// MARK: - Achievement Definition

struct AchievementDefinition: Codable, Identifiable {
    let id: String
    let category: String
    let title: String
    let description: String
    let icon: String
    let threshold: Int
    let tier: String
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, category, title, description, icon, threshold, tier
        case sortOrder = "sort_order"
    }
}

// MARK: - User Achievement (unlocked)

struct UserAchievement: Codable, Identifiable {
    let achievementId: String
    let unlockedAt: String
    let runId: String?
    let category: String?
    let title: String?
    let description: String?
    let icon: String?
    let tier: String?

    var id: String { achievementId }

    enum CodingKeys: String, CodingKey {
        case achievementId = "achievement_id"
        case unlockedAt = "unlocked_at"
        case runId = "run_id"
        case category, title, description, icon, tier
    }
}

// MARK: - Newly Unlocked (from sync response)

struct NewlyUnlockedAchievement: Codable, Identifiable {
    let id: String
    let category: String
    let title: String
    let description: String
    let icon: String
    let tier: String
}

// MARK: - Streak

struct UserStreakResponse: Codable {
    let currentStreakDays: Int
    let longestStreakDays: Int
    let lastRunDate: String?

    enum CodingKeys: String, CodingKey {
        case currentStreakDays = "current_streak_days"
        case longestStreakDays = "longest_streak_days"
        case lastRunDate = "last_run_date"
    }
}

// MARK: - Achievement Tier

enum AchievementTier: String {
    case bronze, silver, gold, platinum

    var color: String {
        switch self {
        case .bronze: return "CD7F32"
        case .silver: return "C0C0C0"
        case .gold: return "FFD700"
        case .platinum: return "B9F2FF"
        }
    }

    var sortIndex: Int {
        switch self {
        case .bronze: return 0
        case .silver: return 1
        case .gold: return 2
        case .platinum: return 3
        }
    }
}

// MARK: - Achievement Category

enum AchievementCategory: String {
    case distance, streak, performance, milestone

    var displayName: String {
        switch self {
        case .distance: return "Distance"
        case .streak: return "Streaks"
        case .performance: return "Performance"
        case .milestone: return "Milestones"
        }
    }

    var icon: String {
        switch self {
        case .distance: return "figure.run"
        case .streak: return "flame.fill"
        case .performance: return "bolt.fill"
        case .milestone: return "star.fill"
        }
    }
}

// MARK: - Mark Notified Request

struct AchievementMarkNotifiedRequest: Codable {
    let achievementIds: [String]

    enum CodingKeys: String, CodingKey {
        case achievementIds = "achievement_ids"
    }
}
