import SwiftUI

/// Surfaces the immediate coach response when a check-in trips a concern flag.
/// Streams the body via the same /api/coach/get-or-stream-review/{event_id}
/// SSE replay endpoint used by WeeklyReviewCardView.
///
/// Routed from the wellness check-in submit flow when `is_serious` is true
/// (push fires) or via the inbox row otherwise.
struct WellnessConcernView: View {
    let eventId: UUID

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: WeeklyReviewViewModel

    init(eventId: UUID) {
        self.eventId = eventId
        _viewModel = StateObject(wrappedValue: WeeklyReviewViewModel(eventId: eventId))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    bodySection
                    feedbackSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .navigationTitle("Quick check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await viewModel.start() }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("From your coach")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
    }

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let err = viewModel.loadFailed {
                Text(err).font(.callout).foregroundStyle(.red)
                Button("Retry") { Task { await viewModel.start() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.stridePrimary)
            } else if viewModel.streamedText.isEmpty && viewModel.isStreaming {
                shimmer
            } else {
                StreamingTextView(text: viewModel.streamedText, isStreaming: viewModel.isStreaming)
            }
        }
    }

    private var shimmer: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<3) { _ in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 14)
            }
        }
        .redacted(reason: .placeholder)
    }

    private var feedbackSection: some View {
        CoachFeedbackRow(eventId: eventId, loopName: "wellness")
    }
}
