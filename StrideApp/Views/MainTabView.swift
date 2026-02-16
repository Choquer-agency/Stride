import SwiftUI
import SwiftData
import PostHog

struct MainTabView: View {
    @State private var selectedTab: Tab = .plan
    @State private var hideTabBar: Bool = false
    
    enum Tab: Int {
        case run = 0
        case plan = 1
        case stats = 2
        case community = 3
        case profile = 4

        var title: String {
            switch self {
            case .run: return "Run"
            case .plan: return "Plan"
            case .stats: return "Stats"
            case .community: return "Community"
            case .profile: return "Profile"
            }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            Group {
                switch selectedTab {
                case .run:
                    NavigationStack {
                        RunTabContainer(hideTabBar: $hideTabBar, selectedTab: $selectedTab)
                    }
                case .plan:
                    PlanTabContainer()
                case .stats:
                    NavigationStack {
                        StatsView(selectedTab: $selectedTab)
                    }
                case .community:
                    NavigationStack {
                        CommunityView()
                    }
                case .profile:
                    NavigationStack {
                        ProfileView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !hideTabBar {
                    Color.clear.frame(height: 50)
                }
            }
            .overlay(alignment: .bottom) {
                if !hideTabBar {
                    CustomTabBar(selectedTab: $selectedTab, screenWidth: geometry.size.width)
                        .offset(y: geometry.safeAreaInsets.bottom)
                        .animation(.none, value: selectedTab)
                }
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChange(of: selectedTab) { _, newTab in
            PostHogSDK.shared.capture("tab_switched", properties: ["tab": newTab.title])
        }
    }
}

// MARK: - Custom Tab Bar
struct CustomTabBar: View {
    @Binding var selectedTab: MainTabView.Tab
    let screenWidth: CGFloat
    
    // Proportional sizing (based on 402px Figma frame, widened for 5 tabs)
    private var pillWidth: CGFloat { screenWidth * 0.90 }
    private var pillHeight: CGFloat { 62 }
    private var buttonsWidth: CGFloat { screenWidth * 0.82 }
    private var bottomOffset: CGFloat { screenWidth * 0.0373 }
    private var blurHeight: CGFloat { screenWidth * 0.209 }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Layer 1: Progressive background blur
            // Full width, pinned to the very bottom of the screen
            Rectangle()
                .fill(.regularMaterial)
                .frame(maxWidth: .infinity)
                .frame(height: blurHeight)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.5), location: 0.4),
                            .init(color: .black, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // Layer 2 & 3: Floating pill with brand-color glow shadow
            HStack(spacing: 0) {
                TabBarButton(
                    tab: .run,
                    selectedTab: $selectedTab,
                    icon: { StrideLogoView(height: 28, color: $0) },
                    title: "Run"
                )
                
                TabBarButton(
                    tab: .plan,
                    selectedTab: $selectedTab,
                    icon: { FlagIconView(size: 24, color: $0) },
                    title: "Plan"
                )
                
                TabBarButton(
                    tab: .stats,
                    selectedTab: $selectedTab,
                    icon: { StatsIconView(size: 24, color: $0) },
                    title: "Stats"
                )

                TabBarButton(
                    tab: .community,
                    selectedTab: $selectedTab,
                    icon: { CommunityIconView(size: 22, color: $0) },
                    title: "Community"
                )

                TabBarButton(
                    tab: .profile,
                    selectedTab: $selectedTab,
                    icon: { ProfileIconView(size: 24, color: $0) },
                    title: "Profile"
                )
            }
            .frame(width: buttonsWidth)
            .frame(width: pillWidth, height: pillHeight)
            .background(
                Capsule()
                    .fill(Color(.systemBackground))
            )
            .clipShape(Capsule())
            .shadow(color: Color.stridePrimary.opacity(0.20), radius: 25, x: 0, y: 4)
            .padding(.bottom, bottomOffset)
        }
        .frame(height: blurHeight)
        .ignoresSafeArea(edges: .bottom)
    }
}

// MARK: - Tab Bar Button
struct TabBarButton<Icon: View>: View {
    let tab: MainTabView.Tab
    @Binding var selectedTab: MainTabView.Tab
    let icon: (Color) -> Icon
    let title: String
    
