import SwiftUI

struct LeaderboardCardView: View {
    let entry: LeaderboardEntry
    let isCurrentUser: Bool
    let isDistanceLeaderboard: Bool

    @State private var decodedPhoto: UIImage?

    private var rankColor: Color {
        switch entry.rank {
        case 1: return Color(hex: "FFD700") // Gold
        case 2: return Color(hex: "C0C0C0") // Silver
        case 3: return Color(hex: "CD7F32") // Bronze
        default: return .clear
        }
    }

    private var isTopThree: Bool { entry.rank <= 3 }

    var body: some View {
        HStack(spacing: 12) {
            // Rank
            ZStack {
                if isTopThree {
                    Circle()
                        .fill(rankColor.opacity(0.2))
                        .frame(width: 36, height: 36)
                }
                Text("\(entry.rank)")
                    .font(.barlowCondensed(size: isTopThree ? 20 : 18, weight: isTopThree ? .semibold : .medium))
                    .foregroundStyle(isTopThree ? rankColor : .secondary)
            }
            .frame(width: 36)

            // Profile photo
            profileImage
                .frame(width: 36, height: 36)
                .clipShape(Circle())

            // Name
            Text(entry.displayName)
                .font(.inter(size: 15, weight: isCurrentUser ? .semibold : .regular))
                .foregroundStyle(isCurrentUser ? Color.stridePrimary : .primary)
                .lineLimit(1)

            Spacer()

            // Value
            Text(entry.formattedValue(isDistance: isDistanceLeaderboard))
                .font(.barlowCondensed(size: 18, weight: .medium))
                .foregroundStyle(isCurrentUser ? Color.stridePrimary : .primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isCurrentUser ? Color.stridePrimary.opacity(0.08) : Color.clear)
        .cornerRadius(12)
        .onAppear { decodePhoto() }
    }

    @ViewBuilder
    private var profileImage: some View {
        if let decodedPhoto {
            Image(uiImage: decodedPhoto)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "person.circle.fill")
                .resizable()
                .foregroundStyle(Color(.tertiarySystemFill))
        }
    }

    private func decodePhoto() {
        guard let base64 = entry.profilePhotoBase64,
              !base64.isEmpty,
              let data = Data(base64Encoded: base64),
              let image = UIImage(data: data) else {
            decodedPhoto = nil
            return
        }
        decodedPhoto = image
    }
}
