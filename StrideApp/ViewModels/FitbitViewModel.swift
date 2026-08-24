import Foundation
import SwiftUI
import os.log

private let fitbitLog = Logger(subsystem: "com.stride.app", category: "Fitbit")

/// Backing view model for the Fitbit (Google Health API) connect flow.
/// Mirrors GarminViewModel: status polling during backfill, connect via
/// system browser, refresh + disconnect actions.
@MainActor
final class FitbitViewModel: ObservableObject {
    @Published private(set) var status: FitbitStatusDTO?
    @Published private(set) var isLoading = false
    @Published private(set) var actionInFlight = false
    @Published var error: String?

    private var pollTask: Task<Void, Never>?

    deinit {
        pollTask?.cancel()
    }

    var isConnected: Bool {
        status?.connected == true
    }

    var backfillRunning: Bool {
        (status?.backfillStatus ?? "") == "running"
    }

    var backfillProgress: Int {
        status?.backfillProgress ?? 0
    }

    func refreshStatus() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let s = try await APIService.shared.fitbitStatus()
            status = s
            if s.backfillStatus == "running" {
                startPollingIfNeeded()
            } else {
                stopPolling()
            }
        } catch {
            fitbitLog.error("fitbitStatus failed: \(error.localizedDescription)")
            self.error = "Couldn't load Fitbit status."
        }
    }

    func openConnectURL() {
        guard let url = APIService.shared.fitbitConnectURL() else {
            error = "Couldn't build Fitbit connect URL — are you signed in?"
            return
        }
        UIApplication.shared.open(url)
    }

    func disconnect() async {
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            try await APIService.shared.fitbitDisconnect()
            await refreshStatus()
        } catch {
            self.error = "Disconnect failed."
        }
    }

    func forceRefresh() async {
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            try await APIService.shared.fitbitRefresh()
            await refreshStatus()
        } catch {
            self.error = "Sync failed."
        }
    }

    private func startPollingIfNeeded() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            let deadline = Date().addingTimeInterval(300)
            while !Task.isCancelled, Date() < deadline {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self else { return }
                do {
                    let s = try await APIService.shared.fitbitStatus()
                    await MainActor.run {
                        self.status = s
                        if s.backfillStatus != "running" {
                            self.pollTask?.cancel()
                            self.pollTask = nil
                        }
                    }
                    if s.backfillStatus != "running" { break }
                } catch {
                    // Silent retry
                }
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}
