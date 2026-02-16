import Foundation
import SwiftUI

@MainActor
class TeamsViewModel: ObservableObject {
    @Published var teams: [TeamResponse] = []
    @Published var teamDetail: TeamDetailResponse?
    @Published var isLoading = false
    @Published var isLoadingDetail = false
    @Published var error: String?

    private let apiService = APIService.shared

    func loadMyTeams() {
        isLoading = true
        error = nil

        Task {
            do {
                teams = try await apiService.fetchMyTeams()
                isLoading = false
            } catch {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    func createTeam(name: String, description: String?) {
        isLoading = true

        Task {
            do {
                let newTeam = try await apiService.createTeam(name: name, description: description)
                teams.insert(newTeam, at: 0)
                isLoading = false
            } catch {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    func joinTeam(inviteCode: String) {
        isLoading = true

        Task {
            do {
                let team = try await apiService.joinTeam(inviteCode: inviteCode)
                teams.insert(team, at: 0)
                isLoading = false
            } catch {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    func leaveTeam(teamId: String) {
        Task {
            do {
                try await apiService.leaveTeam(teamId: teamId)
                teams.removeAll { $0.id == teamId }
                teamDetail = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func loadDetail(teamId: String) {
        isLoadingDetail = true

        Task {
            do {
                teamDetail = try await apiService.fetchTeamDetail(teamId: teamId)
                isLoadingDetail = false
            } catch {
                self.error = error.localizedDescription
                isLoadingDetail = false
            }
        }
    }
}
