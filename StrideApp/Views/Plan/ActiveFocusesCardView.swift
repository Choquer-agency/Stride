import SwiftUI

/// Pinned "this week, focus on:" card at the top of the Plan tab.
///
/// Reads the most recent weekly_review event from the inbox and surfaces its
/// `summary` line as a focus chip. (Phase 2 keeps focuses inside the review's
/// llm_output text — Phase 5+ will expose them as a structured field on the
/// inbox response so we can render multiple chips precisely.)
struct ActiveFocusesCardView: View {
    @StateObject private var viewModel = ActiveFocusesViewModel()
    @State private var showingReview: UUID?

    var body: some View {
        Group {
            if viewModel.hasFocuses {
                contentCard
            } else {
                EmptyView()
            }
        }
        .task { await viewModel.refresh() }
        .sheet(item: Binding(
            get: { showingReview.map { IdentifiableUUIDFocus(id: $0) } },
            set: { showingReview = $0?.id }
        )) { wrap in
            WeeklyReviewCardView(eventId: wrap.id)
        }
    }

    private var contentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .foregroundStyle(Color.stridePrimary)
                Text("This week, focus on")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if let eventId = viewModel.latestReviewEventId {
                    Button {
                        showingReview = eventId
                    } label: {
                        Text("Open")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.stridePrimary)
                    }
                }
            }

            // Phase 2 v1: render the review's first line as the focus.
            // Phase 2.1 will surface explicit focuses[] on the inbox row.
            ForEach(viewModel.focusesPreview, id: \.self) { focus in
                Text(focus)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.stridePrimary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }
}

// MARK: - View model

@MainActor
private final class ActiveFocusesViewModel: ObservableObject {
    @Published private(set) var focusesPreview: [String] = []
    @Published private(set) var latestReviewEventId: UUID?

    var hasFocuses: Bool { !focusesPreview.isEmpty }

    func refresh() async {
        do {
            let inbox = try await APIService.shared.fetchCoachingInbox(limit: 10)
            // Find most recent weekly_review with a summary
            if let review = inbox.first(where: { $0.eventType == "weekly_review" && $0.summary != nil }) {
                self.latestReviewEventId = review.id
                if let summary = review.summary {
                    // Render the first 1–2 sentences as the focus preview
                    let firstLine = summary
                        .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
                        .first
                        .map(String.init) ?? summary
                    self.focusesPreview = [firstLine.trimmingCharacters(in: .whitespacesAndNewlines)]
                }
            } else {
                self.focusesPreview = []
                self.latestReviewEventId = nil
            }
        } catch {
            // Silent — the card just won't appear if the fetch fails
            self.focusesPreview = []
        }
    }
}

private struct IdentifiableUUIDFocus: Identifiable {
    let id: UUID
}
