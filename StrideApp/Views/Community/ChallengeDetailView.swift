import SwiftUI

struct ChallengeDetailView: View {
    let challengeId: String
    @StateObject private var viewModel = ChallengesViewModel()
    @EnvironmentObject private var authService: AuthService

    private var currentUserId: String? {
        switch authService.authState {
        case .signedIn(let user): return user.id
        case .needsProfile(let user): return user.id
        default: return nil
        }
    }

    var body: some View {
        Group {
            if viewModel.isLoadingDetail && viewModel.detail == nil {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(Color.stridePrimary)
                    Text("Loading challenge...")
                        .font(.inter(size: 14))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail = viewModel.detail {
                challengeContent(detail)
            }
        }
        .navigationTitle("Challenge")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.loadDetail(challengeId: challengeId)
        }
    }

    @ViewBuilder
    private func challengeContent(_ detail: ChallengeDetailResponse) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    challengeHeader(detail)

                    // Your Result (if joined)
                    if detail.isJoined {
                        yourResultCard(detail)
                    }

                    // Leaderboard
                    if !detail.leaderboard.isEmpty {
                        leaderboardSection(detail)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }

            // Bottom action
            if !detail.isJoined {
                joinButton
            }
        }
    }

    // MARK: - Header

    private func challengeHeader(_ detail: ChallengeDetailResponse) -> some View {
        VStack(spacing: 12) {
            // Type badge
            HStack(spacing: 6) {
                Image(systemName: detail.isRace ? "flag.checkered" : "figure.run")
                    .font(.system(size: 12, weight: .semibold))
                Text(detail.isRace ? "Weekly Race" : "Monthly Challenge")
                    .font(.inter(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(detail.isRace ? Color.stridePrimary : Color.blue)
            .clipShape(Capsule())

            // Title
            Text(detail.title)
                .font(.inter(size: 22, weight: .bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            // Countdown
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text(detail.timeRemaining)
                    .font(.inter(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Participant count
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text("\(detail.participantCount) runners")
                    .font(.inter(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }

    // MARK: - Your Result

    private func yourResultCard(_ detail: ChallengeDetailResponse) -> some View {
        VStack(spacing: 8) {
            Text("Your Result")
                .font(.inter(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            if detail.isRace {
                if let seconds = detail.yourBestTimeSeconds {
                    Text(formatTime(seconds: seconds))
                        .font(.barlowCondensed(size: 36, weight: .semibold))
                        .foregroundStyle(Color.stridePrimary)
                } else {
                    Text("No qualifying run yet")
                        .font(.inter(size: 14))
                        .foregroundStyle(.tertiary)
                }
            } else {
                let current = detail.yourTotalDistanceKm ?? 0
                let target = detail.cumulativeTargetKm ?? 100

                Text(String(format: "%.1f km", current))
                    .font(.barlowCondensed(size: 36, weight: .semibold))
                    .foregroundStyle(Color.stridePrimary)

                ProgressView(value: min(current / target, 1.0))
                    .tint(Color.stridePrimary)
                    .padding(.horizontal, 20)

                Text(String(format: "%.0f km goal", target))
                    .font(.inter(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
    }

    // MARK: - Leaderboard

    private func leaderboardSection(_ detail: ChallengeDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Leaderboard")
                .font(.inter(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.leading, 4)

            LazyVStack(spacing: 2) {
                ForEach(detail.leaderboard) { entry in
                    leaderboardRow(entry: entry, isRace: detail.isRace)
                }
            }
        }
    }

    private func leaderboardRow(entry: LeaderboardEntry, isRace: Bool) -> some View {
        HStack(spacing: 12) {
            // Rank
            ZStack {
                if entry.rank <= 3 {
                    Image(systemName: "medal.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(medalColor(for: entry.rank))
                } else {
                    Text("#\(entry.rank)")
                        .font(.barlowCondensed(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 32)

            // Avatar
            if let photoBase64 = entry.profilePhotoBase64,
               let data = Data(base64Encoded: photoBase64),
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(String(entry.displayName.prefix(1)).uppercased())
                            .font(.inter(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    )
            }

            // Name
            Text(entry.displayName)
                .font(.inter(size: 14, weight: entry.userId == currentUserId ? .semibold : .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            // Value
            Text(entry.formattedValue(isDistance: !isRace))
                .font(.barlowCondensed(size: 18, weight: .semibold))
                .foregroundStyle(entry.userId == currentUserId ? Color.stridePrimary : .primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            entry.userId == currentUserId
                ? Color.stridePrimary.opacity(0.08)
                : Color(.secondarySystemBackground)
        )
        .cornerRadius(10)
    }

    private func medalColor(for rank: Int) -> Color {
        switch rank {
        case 1: return Color(hex: "FFD700")
        case 2: return Color(hex: "C0C0C0")
        case 3: return Color(hex: "CD7F32")
        default: return .secondary
        }
    }

    // MARK: - Join Button

    private var joinButton: some View {
        Button {
            viewModel.joinChallenge(id: challengeId)
        } label: {
            HStack(spacing: 8) {
                if viewModel.isJoining {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Join Challenge")
                        .font(.inter(size: 16, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.stridePrimary)
            .cornerRadius(14)
        }
        .disabled(viewModel.isJoining)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial)
    }
}

#Preview {
    NavigationStack {
        ChallengeDetailView(challengeId: "test")
            .environmentObject(AuthService.shared)
    }
}
