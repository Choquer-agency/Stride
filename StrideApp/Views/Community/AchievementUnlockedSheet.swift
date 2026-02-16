import SwiftUI

struct AchievementUnlockedSheet: View {
    let achievements: [UserAchievement]
    let onDismiss: () -> Void

    @State private var showContent = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Title
            Text("ACHIEVEMENT UNLOCKED!")
                .font(.barlowCondensed(size: 28, weight: .semibold))
                .foregroundStyle(Color.stridePrimary)
                .scaleEffect(showContent ? 1.0 : 0.5)
                .opacity(showContent ? 1 : 0)

            // Badges
            VStack(spacing: 20) {
                ForEach(achievements) { achievement in
                    VStack(spacing: 12) {
                        AchievementBadgeView(
                            icon: achievement.icon ?? "star",
                            tier: achievement.tier ?? "bronze",
                            isUnlocked: true,
                            size: 80
                        )

                        Text(achievement.title ?? "")
                            .font(.inter(size: 18, weight: .semibold))

                        Text(achievement.description ?? "")
                            .font(.inter(size: 14))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        // Tier label
                        if let tier = achievement.tier {
                            Text(tier.uppercased())
                                .font(.barlowCondensed(size: 14, weight: .medium))
                                .foregroundStyle(tierColor(tier))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(tierColor(tier).opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .scaleEffect(showContent ? 1.0 : 0.3)
            .opacity(showContent ? 1 : 0)

            Spacer()

            Button(action: onDismiss) {
                Text("Continue")
                    .font(.inter(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.stridePrimary)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 40)
            .opacity(showContent ? 1 : 0)

            Spacer()
                .frame(height: 40)
        }
        .padding()
        .background(Color(.systemBackground))
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                showContent = true
            }
            Haptics.notification(.success)
        }
    }

    private func tierColor(_ tier: String) -> Color {
        guard let t = AchievementTier(rawValue: tier) else { return .gray }
        return Color(hex: t.color)
    }
}
