import SwiftUI

/// Race countdown banner for the Plan tab during the final 28 days.
/// Tap → opens RacePrepChecklistView.
///
/// Add to PlanView body when there's an active registered race within 28 days.
/// Caller passes the eventId + days_to_race; this view doesn't fetch.
struct RaceCountdownBannerView: View {
    let eventId: UUID
    let raceTitle: String
    let daysToRace: Int

    @State private var showChecklist = false

    var body: some View {
        Button { showChecklist = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "flag.checkered")
                    .font(.title3)
                    .foregroundStyle(Color.stridePrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(raceTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color.stridePrimary.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.stridePrimary.opacity(0.3), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .sheet(isPresented: $showChecklist) {
            RacePrepChecklistView(eventId: eventId)
        }
    }

    private var headline: String {
        if daysToRace == 0 { return "RACE DAY" }
        if daysToRace == 1 { return "RACE TOMORROW" }
        if daysToRace <= 7 { return "Race in \(daysToRace) days — checklist" }
        return "Race week minus \(daysToRace / 7)"
    }
}
