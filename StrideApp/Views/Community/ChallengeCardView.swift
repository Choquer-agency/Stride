import SwiftUI

struct ChallengeCardView: View {
    let challenge: ChallengeResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row
            HStack {
                // Type badge
                HStack(spacing: 4) {
                    Image(systemName: challenge.typeIcon)
                        .font(.system(size: 10, weight: .semibold))
                    Text(challenge.typeLabel)
                        .font(.inter(size: 11, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(challenge.isRace ? Color.stridePrimary : Color.blue)
                .clipShape(Capsule())

                Spacer()

                // Time remaining
                Text(challenge.timeRemaining)
                    .font(.inter(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Title
            Text(challenge.title)
                .font(.inter(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            // Progress or result
            if challenge.isJoined {
                if let result = challenge.formattedYourResult {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.green)
                        Text("Your best: \(result)")
                            .font(.barlowCondensed(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                } else if let progress = challenge.distanceProgress {
                    // Monthly distance progress bar
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress)
                            .tint(Color.stridePrimary)
                        let current = challenge.yourTotalDistanceKm ?? 0
                        let target = challenge.cumulativeTargetKm ?? 100
                        Text(String(format: "%.1f / %.0f km", current, target))
                            .font(.barlowCondensed(size: 13))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.green)
                        Text("Joined — complete a run to rank!")
                            .font(.inter(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("\(challenge.participantCount) runners")
                        .font(.inter(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            // Bottom: participant count + join status
            HStack {
                if challenge.isJoined {
                    Text("\(challenge.participantCount) runners")
                        .font(.inter(size: 11))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if !challenge.isJoined {
                    Text("Tap to join")
                        .font(.inter(size: 12, weight: .semibold))
                        .foregroundStyle(Color.stridePrimary)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
    }
}
