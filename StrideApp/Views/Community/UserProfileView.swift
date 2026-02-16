import SwiftUI

struct UserProfileView: View {
    let userId: String
    @State private var profile: UserProfileResponse?
    @State private var isLoading = true
    @State private var isFollowing = false

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .tint(Color.stridePrimary)
                    .padding(.top, 60)
            } else if let profile {
                VStack(spacing: 20) {
                    profileHeader(profile)
                    statsRow(profile)
                    followButton(profile)
                    recentActivitySection(profile)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadProfile() }
    }

    // MARK: - Profile Header

    private func profileHeader(_ profile: UserProfileResponse) -> some View {
        VStack(spacing: 12) {
            if let base64 = profile.profilePhotoBase64,
               let data = Data(base64Encoded: base64),
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Text(String(profile.displayName.prefix(1)).uppercased())
                            .font(.inter(size: 32, weight: .semibold))
                            .foregroundStyle(.secondary)
                    )
            }

            Text(profile.displayName)
                .font(.inter(size: 20, weight: .bold))

            if let bio = profile.bio, !bio.isEmpty {
                Text(bio)
                    .font(.inter(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 24) {
                VStack {
                    Text("\(profile.followerCount)")
                        .font(.barlowCondensed(size: 20, weight: .semibold))
                    Text("Followers")
                        .font(.inter(size: 12))
                        .foregroundStyle(.secondary)
                }
                VStack {
                    Text("\(profile.followingCount)")
                        .font(.barlowCondensed(size: 20, weight: .semibold))
                    Text("Following")
                        .font(.inter(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Stats Row

    private func statsRow(_ profile: UserProfileResponse) -> some View {
        HStack(spacing: 0) {
            statItem(
                value: String(format: "%.0f", profile.totalDistanceKm),
                unit: "km",
                label: "Total Distance"
            )
            Divider().frame(height: 40)
            statItem(
                value: "\(profile.totalRuns)",
                unit: "",
                label: "Total Runs"
            )
        }
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func statItem(value: String, unit: String, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.barlowCondensed(size: 24, weight: .semibold))
                if !unit.isEmpty {
                    Text(unit)
                        .font(.inter(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Text(label)
                .font(.inter(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Follow Button

    private func followButton(_ profile: UserProfileResponse) -> some View {
        Button {
            toggleFollow()
        } label: {
            Text(isFollowing ? "Following" : "Follow")
                .font(.inter(size: 15, weight: .semibold))
                .foregroundStyle(isFollowing ? Color.primary : Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isFollowing ? Color(.tertiarySystemFill) : Color.stridePrimary)
                .cornerRadius(12)
        }
    }

    // MARK: - Recent Activity

    private func recentActivitySection(_ profile: UserProfileResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.inter(size: 16, weight: .semibold))

            if profile.recentActivities.isEmpty {
                Text("No recent activity")
                    .font(.inter(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(profile.recentActivities) { activity in
                    ActivityCardView(item: activity, showUser: false)
                }
            }
        }
    }

    // MARK: - Actions

    private func loadProfile() {
        Task {
            do {
                profile = try await APIService.shared.fetchUserProfile(userId: userId)
                isFollowing = profile?.isFollowing ?? false
                isLoading = false
            } catch {
                isLoading = false
            }
        }
    }

    private func toggleFollow() {
        let was = isFollowing
        isFollowing = !was

        Task {
            do {
                if was {
                    try await APIService.shared.unfollowUser(userId: userId)
                } else {
                    try await APIService.shared.followUser(userId: userId)
                }
                // Reload to update counts
                profile = try await APIService.shared.fetchUserProfile(userId: userId)
            } catch {
                isFollowing = was
            }
        }
    }
}
