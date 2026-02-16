import Foundation
import SwiftUI

@MainActor
class ChallengesViewModel: ObservableObject {
    @Published var activeChallenges: [ChallengeResponse] = []
    @Published var isLoading = false
    @Published var error: String?

    // Detail
    @Published var detail: ChallengeDetailResponse?
    @Published var isLoadingDetail = false
    @Published var isJoining = false

    private let apiService = APIService.shared

    func loadActiveChallenges() {
        isLoading = true
        error = nil

        Task {
            do {
                let challenges = try await apiService.fetchChallenges(status: "active")
                activeChallenges = challenges
                isLoading = false
            } catch {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    func loadDetail(challengeId: String) {
        isLoadingDetail = true

        Task {
            do {
                detail = try await apiService.fetchChallengeDetail(id: challengeId)
                isLoadingDetail = false
            } catch {
                self.error = error.localizedDescription
                isLoadingDetail = false
            }
        }
    }

    func joinChallenge(id: String) {
        isJoining = true

        Task {
            do {
                _ = try await apiService.joinChallenge(id: id)
                // Reload detail to reflect joined state
                loadDetail(challengeId: id)
                // Also refresh the list
                loadActiveChallenges()
                isJoining = false
            } catch {
                self.error = error.localizedDescription
                isJoining = false
            }
        }
    }
}
