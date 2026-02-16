import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var bluetoothManager: BluetoothManager
    @StateObject private var achievementsVM = AchievementsViewModel()
    @State private var showEditProfile = false

    var body: some View {
        List {
            // Profile Header
            Section {
                ProfileHeaderView(
                    user: currentUser,
                    onEditTapped: { showEditProfile = true }
                )
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            // Badges section
            if !achievementsVM.unlocked.isEmpty {
                Section {
                    ProfileBadgesRow(achievements: achievementsVM.unlocked)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
            }

            // Streak
            if let streak = achievementsVM.streak, streak.currentStreakDays > 0 {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(Color.stridePrimary)
                        Text("\(streak.currentStreakDays)-day streak")
                            .font(.inter(size: 15, weight: .medium))
                        Spacer()
                        Text("Best: \(streak.longestStreakDays)")
                            .font(.inter(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // All settings sections
            SettingsSectionsView()

            // Sign Out
            Section {
                Button(role: .destructive) {
                    authService.signOut()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(.red, .red)
                }
            }
        }
        .tint(Color.stridePrimary)
        .contentMargins(.bottom, 16, for: .scrollContent)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showEditProfile) {
            EditProfileView()
        }
        .onAppear { achievementsVM.loadAll() }
    }

    private var currentUser: UserResponse? {
        switch authService.authState {
        case .signedIn(let user): return user
        case .needsProfile(let user): return user
        default: return nil
        }
    }
}

// MARK: - Profile Header

struct ProfileHeaderView: View {
    let user: UserResponse?
    let onEditTapped: () -> Void

    @State private var decodedPhoto: UIImage?

    var body: some View {
        HStack(spacing: 16) {
            // Profile photo
            profileImage
                .frame(width: 72, height: 72)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(user?.name ?? "Runner")
                    .font(.inter(size: 20, weight: .semibold))

                Text(user?.email ?? "")
                    .font(.inter(size: 13))
                    .foregroundStyle(.secondary)

                // Stat pills
                if let user {
                    HStack(spacing: 8) {
                        if let age = computedAge(from: user.dateOfBirth) {
                            StatPill(label: "\(age) yrs")
                        }
                        if let height = user.heightCm {
                            StatPill(label: "\(Int(height)) cm")
                        }
                        if let gender = user.gender {
                            StatPill(label: genderShortLabel(gender))
                        }
                    }
                    .padding(.top, 4)
                }
            }

            Spacer()

            Button(action: onEditTapped) {
                Image(systemName: "pencil.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.stridePrimary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
        .onAppear { decodePhoto() }
        .onChange(of: user?.profilePhotoBase64) { _, _ in decodePhoto() }
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
        guard let base64 = user?.profilePhotoBase64,
              !base64.isEmpty,
              let data = Data(base64Encoded: base64),
              let image = UIImage(data: data) else {
            decodedPhoto = nil
            return
        }
        decodedPhoto = image
    }

    private func computedAge(from dateString: String?) -> Int? {
        guard let dateString, !dateString.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let dob = formatter.date(from: dateString) else { return nil }
        let age = Calendar.current.dateComponents([.year], from: dob, to: Date()).year
        return age
    }

    private func genderShortLabel(_ gender: String) -> String {
        switch gender {
        case "male": return "M"
        case "female": return "F"
        case "non_binary": return "NB"
        default: return ""
        }
    }
}

// MARK: - Stat Pill

struct StatPill: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.inter(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.secondarySystemBackground))
            .clipShape(Capsule())
    }
}

// MARK: - Profile Badges Row

struct ProfileBadgesRow: View {
    let achievements: [UserAchievement]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(achievements.prefix(8)) { achievement in
                    VStack(spacing: 4) {
                        AchievementBadgeView(
                            icon: achievement.icon ?? "star",
                            tier: achievement.tier ?? "bronze",
                            isUnlocked: true,
                            size: 44
                        )
                        Text(achievement.title ?? "")
                            .font(.inter(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: 56)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.trailing, 16)
        }
    }
}

#Preview {
    NavigationStack {
        ProfileView()
            .environmentObject(AuthService.shared)
            .environmentObject(BluetoothManager())
    }
}
