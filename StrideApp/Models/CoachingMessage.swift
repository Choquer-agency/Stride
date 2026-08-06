import Foundation
import SwiftData

/// Local SwiftData mirror of recent coaching events for offline display + read state.
///
/// The full event data lives on the backend in `coaching_events`; this is just enough
/// to render the inbox without a network round-trip and to track per-device read state.
/// Synced from `GET /api/coach/inbox` on app foreground.
///
/// Schema version 1 — Phase 0. Phase 5 (chat) will add ChatMessage as a sibling model.
@Model
final class CoachingMessage {
    /// Server-assigned coaching_event UUID (string form for SwiftData primary key).
    @Attribute(.unique) var id: String

    /// e.g. "weekly_review" | "post_run_check" | "red_flag" | "consolidation" | …
    var eventType: String

    /// Short title for inbox row (e.g. "Weekly review · 38km").
    var title: String

    /// First ~200 chars of the LLM output, for inbox preview. Full body is fetched on tap.
    var summary: String?

    /// When the event was generated server-side.
    var receivedAt: Date

    /// Local read state. Nil until the user taps the inbox row.
    var readAt: Date?

    /// Has the user submitted 👍 / 👎 / 🙏 feedback for this event yet?
    /// Tracked locally so the CoachFeedbackRow disappears immediately on tap
    /// (server `coaching_feedback_seen` updates lazily).
    var feedbackGiven: Bool

    /// Did the backend mark notification_delivered=true? (Display badge in inbox.)
    var notificationDelivered: Bool

    /// Optional: deep link target for tap action (set by event-type-aware code).
    var deepLink: String?

    /// Optional: associated plan_adjustment.id, if this event proposed an adjustment.
    var relatedAdjustmentId: String?

    init(
        id: String,
        eventType: String,
        title: String,
        summary: String?,
        receivedAt: Date,
        readAt: Date? = nil,
        feedbackGiven: Bool = false,
        notificationDelivered: Bool = false,
        deepLink: String? = nil,
        relatedAdjustmentId: String? = nil
    ) {
        self.id = id
        self.eventType = eventType
        self.title = title
        self.summary = summary
        self.receivedAt = receivedAt
        self.readAt = readAt
        self.feedbackGiven = feedbackGiven
        self.notificationDelivered = notificationDelivered
        self.deepLink = deepLink
        self.relatedAdjustmentId = relatedAdjustmentId
    }
}
