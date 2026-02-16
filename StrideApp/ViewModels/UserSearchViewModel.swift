import Foundation
import SwiftUI

@MainActor
class UserSearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var results: [UserSearchResult] = []
    @Published var isLoading = false
    @Published var error: String?

    private let apiService = APIService.shared
    private var searchTask: Task<Void, Never>?

    func search() {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            return
        }

        searchTask = Task {
            isLoading = true
            do {
                results = try await apiService.searchUsers(query: trimmed)
                isLoading = false
            } catch {
                if !Task.isCancelled {
                    self.error = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    func toggleFollow(userId: String) {
        guard let index = results.firstIndex(where: { $0.id == userId }) else { return }
        let isCurrentlyFollowing = results[index].isFollowing

        // Optimistic update
        results[index].isFollowing = !isCurrentlyFollowing

        Task {
            do {
                if isCurrentlyFollowing {
                    try await apiService.unfollowUser(userId: userId)
                } else {
                    try await apiService.followUser(userId: userId)
                }
            } catch {
                // Revert on failure
                if let idx = results.firstIndex(where: { $0.id == userId }) {
                    results[idx].isFollowing = isCurrentlyFollowing
                }
            }
        }
    }
}
