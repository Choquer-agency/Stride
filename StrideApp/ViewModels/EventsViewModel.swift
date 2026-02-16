import Foundation
import SwiftUI

@MainActor
class EventsViewModel: ObservableObject {
    @Published var activeEvents: [EventResponse] = []
    @Published var upcomingEvents: [EventResponse] = []
    @Published var isLoading = false
    @Published var error: String?

    // Detail
    @Published var detail: EventDetailResponse?
    @Published var isLoadingDetail = false
    @Published var isRegistering = false

    private let apiService = APIService.shared

    func loadEvents() {
        isLoading = true
        error = nil

        Task {
            do {
                async let active = apiService.fetchEvents(status: "active")
                async let upcoming = apiService.fetchEvents(status: "upcoming")

                let (activeResult, upcomingResult) = try await (active, upcoming)
                activeEvents = activeResult
                upcomingEvents = upcomingResult
                isLoading = false
            } catch {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    func loadDetail(eventId: String) {
        isLoadingDetail = true

        Task {
            do {
                detail = try await apiService.fetchEventDetail(id: eventId)
                isLoadingDetail = false
            } catch {
                self.error = error.localizedDescription
                isLoadingDetail = false
            }
        }
    }

    func register(eventId: String) {
        isRegistering = true

        Task {
            do {
                _ = try await apiService.registerForEvent(id: eventId)
                loadDetail(eventId: eventId)
                loadEvents()
                isRegistering = false
            } catch {
                self.error = error.localizedDescription
                isRegistering = false
            }
        }
    }

    func unregister(eventId: String) {
        isRegistering = true

        Task {
            do {
                _ = try await apiService.unregisterFromEvent(id: eventId)
                loadDetail(eventId: eventId)
                loadEvents()
                isRegistering = false
            } catch {
                self.error = error.localizedDescription
                isRegistering = false
            }
        }
    }
}
