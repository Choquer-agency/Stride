import SwiftUI

/// Adapts to event_type — surfaces post_run_info, post_run_check, red_flag,
/// or routes to AdjustmentReviewSheet when the response was an adjustment.
///
/// Routed from:
///   stride://coach/post-run/{event_id}      → standard styling
///   stride://coach/red-flag/{event_id}      → red accent border
///
/// Streams the body text via /api/coach/get-or-stream-review/{id} (the same
/// endpoint serves any coaching event with an llm_output) and renders an
/// optional "Reply in chat" button for check_in responses (Phase 5 wires chat).
struct PostRunCheckView: View {
    let eventId: UUID
    var isRedFlag: Bool = false

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: WeeklyReviewViewModel  // re-uses streaming logic

    init(eventId: UUID, isRedFlag: Bool = false) {
        self.eventId = eventId
        self.isRedFlag = isRedFlag
        _viewModel = StateObject(wrappedValue: WeeklyReviewViewModel(eventId: eventId))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    bodySection
                    if isRedFlag {
                        redFlagFooter
                    }
                    feedbackSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .navigationTitle(isRedFlag ? "Coach flag" : "Today's run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .background(redFlagBackground)
        }
        .task { await viewModel.start() }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isRedFlag ? "I have to flag this" : "From your coach")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isRedFlag ? Color.red : .secondary)
                .textCase(.uppercase)
        }
    }

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let err = viewModel.loadFailed {
                Text(err)
                    .font(.callout)
                    .foregroundStyle(.red)
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
            ForEach(0..<3) { _ in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 14)
            }
        }
        .redacted(reason: .placeholder)
    }

    private var redFlagFooter: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.title2)
            Text("This pattern needs your attention even if you'd planned to push through.")
                .font(.callout)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color.red.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var feedbackSection: some View {
        CoachFeedbackRow(
            eventId: eventId,
            loopName: isRedFlag ? "red_flag" : "post_run_check"
        )
    }

    @ViewBuilder
    private var redFlagBackground: some View {
        if isRedFlag {
            LinearGradient(
                colors: [Color.red.opacity(0.06), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        } else {
            EmptyView()
        }
    }
}
