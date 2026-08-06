import SwiftUI

/// Sectioned list of all coaching events. Surfaced as a card on the Plan tab
/// (or via a dedicated "Coach" navigation entry). Tap routes to the matching
/// view (WeeklyReviewCardView, AdjustmentReviewSheet in Phase 3, RaceRecapView).
struct CoachInboxView: View {
    @StateObject private var viewModel = CoachInboxViewModel()
    @State private var selectedReviewEventId: UUID?
    @State private var selectedRaceRecapEventId: UUID?
    @State private var showCheckinFlow = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView().controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.items.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Coach inbox")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
        .task { await viewModel.refresh() }
        .sheet(item: Binding(
            get: { selectedReviewEventId.map { IdentifiableUUID(id: $0) } },
            set: { selectedReviewEventId = $0?.id }
        )) { wrap in
            WeeklyReviewCardView(eventId: wrap.id)
        }
        .sheet(item: Binding(
            get: { selectedRaceRecapEventId.map { IdentifiableUUID(id: $0) } },
            set: { selectedRaceRecapEventId = $0?.id }
        )) { wrap in
            RaceRecapView(eventId: wrap.id)
        }
        .fullScreenCover(isPresented: $showCheckinFlow) {
            WeeklyCheckinFlowView()
        }
    }

    // MARK: - List

    private var list: some View {
        List {
            ForEach(viewModel.sections, id: \.title) { section in
                Section(header: Text(section.title)) {
                    ForEach(section.items) { item in
                        Button {
                            handleTap(item: item)
                        } label: {
                            inboxRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await viewModel.refresh() }
    }

    private func inboxRow(item: CoachingInboxItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(displayTitle(for: item.eventType))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(item.triggeredAt.formatted(.relative(presentation: .numeric)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let summary = item.summary {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Nothing yet")
                .font(.headline)
            Text("Coach messages will appear here as your training progresses.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Routing

    private func handleTap(item: CoachingInboxItem) {
        switch item.eventType {
        case "weekly_checkin_invite":
            // Opens the check-in flow; if it was already submitted/expired the
            // flow itself shows the linked review or a friendly empty state.
            showCheckinFlow = true
        case "weekly_review", "block_review":
            // Both reuse WeeklyReviewCardView; the card branches on `kind` itself
            // when presented from the deep-link router. Inbox routing keeps it
            // simple for v2 (always presents weekly variant from inbox tap).
            selectedReviewEventId = item.id
        case "post_race":
            selectedRaceRecapEventId = item.id
        default:
            // Future: post_run_check / wellness_concern / etc. — Phase 3+
            selectedReviewEventId = item.id
        }
    }

    private func displayTitle(for eventType: String) -> String {
        switch eventType {
        case "weekly_review": return "Weekly review"
        case "weekly_checkin_invite": return "Weekly check-in"
        case "block_review":  return "Block review"
        case "race_prep_review": return "Race prep"
        case "race_prep_entry": return "Welcome to taper"
        case "post_race":     return "Race recap"
        case "post_run_check": return "Post-run check"
        case "post_run_info":  return "Run synced"
        case "red_flag":      return "Coach flag"
        case "consolidation": return "Locked in"
        case "wellness_concern": return "Wellness check-in"
        case "plan_adjustment_proposed": return "Coach proposes a change"
        case "chat":          return "Chat"
        case "garmin_reconcile": return "Garmin sync recovery"
        case "no_active_plan": return "No active plan"
        default: return eventType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

// MARK: - View model

@MainActor
final class CoachInboxViewModel: ObservableObject {
    @Published private(set) var sections: [InboxSection] = []
    @Published private(set) var items: [CoachingInboxItem] = []
    @Published private(set) var isLoading: Bool = false
    @Published var error: String?

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await APIService.shared.fetchCoachingInbox(limit: 30)
            self.items = fetched
            self.sections = group(fetched)
        } catch {
            self.error = "Couldn't load inbox."
        }
    }

    private func group(_ items: [CoachingInboxItem]) -> [InboxSection] {
        let reviewTypes: Set<String> = ["weekly_review", "block_review", "race_prep_review"]
        let raceTypes: Set<String> = ["post_race", "race_prep_entry", "race_logistics_generated"]
        let adjustmentTypes: Set<String> = ["plan_adjustment_proposed"]

        let reviews = items.filter { reviewTypes.contains($0.eventType) }
        let races = items.filter { raceTypes.contains($0.eventType) }
        let adjustments = items.filter { adjustmentTypes.contains($0.eventType) }
        let other = items.filter {
            !reviewTypes.contains($0.eventType) &&
            !raceTypes.contains($0.eventType) &&
            !adjustmentTypes.contains($0.eventType) &&
            $0.eventType != "no_active_plan" &&
            $0.eventType != "garmin_reconcile"
        }

        var sections: [InboxSection] = []
        if !races.isEmpty {       sections.append(InboxSection(title: "Race", items: races)) }
        if !reviews.isEmpty {     sections.append(InboxSection(title: "Reviews", items: reviews)) }
        if !adjustments.isEmpty { sections.append(InboxSection(title: "Adjustments", items: adjustments)) }
        if !other.isEmpty {       sections.append(InboxSection(title: "Other", items: other)) }
        return sections
    }
}

struct InboxSection: Identifiable {
    let title: String
    let items: [CoachingInboxItem]
    var id: String { title }
}

private struct IdentifiableUUID: Identifiable {
    let id: UUID
}
