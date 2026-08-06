import Foundation
import SwiftUI
import os.log

private let pauseLog = Logger(subsystem: "com.stride.app", category: "PauseCoach")

/// View model for `PauseCoachSheet` and the Run-tab pause banner.
/// Wraps /api/coach/pause, /resume, /pause-status.
@MainActor
final class PauseCoachViewModel: ObservableObject {
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var pausedUntil: Date?
    @Published private(set) var resumePending: Bool = false
    @Published private(set) var isLoading = false
    @Published private(set) var actionInFlight = false
    @Published var error: String?

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let url = URL(string: "\(APIConfiguration.serverURL)/api/coach/pause-status")!
            var request = URLRequest(url: url)
            if let token = AuthService.shared.currentToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, _) = try await URLSession.shared.data(for: request)
            struct Resp: Decodable {
                let paused: Bool
                let paused_until: String?
                let resume_pending: Bool
            }
            let resp = try JSONDecoder().decode(Resp.self, from: data)
            self.isPaused = resp.paused
            self.resumePending = resp.resume_pending
            if let s = resp.paused_until {
                self.pausedUntil = ISO8601DateFormatter().date(from: s)
            } else {
                self.pausedUntil = nil
            }
        } catch {
            pauseLog.error("refresh failed: \(error.localizedDescription)")
            self.error = "Couldn't load pause state."
        }
    }

    func pause(durationDays: Int? = nil, untilResume: Bool = false) async {
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            try await APIService.shared.pauseCoach(durationDays: durationDays, untilResume: untilResume)
            await refresh()
        } catch {
            self.error = "Couldn't pause."
        }
    }

    func resume() async {
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            try await APIService.shared.resumeCoach()
            await refresh()
        } catch {
            self.error = "Couldn't resume."
        }
    }

    var pausedUntilDescription: String? {
        guard let until = pausedUntil else { return nil }
        // If "until I resume" sentinel (set by route handler as now+100yrs), show that
        let years = Calendar.current.dateComponents([.year], from: Date(), to: until).year ?? 0
        if years > 50 {
            return "Paused until you resume"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Resumes \(formatter.localizedString(for: until, relativeTo: Date()))"
    }
}
