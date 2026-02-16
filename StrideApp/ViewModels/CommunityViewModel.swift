import Foundation
import SwiftUI

@MainActor
class CommunityViewModel: ObservableObject {
    @Published var selectedType: LeaderboardType = .distance
    @Published var selectedFilter: LeaderboardFilter = .all
    @Published var entries: [LeaderboardEntry] = []
    @Published var yourRank: Int?
    @Published var yourValue: Double?
    @Published var totalParticipants: Int = 0
    @Published var isLoading = false
    @Published var error: String?

    private let apiService = APIService.shared

    /// Compute the user's age group from their DOB for the "My Age" filter
    var userAgeGroup: String? {
        guard case .signedIn(let user) = AuthService.shared.authState,
              let dob = user.dateOfBirth, !dob.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let dobDate = formatter.date(from: dob) else { return nil }

        let age = Calendar.current.dateComponents([.year], from: dobDate, to: Date()).year ?? 0

        switch age {
        case 18...29: return "18-29"
        case 30...39: return "30-39"
        case 40...49: return "40-49"
        case 50...59: return "50-59"
        case 60...: return "60+"
        default: return nil
        }
    }

    func loadLeaderboard() {
        isLoading = true
        error = nil

        Task {
            do {
                let response = try await apiService.fetchLeaderboard(
                    type: selectedType,
                    filter: selectedFilter,
                    userAgeGroup: userAgeGroup
                )
                entries = response.entries
                yourRank = response.yourRank
                yourValue = response.yourValue
                totalParticipants = response.totalParticipants
                isLoading = false
            } catch {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }
}
