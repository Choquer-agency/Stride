import SwiftUI

/// Race recap sheet — fired when Garmin webhook detects the athlete completed
/// a registered race (Phase 1 race detection). Surfaced from
/// `stride://coach/post-run/{event_id}` push deep link when event_type == post_race.
///
/// Displays:
///   - Hero stat: final time + PR delta if available
///   - Splits chart (when present in the matched Run.km_splits_json)
///   - Streaming coach commentary from coach_post_race.txt (Phase 3 wires the SSE)
///   - 7-14 day recovery checklist (Phase 3 will populate from <adjustment> tag)
///
/// For Phase 1 we wire the structure + summary display; the live SSE streaming
/// of the recap text plugs in once /api/coach/run-post-run-check is exposed.
struct RaceRecapView: View {
    let eventId: UUID
    let initialSummary: String?

    @Environment(\.dismiss) private var dismiss
    @State private var coachText: String
    @State private var loading: Bool = false

    init(eventId: UUID, initialSummary: String? = nil) {
        self.eventId = eventId
        self.initialSummary = initialSummary
        _coachText = State(initialValue: initialSummary ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    heroSection
                    Divider().padding(.horizontal)
                    coachSection
                    Divider().padding(.horizontal)
                    recoveryChecklistPlaceholder
                    feedbackSection
                }
                .padding(.vertical, 24)
            }
            .navigationTitle("Race day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await fetchLatestIfNeeded() }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 8) {
            Text("Race day")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text("You showed up.")
                .font(.system(size: 36, weight: .bold, design: .default))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.top, 8)
    }

    // MARK: - Coach commentary

    private var coachSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("From your coach")
                    .font(.headline)
                Spacer()
                if loading {
                    ProgressView().controlSize(.small)
                }
            }
            if coachText.isEmpty {
                Text("Generating recap…")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                Text(coachText)
                    .font(.body)
                    .lineSpacing(4)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Recovery checklist (Phase 3 wires real items from <adjustment> tag)

    private var recoveryChecklistPlaceholder: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Next 7–14 days")
                .font(.headline)
            Text("Your coach will lay out the recovery plan once the full recap loads. As a default: take today and tomorrow completely off, walk for 20–30 min if you feel like moving, eat enough, sleep more.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Feedback row (first 3 race recaps)

    private var feedbackSection: some View {
        // RaceRecap doesn't get its own feedback bucket — uses post_race like the
        // inbox event. CoachFeedbackRow visibility gating happens in the parent
        // when surfacing — included unconditionally here for now.
        CoachFeedbackRow(eventId: eventId, loopName: "post_race")
            .padding(.horizontal, 20)
    }

    // MARK: - Data fetch

    private func fetchLatestIfNeeded() async {
        // Phase 1: if we have an initialSummary from the inbox, that's what we show.
        // Phase 3 will replace this with an SSE stream from /api/coach/get-or-stream-event.
        guard coachText.isEmpty else { return }
        loading = true
        defer { loading = false }
        do {
            // Reuse the inbox endpoint to grab the event's summary
            let inbox = try await APIService.shared.fetchCoachingInbox(limit: 50)
            if let item = inbox.first(where: { $0.id == eventId }), let summary = item.summary {
                coachText = summary
            }
        } catch {
            // Silent — leave placeholder in place
        }
    }
}
