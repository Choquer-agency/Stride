import Foundation
import SwiftUI

@MainActor
class ActivityFeedViewModel: ObservableObject {
    @Published var items: [ActivityFeedItem] = []
    @Published var isLoading = false
    @Published var followingOnly = true
    @Published var error: String?

    private let apiService = APIService.shared
    private var offset = 0
    private let pageSize = 20

    func loadFeed() {
        offset = 0
        isLoading = true
        error = nil

        Task {
            do {
                items = try await apiService.fetchActivityFeed(
                    followingOnly: followingOnly, limit: pageSize, offset: 0
                )
                offset = items.count
                isLoading = false
            } catch {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    func loadMore() {
        guard !isLoading else { return }
        isLoading = true

        Task {
            do {
                let more = try await apiService.fetchActivityFeed(
                    followingOnly: followingOnly, limit: pageSize, offset: offset
                )
                items.append(contentsOf: more)
                offset += more.count
                isLoading = false
            } catch {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }
}
