import Foundation
import AuthenticationServices
import Combine
import SwiftUI
import os.log

private let fitbitLog = Logger(subsystem: "com.stride.app", category: "Fitbit")

/// Backing view model for the Fitbit (Google Health API) connect flow.
/// Mirrors GarminViewModel: status polling during backfill, connect via
/// system browser, refresh + disconnect actions.
@MainActor
final class FitbitViewModel: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var status: FitbitStatusDTO?
    @Published private(set) var isLoading = false
    @Published private(set) var actionInFlight = false
    @Published var error: String?

    private var authSession: ASWebAuthenticationSession?
    private var authObserver: AnyCancellable?

    override init() {
        super.init()
        authObserver = AuthService.shared.$authState.sink { [weak self] _ in
            self?.authSession?.cancel()
            self?.authSession = nil
            self?.stopPolling()
            self?.status = nil
            self?.error = nil
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

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
        let owner = AuthService.shared.currentUserID
        guard owner != nil else { status = nil; return }
        isLoading = true
        defer { isLoading = false }
        do {
            let s = try await APIService.shared.fitbitStatus()
            guard owner == AuthService.shared.currentUserID else { return }
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
        let owner = AuthService.shared.currentUserID
        authSession?.cancel()
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "stride") { [weak self] callback, failure in
            Task { @MainActor in
                guard let self, owner == AuthService.shared.currentUserID else { return }
                self.authSession = nil
                guard let callback, callback.host == "fitbit", callback.path == "/connected" else {
                    if failure != nil { self.error = "Fitbit connection cancelled or failed." }
                    return
                }
                if URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "error" }) == true {
                    self.error = "Google couldn't connect Fitbit. Check your selected account and try again."
                }
                await self.refreshStatus()
            }
        }
        session.prefersEphemeralWebBrowserSession = true
        session.presentationContextProvider = self
        authSession = session
        if !session.start() {
            authSession = nil
            error = "Couldn't open Google sign in."
        }
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
        let owner = AuthService.shared.currentUserID
        pollTask = Task { [weak self] in
            let deadline = Date().addingTimeInterval(300)
            while !Task.isCancelled, Date() < deadline {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled, let self, owner == AuthService.shared.currentUserID else { return }
                do {
                    let s = try await APIService.shared.fitbitStatus()
                    await MainActor.run {
                        guard !Task.isCancelled, owner == AuthService.shared.currentUserID else { return }
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
