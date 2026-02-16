import SwiftUI

struct CommunityView: View {
    @StateObject private var viewModel = CommunityViewModel()
    @StateObject private var achievementsVM = AchievementsViewModel()
    @StateObject private var challengesVM = ChallengesViewModel()
    @StateObject private var eventsVM = EventsViewModel()
    @StateObject private var feedVM = ActivityFeedViewModel()
    @StateObject private var teamsVM = TeamsViewModel()
    @EnvironmentObject private var authService: AuthService

    private var currentUserId: String? {
        switch authService.authState {
        case .signedIn(let user): return user.id
        case .needsProfile(let user): return user.id
        default: return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Events + Challenges + Achievements banners
            VStack(spacing: 8) {
                activityFeedBanner
                teamsBanner
                eventsBanner
                challengesBanner
                achievementsBanner
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Segment picker for leaderboard type
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LeaderboardType.allCases, id: \.rawValue) { type in
                        SegmentChip(
                            title: type.rawValue,
                            isSelected: viewModel.selectedType == type
                        ) {
                            viewModel.selectedType = type
                            viewModel.loadLeaderboard()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            // Filter pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LeaderboardFilter.allCases, id: \.rawValue) { filter in
                        FilterPill(
                            title: filter.rawValue,
                            isSelected: viewModel.selectedFilter == filter
                        ) {
                            viewModel.selectedFilter = filter
                            viewModel.loadLeaderboard()
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            Divider()
                .padding(.top, 8)

            // Leaderboard content
            ZStack {
                if viewModel.isLoading && viewModel.entries.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(Color.stridePrimary)
                        Text("Loading leaderboard...")
                            .font(.inter(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.entries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "trophy")
                            .font(.system(size: 40))
                            .foregroundStyle(Color(.tertiaryLabel))
                        Text("No entries yet")
                            .font(.inter(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("Complete Bluetooth-verified runs to appear on the leaderboard.")
                            .font(.inter(size: 13))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    leaderboardList
                }
            }
        }
        .navigationTitle("Community")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: UserSearchView()) {
                    Image(systemName: "magnifyingglass")
                }
            }
        }
        .onAppear {
            viewModel.loadLeaderboard()
            achievementsVM.loadAll()
            achievementsVM.checkUnnotified()
            challengesVM.loadActiveChallenges()
            eventsVM.loadEvents()
            teamsVM.loadMyTeams()
        }
        .sheet(isPresented: $achievementsVM.showUnlockedSheet) {
            AchievementUnlockedSheet(
                achievements: achievementsVM.unnotifiedAchievements,
                onDismiss: {
                    achievementsVM.markNotified()
                    achievementsVM.showUnlockedSheet = false
                }
            )
        }
    }

    // MARK: - Activity Feed Banner

    private var activityFeedBanner: some View {
        NavigationLink(destination: ActivityFeedView()) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "bell.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Activity Feed")
                        .font(.inter(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text("See what your friends are up to")
                        .font(.inter(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Teams Banner

    private var teamsBanner: some View {
        NavigationLink(destination: TeamsView()) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.purple)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Teams")
                        .font(.inter(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)

                    let count = teamsVM.teams.count
                    Text(count > 0 ? "\(count) team\(count == 1 ? "" : "s")" : "Create or join a team")
                        .font(.inter(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Events Banner

    private var eventsBanner: some View {
        NavigationLink(destination: EventsView()) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "calendar")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Events")
                        .font(.inter(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)

                    let count = eventsVM.activeEvents.count + eventsVM.upcomingEvents.count
                    Text(count > 0 ? "\(count) available" : "No events right now")
                        .font(.inter(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Challenges Banner

    private var challengesBanner: some View {
        NavigationLink(destination: ChallengesView()) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.stridePrimary.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.stridePrimary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Challenges")
                        .font(.inter(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)

                    let count = challengesVM.activeChallenges.count
                    Text(count > 0 ? "\(count) active" : "No active challenges")
                        .font(.inter(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Achievements Banner

    private var achievementsBanner: some View {
        NavigationLink(destination: AchievementsView()) {
            HStack(spacing: 12) {
                // Show up to 4 unlocked badges
                HStack(spacing: -8) {
                    let topAchievements = Array(achievementsVM.unlocked.prefix(4))
                    ForEach(topAchievements) { achievement in
                        AchievementBadgeView(
                            icon: achievement.icon ?? "star",
                            tier: achievement.tier ?? "bronze",
                            isUnlocked: true,
                            size: 36
                        )
                    }

                    if achievementsVM.unlocked.isEmpty {
                        AchievementBadgeView(
                            icon: "star",
                            tier: "bronze",
                            isUnlocked: false,
                            size: 36
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Achievements")
                        .font(.inter(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)

                    let count = achievementsVM.unlocked.count
                    let total = achievementsVM.definitions.count
                    Text("\(count)/\(total) unlocked")
                        .font(.inter(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Leaderboard List

    private var leaderboardList: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("\(viewModel.totalParticipants) runners")
                    .font(.inter(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(Color.stridePrimary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Entries
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(viewModel.entries) { entry in
                        LeaderboardCardView(
                            entry: entry,
                            isCurrentUser: entry.userId == currentUserId,
                            isDistanceLeaderboard: viewModel.selectedType.isDistanceBased
                        )
                    }
                }
                .padding(.bottom, 80) // Space for sticky card
            }

            // Sticky "Your Position" card at bottom
            if let rank = viewModel.yourRank, let value = viewModel.yourValue {
                yourPositionCard(rank: rank, value: value)
            }
        }
    }

    // MARK: - Your Position Card

    private func yourPositionCard(rank: Int, value: Double) -> some View {
        HStack(spacing: 12) {
            Text("#\(rank)")
                .font(.barlowCondensed(size: 22, weight: .semibold))
                .foregroundStyle(Color.stridePrimary)

            Text("Your Position")
                .font(.inter(size: 14, weight: .medium))
                .foregroundStyle(.primary)

            Spacer()

            let formatted = LeaderboardEntry(
                rank: rank,
                userId: "",
                displayName: "",
                profilePhotoBase64: nil,
                value: value
            ).formattedValue(isDistance: viewModel.selectedType.isDistanceBased)

            Text(formatted)
                .font(.barlowCondensed(size: 20, weight: .semibold))
                .foregroundStyle(Color.stridePrimary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color(.separator)),
            alignment: .top
        )
    }
}

// MARK: - Segment Chip

struct SegmentChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.inter(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.stridePrimary : Color(.secondarySystemBackground))
                .clipShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Filter Pill

struct FilterPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.inter(size: 12, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? Color.stridePrimary : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected
                        ? Color.stridePrimary.opacity(0.1)
                        : Color(.tertiarySystemBackground)
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? Color.stridePrimary.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    NavigationStack {
        CommunityView()
            .environmentObject(AuthService.shared)
    }
}
