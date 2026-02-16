import SwiftUI

struct AchievementsView: View {
    @StateObject private var viewModel = AchievementsViewModel()

    var body: some View {
        ScrollView {
            // Streak card
            if let streak = viewModel.streak, streak.currentStreakDays > 0 {
                streakCard(streak)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            // Achievement grid by category
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(viewModel.groupedByCategory, id: \.0) { category, achievements in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(category.uppercased())
                            .font(.inter(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 150), spacing: 12)],
                            spacing: 12
                        ) {
                            ForEach(achievements) { defn in
                                achievementCard(defn)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.vertical, 16)
            .padding(.bottom, 80)
        }
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { viewModel.loadAll() }
        .overlay {
            if viewModel.isLoading && viewModel.definitions.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(Color.stridePrimary)
                    Text("Loading achievements...")
                        .font(.inter(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Streak Card

    private func streakCard(_ streak: UserStreakResponse) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "flame.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.stridePrimary)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(streak.currentStreakDays)-day streak")
                    .font(.barlowCondensed(size: 24, weight: .semibold))
                Text("Longest: \(streak.longestStreakDays) days")
                    .font(.inter(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }

    // MARK: - Achievement Card

    private func achievementCard(_ defn: AchievementDefinition) -> some View {
        let unlocked = viewModel.isUnlocked(defn)

        return VStack(spacing: 8) {
            AchievementBadgeView(
                icon: defn.icon,
                tier: defn.tier,
                isUnlocked: unlocked,
                size: 52
            )

            Text(defn.title)
                .font(.inter(size: 13, weight: unlocked ? .semibold : .regular))
                .foregroundStyle(unlocked ? .primary : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if unlocked, let date = viewModel.unlockedDate(for: defn) {
                Text(date)
                    .font(.inter(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                Text(defn.description)
                    .font(.inter(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            // Progress bar for streak achievements
            if !unlocked, let progress = viewModel.progress(for: defn) {
                ProgressView(value: progress)
                    .tint(Color.stridePrimary)
                    .scaleEffect(y: 0.6)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

#Preview {
    NavigationStack {
        AchievementsView()
    }
}
