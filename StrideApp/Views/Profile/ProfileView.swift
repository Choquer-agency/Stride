import SwiftUI
import SwiftData

struct ProfileView: View {
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var bluetoothManager: BluetoothManager
    @ObservedObject private var heartRateManager = HeartRateManager.shared
    @Query(filter: #Predicate<TrainingPlan> { $0.isArchived == false }, sort: \TrainingPlan.createdAt, order: .reverse) private var plans: [TrainingPlan]
    @Query(sort: \RunLog.completedAt, order: .reverse) private var runLogs: [RunLog]
    @StateObject private var achievementsVM = AchievementsViewModel()
    @State private var showEditProfile = false
    @AppStorage(RunLobbyAppearance.storageKey) private var appearanceRaw = RunLobbyAppearance.black.rawValue

    var onOpenPlan: () -> Void = {}

    @State private var showDeleteConfirmation = false
    @State private var accountError: String?

    private var appearance: RunLobbyAppearance { RunLobbyAppearance(rawValue: appearanceRaw) ?? .black }
    private var style: StridePageStyle { .init(appearance: appearance) }
    private var activePlan: TrainingPlan? { plans.first }
    private var thisMonthRuns: Int {
        guard let month = Calendar.current.dateInterval(of: .month, for: Date()) else { return 0 }
        return runLogs.filter { $0.isValidForStats && $0.completedAt >= month.start && $0.completedAt < month.end }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                StridePageHeader(profileAction: { showEditProfile = true })
                    .padding(.bottom, 24)
                Text("YOUR SPACE / YOUR SETUP")
                    .font(.runEyebrow(10)).tracking(1.3).foregroundStyle(style.muted)
                Text("THE ATHLETE.")
                    .font(.barlowCondensed(size: 43))
                    .padding(.top, 6)
                identityHeader.padding(.top, 17)
                athleteMetrics.padding(.top, 17)
                goalCard.padding(.top, 17)
                connectedSection.padding(.top, 24)
                runningSection.padding(.top, 24)
                preferencesSection.padding(.top, 24)
                accountSection.padding(.top, 24)
            }
            .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background { StridePageBackdrop().ignoresSafeArea() }
        .foregroundStyle(style.ink)
        .preferredColorScheme(appearance.colorScheme)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showEditProfile) {
            EditProfileView()
        }
        .confirmationDialog(
            "Permanently delete your account?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                Task {
                    do {
                        try await authService.deleteAccount()
                    } catch {
                        accountError = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your profile and synced Stride data will be permanently deleted. This cannot be undone.")
        }
        .alert("Account Could Not Be Deleted", isPresented: Binding(
            get: { accountError != nil },
            set: { if !$0 { accountError = nil } }
        )) {
            Button("OK", role: .cancel) { accountError = nil }
        } message: {
            Text(accountError ?? "Please try again.")
        }
        .onAppear { achievementsVM.loadAll() }
    }

