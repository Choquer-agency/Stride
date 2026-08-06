import Foundation
import SwiftUI
import os.log

private let garminLog = Logger(subsystem: "com.stride.app", category: "Garmin")

/// Backing view model for the Garmin connect flow + integrations section.
///
/// Owns:
/// - latest connection status (from `GET /api/garmin/status`)
/// - backfill polling while status == "running"
/// - connect (open SFSafariView), refresh, disconnect actions
@MainActor
final class GarminViewModel: ObservableObject {
    @Published private(set) var status: GarminStatusDTO?
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
            let s = try await APIService.shared.garminStatus()
            status = s
            // Auto-poll while a backfill is running
            if s.backfillStatus == "running" {
                startPollingIfNeeded()
            } else {
                stopPolling()
            }
        } catch {
            garminLog.error("garminStatus failed: \(error.localizedDescription)")
            self.error = "Couldn't load Garmin status."
        }
    }

    func openConnectURL() {
        guard let url = APIService.shared.garminConnectURL() else {
            error = "Couldn't build Garmin connect URL — are you signed in?"
            return
        }
        UIApplication.shared.open(url)
    }

    func disconnect() async {
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            try await APIService.shared.garminDisconnect()
            await refreshStatus()
        } catch {
            self.error = "Disconnect failed."
        }
    }

    func forceRefreshGarmin() async {
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            try await APIService.shared.garminRefresh()
            await refreshStatus()
        } catch {
            self.error = "Sync failed."
        }
    }

    private func startPollingIfNeeded() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            // Poll every 3 seconds while backfill is running, max 5 minutes
            let deadline = Date().addingTimeInterval(300)
            while !Task.isCancelled, Date() < deadline {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self else { return }
                do {
                    let s = try await APIService.shared.garminStatus()
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
