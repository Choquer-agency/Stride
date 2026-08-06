import SwiftUI

/// Auto-dismissing celebration sheet for consolidation events.
/// Surfaced from `stride://coach/streak/{event_id}` push deep links.
/// Auto-dismisses after 5s; tap "Inbox" or anywhere outside to dismiss earlier.
struct StreakCelebrationView: View {
    let eventId: UUID

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: WeeklyReviewViewModel

    init(eventId: UUID) {
        self.eventId = eventId
        _viewModel = StateObject(wrappedValue: WeeklyReviewViewModel(eventId: eventId))
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "bolt.heart.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.stridePrimary)
                .symbolEffect(.bounce, value: viewModel.streamedText)

            Text("Locked in")
                .font(.title.weight(.bold))

            if !viewModel.streamedText.isEmpty {
                Text(viewModel.streamedText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .lineSpacing(3)
            } else if viewModel.isStreaming {
                ProgressView().controlSize(.small)
            }

            Spacer()

            Button("Done") { dismiss() }
                .font(.headline)
                .foregroundStyle(Color.stridePrimary)
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .task {
            await viewModel.start()
            // Auto-dismiss after 5s of being on-screen with content
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            dismiss()
        }
    }
}
