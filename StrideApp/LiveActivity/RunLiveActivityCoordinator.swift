import ActivityKit
import Foundation
import OSLog

@MainActor
final class RunLiveActivityCoordinator {
    static let shared = RunLiveActivityCoordinator()

    private let logger = Logger(subsystem: "com.stride-v.2.app", category: "LiveActivity")
    private var current: Activity<StrideRunAttributes>?
    private var lastPublishedAt = Date.distantPast
    private var pendingUpdate: Task<Void, Never>?

    private init() {}

    func start(sessionID: String, title: String, isOutdoor: Bool,
               state: StrideRunAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.info("Live Activities are unavailable or disabled")
            return
        }
        if let existing = Activity<StrideRunAttributes>.activities.first(where: { $0.attributes.sessionID == sessionID }) {
            current = existing
            publish(sessionID: sessionID, state: state, force: true)
            return
        }
        let oldActivities = Activity<StrideRunAttributes>.activities
        Task {
            for old in oldActivities { await old.end(nil, dismissalPolicy: .immediate) }
        }
        do {
            let attributes = StrideRunAttributes(sessionID: sessionID, title: title, isOutdoor: isOutdoor)
            current = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(60)),
                pushType: nil
            )
            lastPublishedAt = Date()
        } catch {
            logger.error("Could not start run Live Activity: \(error.localizedDescription)")
        }
    }

    func publish(sessionID: String, state: StrideRunAttributes.ContentState, force: Bool = false) {
        guard let activity = current ?? Activity<StrideRunAttributes>.activities.first(where: { $0.attributes.sessionID == sessionID }),
              activity.attributes.sessionID == sessionID else { return }
        current = activity
        let now = Date()
        guard force || now.timeIntervalSince(lastPublishedAt) >= 5 else { return }
        lastPublishedAt = now
        let prior = pendingUpdate
        pendingUpdate = Task {
            await prior?.value
            await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(60)))
        }
    }

    func finish(sessionID: String, state: StrideRunAttributes.ContentState) {
        guard let activity = current ?? Activity<StrideRunAttributes>.activities.first(where: { $0.attributes.sessionID == sessionID }),
              activity.attributes.sessionID == sessionID else { return }
        let prior = pendingUpdate
        current = nil
        pendingUpdate = nil
        lastPublishedAt = .distantPast
        Task {
            await prior?.value
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
    }

    func endOrphanedActivities() {
        let activities = Activity<StrideRunAttributes>.activities
        guard !activities.isEmpty else { return }
        current = nil
        pendingUpdate = nil
        lastPublishedAt = .distantPast
        Task {
            for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
