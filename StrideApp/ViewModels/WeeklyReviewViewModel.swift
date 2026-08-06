import Foundation
import SwiftUI
import os.log

private let reviewLog = Logger(subsystem: "com.stride.app", category: "WeeklyReview")

/// Backing view model for `WeeklyReviewCardView`.
///
/// Loads the review text via the SSE replay endpoint, exposes streaming state
/// for the body view, and surfaces parsed focuses + adjustment proposal so the
/// card can render them in dedicated sections.
@MainActor
final class WeeklyReviewViewModel: ObservableObject {
    let eventId: UUID

    @Published private(set) var streamedText: String = ""
    @Published private(set) var isStreaming: Bool = false
    @Published private(set) var loadFailed: String?
    @Published private(set) var focuses: [String] = []
    @Published private(set) var adjustmentSummary: String?
    @Published private(set) var hasMarkedRead: Bool = false

    init(eventId: UUID) {
        self.eventId = eventId
    }

    /// Begin streaming the review text from the backend. Idempotent — calling
    /// twice will reset the state and re-stream.
    func start() async {
        guard !isStreaming else { return }
        streamedText = ""
        loadFailed = nil
        isStreaming = true

        await APIService.shared.getOrStreamReview(
            eventId: eventId,
            onChunk: { [weak self] chunk in
                Task { @MainActor in
                    self?.streamedText.append(chunk)
                }
            },
            onComplete: { [weak self] full in
                Task { @MainActor in
                    self?.streamedText = full
                    self?.isStreaming = false
                    self?.parseSidecarTags(in: full)
                    await self?.markRead()
                }
            },
            onError: { [weak self] error in
                Task { @MainActor in
                    self?.isStreaming = false
                    self?.loadFailed = error.localizedDescription
                    reviewLog.error("Review stream failed: \(error.localizedDescription)")
                }
            }
        )
    }

    /// The backend strips JSON tags before sending the stream, so for Phase 2
    /// we receive clean prose. Focuses + adjustment surface from the inbox row's
    /// metadata when available — set them via `apply(focuses:adjustmentSummary:)`.
    func apply(focuses: [String], adjustmentSummary: String?) {
        self.focuses = focuses
        self.adjustmentSummary = adjustmentSummary
    }

    /// Parse any tags that may have leaked through (defensive).
    private func parseSidecarTags(in text: String) {
        // Backend already strips with focus_tracker.strip_tags before persisting,
        // but we do a permissive client-side scan in case a tag survives.
        if let focusesMatch = text.range(of: #"<focuses>\s*\[(.*?)\]\s*</focuses>"#, options: .regularExpression) {
            let body = String(text[focusesMatch])
            // Crude — only used as a fallback. Phase 5 will share a parser.
            let items = body
                .replacingOccurrences(of: "<focuses>", with: "")
                .replacingOccurrences(of: "</focuses>", with: "")
                .replacingOccurrences(of: "[", with: "")
                .replacingOccurrences(of: "]", with: "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"")) }
                .filter { !$0.isEmpty }
            if !items.isEmpty { self.focuses = items }
        }
    }

    private func markRead() async {
        guard !hasMarkedRead else { return }
        do {
            try await APIService.shared.markCoachingEventRead(eventId: eventId)
            hasMarkedRead = true
        } catch {
            reviewLog.error("markCoachingEventRead failed: \(error.localizedDescription)")
        }
    }
}