    private var identityHeader: some View {
        HStack(spacing: 14) {
            avatar.frame(width: 66, height: 66)
                .clipShape(Circle())
                .overlay(Circle().stroke(style.accent, lineWidth: 2))
                .padding(4)
                .overlay(Circle().stroke(style.accent.opacity(0.15), lineWidth: 4))
            VStack(alignment: .leading, spacing: 3) {
                Text((currentUser?.name ?? currentUser?.displayName ?? "RUNNER").uppercased())
                    .font(.barlowCondensed(size: 27))
                    .lineLimit(2).minimumScaleFactor(0.75)
                Text(currentUser?.email.uppercased() ?? "")
                    .font(.runEyebrow(9)).foregroundStyle(style.muted)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            Button { showEditProfile = true } label: {
                Text("EDIT ↗").font(.runEyebrow(10))
                    .padding(.horizontal, 11).padding(.vertical, 8)
                    .overlay(Capsule().stroke(style.rule, lineWidth: 0.7))
            }.buttonStyle(.plain)
        }
    }

    @ViewBuilder private var avatar: some View {
        if let encoded = currentUser?.profilePhotoBase64,
           let data = Data(base64Encoded: encoded),
           let photo = UIImage(data: data) {
            Image(uiImage: photo).resizable().scaledToFill()
        } else {
            Text(initials).font(.barlowCondensed(size: 31))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(style.card)
        }
    }

    private var initials: String {
        let letters = (currentUser?.name ?? currentUser?.displayName ?? "")
            .split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "BC" : letters.uppercased()
    }

    private var athleteMetrics: some View {
        HStack(spacing: 0) {
            identityMetric("\(activePlan?.currentWeek?.weekNumber ?? 0)",
                           label: "WEEK / \(activePlan?.sortedWeeks.count ?? 0)")
            Rectangle().fill(style.rule).frame(width: 0.5, height: 38)
            identityMetric("\(thisMonthRuns)", label: "RUNS THIS MO.")
            Rectangle().fill(style.rule).frame(width: 0.5, height: 38)
            identityMetric("\(achievementsVM.streak?.currentStreakDays ?? 0)", label: "DAY STREAK")
        }
        .padding(.top, 16)
        .overlay(alignment: .top) { Rectangle().fill(style.rule).frame(height: 0.5) }
    }

    private func identityMetric(_ value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.barlowCondensed(size: 31))
            Text(label).font(.runEyebrow(8)).foregroundStyle(style.muted)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var goalCard: some View {
        Button(action: onOpenPlan) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("CURRENT GOAL / ROAD TO RACE")
                        .font(.runEyebrow(9)).foregroundStyle(style.muted)
                    Text((activePlan?.raceName ?? activePlan?.displayDistance ?? "BUILD YOUR PLAN").uppercased())
                        .font(.barlowCondensed(size: 25))
                        .lineLimit(1).minimumScaleFactor(0.65)
                    Text(activePlan.map { "\($0.sortedWeeks.count) WEEK PLAN · WEEK \($0.currentWeek?.weekNumber ?? 0)" } ?? "SET YOUR NEXT GOAL")
                        .font(.runEyebrow(9)).foregroundStyle(style.muted)
                }
                Spacer(minLength: 0)
                if let plan = activePlan {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(max(0, plan.daysUntilRace))")
                            .font(.barlowCondensed(size: 31))
                        Text("DAYS TO GO").font(.runEyebrow(8)).foregroundStyle(style.muted)
                    }
                } else {
                    Image(systemName: "arrow.up.right").font(.system(size: 17, weight: .medium))
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .stridePageCard(style)
        }
        .buttonStyle(.plain)
    }

    private var connectedSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            StrideSectionHeading(title: "CONNECTED", trailing: "MANAGE ↗", style: style)
            NavigationLink { allSettings } label: {
                profileRow(icon: "figure.run", title: "Assault Runner", detail: "TREADMILL",
                           status: bluetoothManager.connectedDevice == nil ? "NOT CONNECTED" : "CONNECTED")
            }
            NavigationLink { HeartRateMonitorPicker().toolbar(.visible, for: .navigationBar) } label: {
                profileRow(icon: "heart.fill", title: "Heart rate monitor",
                           detail: heartRateManager.selectedDeviceName?.uppercased() ?? "CHOOSE MONITOR",
                           status: heartRateManager.isConnected ? "CONNECTED" : nil)
            }
            NavigationLink { allSettings } label: {
                profileRow(icon: "link", title: "Integrations", detail: "GARMIN, FITBIT & MORE")
            }
        }
        .buttonStyle(.plain)
    }

    private var runningSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            StrideSectionHeading(title: "YOUR RUNNING", style: style)
            NavigationLink { ShoesView().toolbar(.visible, for: .navigationBar) } label: {
                profileRow(icon: "shoeprints.fill", title: "Shoes & gear", detail: "TRACK MILEAGE")
            }
            NavigationLink { ArchivedPlansView().toolbar(.visible, for: .navigationBar) } label: {
                profileRow(icon: "clock.arrow.circlepath", title: "Previous plans", detail: "TRAINING HISTORY")
            }
            NavigationLink { AchievementsView().toolbar(.visible, for: .navigationBar) } label: {
                profileRow(icon: "star.fill", title: "Achievements", detail: "BADGES & PERSONAL BESTS")
            }
        }
        .buttonStyle(.plain)
    }

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            StrideSectionHeading(title: "PREFERENCES", style: style)
            NavigationLink { allSettings } label: {
                profileRow(icon: "waveform", title: "Audio & coaching", detail: "VOICE, CUES & HAPTICS")
            }
            NavigationLink { allSettings } label: {
                profileRow(icon: "bell", title: "Notifications", detail: "REMINDERS & UPDATES")
            }
            NavigationLink { accountAndPrivacy } label: {
                profileRow(icon: "gearshape", title: "Account & privacy", detail: "PERSONAL DATA")
            }
        }
        .buttonStyle(.plain)
    }

    private var accountSection: some View {
        NavigationLink { allSettings } label: {
            HStack {
                Text("ALL SETTINGS").font(.runEyebrow(10)).foregroundStyle(style.muted)
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(style.muted)
            }
            .padding(.vertical, 15)
        }
        .buttonStyle(.plain)
    }

    private func profileRow(icon: String, title: String, detail: String, status: String? = nil) -> some View {
        HStack(spacing: 12) {
            Rectangle().fill(style.accent).frame(width: 3, height: 43)
            Image(systemName: icon).font(.system(size: 15, weight: .medium))
                .foregroundStyle(style.accent)
                .frame(width: 32, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased()).font(.barlowCondensed(size: 25))
                    .lineLimit(1).minimumScaleFactor(0.75)
                Text(detail).font(.inter(size: 11)).foregroundStyle(style.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 3)
            if let status {
                HStack(spacing: 4) {
                    Circle().fill(status == "CONNECTED" ? Color.blue : style.muted)
                        .frame(width: 5, height: 5)
                    Text(status).font(.runEyebrow(8)).foregroundStyle(style.muted)
                }
            }
            Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(style.accent)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(style.rule).frame(height: 0.5) }
    }

    private var allSettings: some View {
        List { SettingsSectionsView() }
            .navigationTitle("Settings")
            .toolbar(.visible, for: .navigationBar)
    }

    private var accountAndPrivacy: some View {
        List {
            Section("Account") {
                NavigationLink("Edit profile") { EditProfileView() }
                NavigationLink("iCloud Sync") { SyncSettingsView() }
                Button("Sign Out", role: .destructive) { authService.signOut() }
                Button("Delete Account", role: .destructive) { showDeleteConfirmation = true }
            }
            Section("Legal") {
                Link("Privacy Policy", destination: URL(string: "https://stride.app/privacy")!)
                Link("Terms of Service", destination: URL(string: "https://stride.app/terms")!)
            }
        }
        .navigationTitle("Account & Privacy")
        .toolbar(.visible, for: .navigationBar)
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
