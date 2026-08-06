import Foundation
import SwiftData

/// Local SwiftData mirror of the backend chat_messages table.
///
/// Synced from `GET /api/coach/chat/history` on app foreground + appended
/// optimistically as the athlete types and the coach streams.
@Model
final class ChatMessage {
    @Attribute(.unique) var id: String

    /// "athlete" | "coach"
    var role: String

    var content: String
    var sentAt: Date

    /// True only for the live-streaming coach turn currently in flight.
    /// Cleared when the SSE `done` event arrives.
    var isStreaming: Bool

    /// Optional cross-references back to coaching events / plan adjustments.
    var relatedEventId: String?
    var relatedAdjustmentId: String?

    /// Plan thread this message belongs to (nil during no-plan periods).
    var trainingPlanId: String?

    init(
        id: String,
        role: String,
        content: String,
        sentAt: Date,
        isStreaming: Bool = false,
        relatedEventId: String? = nil,
        relatedAdjustmentId: String? = nil,
        trainingPlanId: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.sentAt = sentAt
        self.isStreaming = isStreaming
        self.relatedEventId = relatedEventId
        self.relatedAdjustmentId = relatedAdjustmentId
        self.trainingPlanId = trainingPlanId
    }
}

extension ChatMessage {
    /// Convenience role discriminators.
    var isAthlete: Bool { role == "athlete" }
    var isCoach: Bool { role == "coach" }
}
