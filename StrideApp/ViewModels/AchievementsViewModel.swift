import Foundation
import SwiftUI

@MainActor
class AchievementsViewModel: ObservableObject {
    @Published var definitions: [AchievementDefinition] = []
    @Published var unlocked: [UserAchievement] = []
    @Published var streak: UserStreakResponse?
    @Published var unnotifiedAchievements: [UserAchievement] = []
    @Published var isLoading = false
    @Published var showUnlockedSheet = false

    private let apiService = APIService.shared
    private var unlockedIds: Set<String> = []

    // MARK: - Computed

    var groupedByCategory: [(String, [AchievementDefinition])] {
        let categories: [AchievementCategory] = [.milestone, .distance, .streak, .performance]
        return categories.compactMap { cat in
            let items = definitions.filter { $0.category == cat.rawValue }
            return items.isEmpty ? nil : (cat.displayName, items)
        }
    }

    func isUnlocked(_ defn: AchievementDefinition) -> Bool {
        unlockedIds.contains(defn.id)
    }

    func unlockedDate(for defn: AchievementDefinition) -> String? {
        guard let ua = unlocked.first(where: { $0.achievementId == defn.id }) else { return nil }
        // Parse ISO date and format nicely
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = isoFormatter.date(from: ua.unlockedAt) else {
            // Try without fractional seconds
            isoFormatter.formatOptions = [.withInternetDateTime]
            guard let date = isoFormatter.date(from: ua.unlockedAt) else { return nil }
            return formatDate(date)
        }
        return formatDate(date)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    // MARK: - Progress for locked achievements

    func progress(for defn: AchievementDefinition) -> Double? {
        // Only show progress for distance and streak categories
        guard let cat = AchievementCategory(rawValue: defn.category) else { return nil }
        switch cat {
        case .distance:
            // We'd need lifetime km — not available here without another endpoint
            return nil
        case .streak:
            guard let streak else { return nil }
            let current = Double(streak.longestStreakDays)
            return min(current / Double(defn.threshold), 1.0)
        default:
            return nil
        }
    }

    // MARK: - Load Data

    func loadAll() {
        guard !isLoading else { return }
        isLoading = true

        Task {
            do {
                async let defsTask = apiService.fetchAchievementDefinitions()
                async let mineTask = apiService.fetchMyAchievements()
                async let streakTask = apiService.fetchStreak()

                let (defs, mine, streakResp) = try await (defsTask, mineTask, streakTask)
                definitions = defs
                unlocked = mine
                streak = streakResp
                unlockedIds = Set(mine.map { $0.achievementId })
                isLoading = false
            } catch {
                isLoading = false
            }
        }
    }

    func checkUnnotified() {
        Task {
            do {
                let unnotified = try await apiService.fetchUnnotifiedAchievements()
                if !unnotified.isEmpty {
                    unnotifiedAchievements = unnotified
                    showUnlockedSheet = true
                }
            } catch {
                // Silently fail — not critical
            }
        }
    }

    func markNotified() {
        let ids = unnotifiedAchievements.map { $0.achievementId }
        guard !ids.isEmpty else { return }

        Task {
            try? await apiService.markAchievementsNotified(ids: ids)
            unnotifiedAchievements = []
        }
    }
}
