import SwiftUI

struct AchievementBadgeView: View {
    let icon: String
    let tier: String
    let isUnlocked: Bool
    var size: CGFloat = 56

    private var tierColor: Color {
        guard let t = AchievementTier(rawValue: tier) else { return .gray }
        return Color(hex: t.color)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(isUnlocked ? tierColor.opacity(0.15) : Color(.tertiarySystemFill))
                .frame(width: size, height: size)

            Circle()
                .strokeBorder(isUnlocked ? tierColor : Color(.quaternarySystemFill), lineWidth: 2.5)
                .frame(width: size, height: size)

            Image(systemName: icon)
                .font(.system(size: size * 0.36, weight: .medium))
                .foregroundStyle(isUnlocked ? tierColor : Color(.tertiaryLabel))
        }
        .opacity(isUnlocked ? 1.0 : 0.5)
    }
}
