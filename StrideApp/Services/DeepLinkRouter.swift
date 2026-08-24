import Foundation
import SwiftUI

/// Custom URL scheme deep-link router for stride:// URLs.
///
/// Push notifications carry a `deep_link` field in their payload (set by
/// `app/services/push_service.py`). When the user taps the notification,
/// `PushNotificationManager` parses the URL and forwards it here. Views
/// observe `pendingLink` and consume it (set to nil after handling).
///
/// Routes (set up in v2 plan §Phase 0):
///   stride://coach/inbox
///   stride://coach/weekly-review/{event_id}
///   stride://coach/adjustment/{adjustment_id}
///   stride://coach/chat?event_id={id}
///   stride://coach/post-run/{event_id}
///   stride://coach/streak/{event_id}
///   stride://coach/red-flag/{event_id}
///   stride://wellness/checkin
///   stride://run/{run_id}
///   stride://nutrition/log
///   stride://race-prep/checklist/{event_id}
///   stride://race-prep/review/{event_id}
///   stride://garmin/connected
@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()

    @Published private(set) var pendingLink: DeepLink?

    private init() {}

    /// Called by PushNotificationManager (or onOpenURL) when a stride:// URL arrives.
    func handle(url: URL) {
        guard url.scheme == "stride" else { return }
        guard let link = DeepLink(url: url) else {
            #if DEBUG
            print("DeepLinkRouter: unknown URL \(url)")
            #endif
            return
        }
        pendingLink = link
    }

    /// Views call this after navigating to the link target so we don't re-fire.
    func consume() {
        pendingLink = nil
    }
}

/// Parsed representation of a stride:// URL.
enum DeepLink: Equatable {
    case coachInbox
    case coachCheckin(checkinId: String)
    case coachWeeklyReview(eventId: String)
    case coachAdjustment(adjustmentId: String)
    case coachChat(relatedEventId: String?)
    case coachPostRun(eventId: String)
    case coachStreak(eventId: String)
    case coachRedFlag(eventId: String)
    case wellnessCheckin
    case runDetail(runId: String)
    case nutritionLog
    case racePrepChecklist(eventId: String)
    case racePrepReview(eventId: String)
    case garminConnected
    case fitbitConnected
    case unknown(host: String, path: String)

    init?(url: URL) {
        guard url.scheme == "stride" else { return nil }
        // Treat host + path as the route. Examples:
        //   stride://coach/inbox  → host "coach", path "/inbox"
        //   stride://coach/weekly-review/abc → host "coach", path "/weekly-review/abc"
        let host = url.host ?? ""
        let segments = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "coach":
            switch segments.first {
            case "inbox" where segments.count == 1:
                self = .coachInbox
            case "checkin" where segments.count == 2:
                self = .coachCheckin(checkinId: segments[1])
            case "weekly-review" where segments.count == 2:
                self = .coachWeeklyReview(eventId: segments[1])
            case "adjustment" where segments.count == 2:
                self = .coachAdjustment(adjustmentId: segments[1])
            case "chat" where segments.count == 1:
                let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let related = comps?.queryItems?.first(where: { $0.name == "event_id" })?.value
                self = .coachChat(relatedEventId: related)
            case "post-run" where segments.count == 2:
                self = .coachPostRun(eventId: segments[1])
            case "streak" where segments.count == 2:
                self = .coachStreak(eventId: segments[1])
            case "red-flag" where segments.count == 2:
                self = .coachRedFlag(eventId: segments[1])
            default:
                self = .unknown(host: host, path: segments.joined(separator: "/"))
            }
        case "wellness":
            if segments == ["checkin"] {
                self = .wellnessCheckin
            } else {
                self = .unknown(host: host, path: segments.joined(separator: "/"))
            }
        case "run":
            if segments.count == 1 {
                self = .runDetail(runId: segments[0])
            } else {
                self = .unknown(host: host, path: segments.joined(separator: "/"))
            }
        case "nutrition":
            if segments == ["log"] {
                self = .nutritionLog
            } else {
                self = .unknown(host: host, path: segments.joined(separator: "/"))
            }
        case "race-prep":
            switch segments.first {
            case "checklist" where segments.count == 2:
                self = .racePrepChecklist(eventId: segments[1])
            case "review" where segments.count == 2:
                self = .racePrepReview(eventId: segments[1])
            default:
                self = .unknown(host: host, path: segments.joined(separator: "/"))
            }
        case "garmin":
            if segments == ["connected"] {
                self = .garminConnected
            } else {
                self = .unknown(host: host, path: segments.joined(separator: "/"))
            }
        case "fitbit":
            if segments == ["connected"] {
                self = .fitbitConnected
            } else {
                self = .unknown(host: host, path: segments.joined(separator: "/"))
            }
        default:
            self = .unknown(host: host, path: segments.joined(separator: "/"))
        }
    }
}
