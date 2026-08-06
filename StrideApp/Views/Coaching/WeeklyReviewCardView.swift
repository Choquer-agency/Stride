import SwiftUI

/// Full-screen sheet for the Sunday weekly review (and Phase 7's monthly block review).
///
/// Surfaced from `stride://coach/weekly-review/{event_id}` and
/// `stride://coach/block-review/{event_id}` deep links and from the Coach inbox.
/// Streams the review body via the SSE replay endpoint, surfaces parsed focuses,
/// and shows an adjustment-proposal card when the LLM emitted one.
///
/// Phase 7: pass `kind: .block` to render block-review styling (different
/// header copy + emphasis on multi-week framing).
struct WeeklyReviewCardView: View {
    let eventId: UUID

    /// Distinguishes weekly vs block reviews — same backend stream, different chrome.
    enum ReviewKind {
        case weekly, block
    }

    let kind: ReviewKind

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: WeeklyReviewViewModel

    init(eventId: UUID, kind: ReviewKind = .weekly, focuses: [String] = [], adjustmentSummary: String? = nil) {
        self.eventId = eventId
        self.kind = kind
        let vm = WeeklyReviewViewModel(eventId: eventId)
        _viewModel = StateObject(wrappedValue: vm)
        // Defer focuses/adjustment apply until after init via .task so we don't
        // touch StateObject during init.
        self._initialFocuses = State(initialValue: focuses)
        self._initialAdjustment = State(initialValue: adjustmentSummary)
    }

    @State private var initialFocuses: [String]
    @State private var initialAdjustment: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    bodySection
                    if !viewModel.focuses.isEmpty {
                        focusesSection
                    }
                    if let summary = viewModel.adjustmentSummary {
                        adjustmentCard(summary: summary)
                    }
                    feedbackSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .navigationTitle(kind == .block ? "Block review" : "This week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            viewModel.apply(focuses: initialFocuses, adjustmentSummary: initialAdjustment)
            await viewModel.start()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(weekHeaderText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(kind == .block ? "Block review" : "Coach review")
                .font(.system(size: 28, weight: .bold))
        }
    }

    private var weekHeaderText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        let now = Date()
        // Block reviews look back 6 weeks; weekly reviews look back 6 days.
        let daysBack = kind == .block ? -42 : -6
        let start = Calendar.current.date(byAdding: .day, value: daysBack, to: now) ?? now
        let prefix = kind == .block ? "Last 6 weeks" : "Week of"
        return "\(prefix) — \(formatter.string(from: start)) – \(formatter.string(from: now))"
    }

    // MARK: - Body

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let err = viewModel.loadFailed {
                Text(err)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.vertical, 12)
                Button("Retry") { Task { await viewModel.start() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.stridePrimary)
            } else if viewModel.streamedText.isEmpty && viewModel.isStreaming {
                placeholderShimmer
            } else {
                StreamingTextView(text: viewModel.streamedText, isStreaming: viewModel.isStreaming)
            }
        }
    }

    private var placeholderShimmer: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<4) { _ in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 14)
            }
        }
        .redacted(reason: .placeholder)
    }

    // MARK: - Focuses

    private var focusesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This week, focus on")
                .font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.focuses, id: \.self) { focus in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "target")
                            .foregroundStyle(Color.stridePrimary)
                        Text(focus)
                            .font(.callout)
                            .foregroundStyle(.primary)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.stridePrimary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    // MARK: - Adjustment proposal

    private func adjustmentCard(summary: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(Color.stridePrimary)
                Text("Coach proposes a change")
                    .font(.headline)
            }
            Text(summary)
                .font(.callout)
                .foregroundStyle(.primary)
            // Phase 3 wires Accept/Reject → AdjustmentReviewSheet.
            // For Phase 2 we just surface the summary so the athlete sees it.
            HStack {
                Button(action: {}) {
                    Text("Review")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.stridePrimary)
                .disabled(true) // enabled in Phase 3
            }
        }
        .padding(16)
        .background(Color.gray.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Feedback

    private var feedbackSection: some View {
        CoachFeedbackRow(eventId: eventId, loopName: "weekly_review")
    }
}