    private var isSelected: Bool {
        selectedTab == tab
    }
    
    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
            }
        }) {
            VStack(spacing: 4) {
                icon(isSelected ? .stridePrimary : .black)
                    .frame(width: 30, height: 30)
                
                Text(title)
                    .font(.inter(size: 12, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? .stridePrimary : .black)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Run Tab Container
struct RunTabContainer: View {
    @EnvironmentObject private var bluetoothManager: BluetoothManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Workout.date) private var allWorkouts: [Workout]
    @Query(filter: #Predicate<Shoe> { $0.isRetired == false }, sort: \Shoe.name) private var shoes: [Shoe]
    @StateObject private var viewModel = RunViewModel()
    @State private var runState: RunState = .lobby
    
    @Binding var hideTabBar: Bool
    @Binding var selectedTab: MainTabView.Tab

    enum RunState {
        case lobby
        case active
        case summary(RunResult, Int?)  // result + optional score
    }

    var body: some View {
        Group {
            switch runState {
            case .lobby:
                RunLobbyView(
                    onStartPlannedWorkout: { workout in
                        viewModel.reset()
                        viewModel.loadPlannedWorkout(workout)
                        viewModel.attach(bluetoothManager: bluetoothManager)
                        PostHogSDK.shared.capture("run_started", properties: ["is_planned": true])
                        withAnimation {
                            runState = .active
                            hideTabBar = true
                        }
                    },
                    onStartFreeRun: {
                        viewModel.reset()
                        viewModel.attach(bluetoothManager: bluetoothManager)
                        PostHogSDK.shared.capture("run_started", properties: ["is_planned": false])
                        withAnimation {
                            runState = .active
                            hideTabBar = true
                        }
                    }
                )
                
            case .active:
                RunView(viewModel: viewModel, onFinishRun: {
                    let result = viewModel.buildRunResult()
                    let score = RunScoringService.calculateScore(result: result)
                    withAnimation {
                        runState = .summary(result, score)
                    }
                })
                
            case .summary(let result, let score):
                RunSummaryView(result: result, score: score, shoes: Array(shoes), onSave: { feedbackRating, notes, shoeId, shoeName in
                    PostHogSDK.shared.capture("run_completed", properties: [
                        "distance_km": result.distanceKm,
                        "duration_seconds": result.durationSeconds,
                        "is_planned": result.isPlannedRun,
                    ])
                    saveRun(result: result, score: score, feedbackRating: feedbackRating, notes: notes, shoeId: shoeId, shoeName: shoeName)
                    viewModel.reset()
                    withAnimation {
                        runState = .lobby
                        hideTabBar = false
                        selectedTab = .stats
                    }
                })
            }
        }
    }
    
    // MARK: - Persistence
    
    private func saveRun(result: RunResult, score: Int?, feedbackRating: Int?, notes: String, shoeId: UUID? = nil, shoeName: String? = nil) {
        // Encode km splits to JSON
        let splitsJSON: String? = {
            let codableSplits = result.kmSplits.map { split in
                CodableKilometerSplit(
                    kilometer: split.kilometer,
                    pace: split.pace,
                    time: split.time,
                    isFastest: split.isFastest
                )
            }
            guard let data = try? JSONEncoder().encode(codableSplits) else { return nil }
            return String(data: data, encoding: .utf8)
        }()

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesValue = trimmedNotes.isEmpty ? nil : trimmedNotes

        // A) Always create a RunLog — the authoritative run record
        let workout: Workout? = result.plannedWorkoutId.flatMap { wid in
            allWorkouts.first { $0.id == wid }
        }

        let runLog = RunLog(
            distanceKm: result.distanceKm,
            durationSeconds: result.durationSeconds,
            avgPaceSecPerKm: result.avgPaceSecPerKm,
            kmSplitsJSON: splitsJSON,
            feedbackRating: feedbackRating,
            notes: notesValue,
            dataSource: result.dataSource,
            treadmillBrand: result.treadmillBrand,
            shoeId: shoeId,
            shoeName: shoeName,
            plannedWorkoutId: result.plannedWorkoutId,
            plannedWorkoutTitle: workout?.title ?? result.plannedWorkoutTitle,
            plannedWorkoutTypeRaw: workout?.workoutTypeRaw ?? result.plannedWorkoutType?.rawValue,
            plannedDistanceKm: workout?.distanceKm ?? result.targetDistanceKm,
            plannedDurationMinutes: workout?.durationMinutes ?? result.targetDurationMinutes,
            plannedPaceDescription: workout?.paceDescription ?? result.targetPaceDescription,
            completionScore: result.isPlannedRun ? score : nil,
            planName: workout?.week?.plan?.raceName ?? workout?.week?.plan?.displayDistance,
            weekNumber: workout?.week?.weekNumber
        )
        modelContext.insert(runLog)

        // B) For planned runs, also update Workout as a display cache
        if let workout {
            workout.isCompleted = true
            workout.completedAt = Date()
            workout.actualDistanceKm = result.distanceKm
            workout.actualDurationSeconds = result.durationSeconds
            workout.actualAvgPaceSecPerKm = result.avgPaceSecPerKm
            workout.completionScore = score
            workout.kmSplitsJSON = splitsJSON
            workout.feedbackRating = feedbackRating
            workout.notes = notesValue
        }

        // C) Free runs only produce a RunLog — no Workout object created

        // D) Update local shoe mileage
        if let shoeId, let shoe = shoes.first(where: { $0.id == shoeId }) {
            shoe.totalDistanceKm += result.distanceKm
        }

        try? modelContext.save()

        // Sync to server
        RunSyncService.shared.syncPendingRuns()

        // Haptic feedback
        Haptics.notification(.success)
    }
}

// MARK: - Plan Tab Container
struct PlanTabContainer: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<TrainingPlan> { $0.isArchived == false }, sort: \TrainingPlan.createdAt, order: .reverse) private var plans: [TrainingPlan]
    @State private var showOnboarding = false
    
    var body: some View {
        Group {
            if let plan = plans.first {
                PlanView(plan: plan)
            } else {
                EmptyStateView(showOnboarding: $showOnboarding)
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingContainerView()
        }
        .onAppear {
            archiveExtraPlans()
        }
    }

    /// Keep only the most recent plan, archive all others
    private func archiveExtraPlans() {
        guard plans.count > 1 else { return }
        for plan in plans.dropFirst() {
            plan.isArchived = true
            plan.archivedAt = Date()
            plan.archiveReason = .replaced
        }
        try? modelContext.save()
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    @Binding var showOnboarding: Bool
    
    var body: some View {
        GeometryReader { geometry in
            let logoHeight = geometry.size.width * 88.0 / 402.0
            let buttonWidth = geometry.size.width * 236.0 / 402.0
            
            VStack(spacing: 0) {
                Spacer()
                
                // Stride Logo
                StrideLogoView(height: logoHeight)
                
                Spacer()
                    .frame(height: 32)
                
                // Title
                Text("WELCOME TO STRIDE")
                    .font(.barlowCondensed(size: 32, weight: .medium))
                
                Spacer()
                    .frame(height: 32)
                
                // Body text - specific line breaks
                Text("I'm your personal training coach. I'll build a\nplan around your goals, your schedule, and\nhow you actually run.")
                    .font(.inter(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                
                Spacer()
                    .frame(height: 32)
                
                // CTA Button
                Button(action: {
                    PostHogSDK.shared.capture("onboarding_started")
                    showOnboarding = true
                }) {
                    Text("Start Building My Plan")
                        .font(.inter(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: buttonWidth)
                        .padding(.vertical, 18)
                        .background(Color.stridePrimary)
                        .clipShape(Capsule())
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Race Type Badge
struct RaceTypeBadge: View {
    let raceType: RaceType
    var customDistanceKm: Double? = nil

    var badgeText: String {
        if raceType == .custom, let km = customDistanceKm {
            if km >= 50 { return "\(Int(km))K" }
            return "\(Int(km)) km"
        }
        return raceType.shortName
    }

    var body: some View {
        Text(badgeText)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.stridePrimary.opacity(0.2))
            .foregroundStyle(Color.stridePrimary)
            .clipShape(Capsule())
    }
}

// MARK: - UIColor Extension for Hex
extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}

#Preview {
    MainTabView()
        .modelContainer(for: TrainingPlan.self, inMemory: true)
}
