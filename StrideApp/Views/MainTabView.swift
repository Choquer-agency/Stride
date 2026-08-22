import SwiftUI
import SwiftData
import PostHog

struct MainTabView: View {
    @State private var selectedTab: Tab = .plan
    @State private var hideTabBar: Bool = false

    // Coach deep links (push taps) presented as sheets over whatever tab is active.
    @ObservedObject private var deepLinkRouter = DeepLinkRouter.shared
    @State private var presentedCheckinId: String?
    @State private var showCheckinFlow = false
    @State private var presentedReviewEventId: UUID?
    @State private var showReview = false
    @State private var showCoachInbox = false
    
    enum Tab: Int {
        case run = 0
        case plan = 1
        case stats = 2
        case profile = 3

        var title: String {
            switch self {
            case .run: return "Run"
            case .plan: return "Plan"
            case .stats: return "Stats"
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
                case .profile:
                    NavigationStack {
                        ProfileView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !hideTabBar {
                    Color.clear.frame(height: 72)
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
        .onAppear { consumeDeepLinkIfNeeded(deepLinkRouter.pendingLink) }
        .onChange(of: deepLinkRouter.pendingLink) { _, link in
            consumeDeepLinkIfNeeded(link)
        }
        .fullScreenCover(isPresented: $showCheckinFlow) {
            WeeklyCheckinFlowView(checkinId: presentedCheckinId)
        }
        .sheet(isPresented: $showReview) {
            if let eventId = presentedReviewEventId {
                WeeklyReviewCardView(eventId: eventId)
            }
        }
        .sheet(isPresented: $showCoachInbox) {
            NavigationStack { CoachInboxView() }
        }
    }

    /// Consume the coach deep links this tab container owns. Garmin links stay
    /// with IntegrationsSection; unhandled links remain pending for other views.
    private func consumeDeepLinkIfNeeded(_ link: DeepLink?) {
        guard let link else { return }
        switch link {
        case .coachCheckin(let checkinId):
            presentedCheckinId = checkinId
            showCheckinFlow = true
            deepLinkRouter.consume()
        case .coachWeeklyReview(let eventIdString):
            if let eventId = UUID(uuidString: eventIdString) {
                presentedReviewEventId = eventId
                showReview = true
            }
            deepLinkRouter.consume()
        case .coachInbox:
            showCoachInbox = true
            deepLinkRouter.consume()
        default:
            break
        }
    }
}

// MARK: - Custom Tab Bar
struct CustomTabBar: View {
    @Binding var selectedTab: MainTabView.Tab
    let screenWidth: CGFloat
    
    private var pillWidth: CGFloat { min(screenWidth - 32, 430) }
    private var pillHeight: CGFloat { 64 }
    private var buttonsWidth: CGFloat { pillWidth - 12 }
    private var bottomOffset: CGFloat { 8 }
    private var blurHeight: CGFloat { 92 }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(.thinMaterial)
                .frame(maxWidth: .infinity)
                .frame(height: blurHeight)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.35), location: 0.45),
                            .init(color: .black, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            HStack(spacing: 0) {
                TabBarButton(
                    tab: .run,
                    selectedTab: $selectedTab,
                    icon: { color in FlagIconView(size: 23, color: color) },
                    title: "Run"
                )
                
                TabBarButton(
                    tab: .plan,
                    selectedTab: $selectedTab,
                    icon: { color in
                        Image(systemName: "calendar")
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(color)
                    },
                    title: "Plan"
                )
                
                TabBarButton(
                    tab: .stats,
                    selectedTab: $selectedTab,
                    icon: { color in
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(color)
                    },
                    title: "Stats"
                )

                TabBarButton(
                    tab: .profile,
                    selectedTab: $selectedTab,
                    icon: { color in
                        Image(systemName: "person")
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(color)
                    },
                    title: "Profile"
                )
            }
            .frame(width: buttonsWidth)
            .frame(width: pillWidth, height: pillHeight)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
            )
            .overlay(Capsule().stroke(Color.black.opacity(0.06), lineWidth: 1))
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.10), radius: 18, x: 0, y: 6)
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
            VStack(spacing: 3) {
                icon(isSelected ? .stridePrimary : Color(.secondaryLabel))
                    .frame(width: 34, height: 32)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.stridePrimary.opacity(0.10) : .clear)
                            .frame(width: 34, height: 34)
                    )
                
                Text(title)
                    .font(.inter(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .stridePrimary : Color(.secondaryLabel))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Run Tab Container
struct RunTabContainer: View {
    @EnvironmentObject private var bluetoothManager: BluetoothManager
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Workout.date) private var allWorkouts: [Workout]
    @Query(filter: #Predicate<Shoe> { $0.isRetired == false }, sort: \Shoe.name) private var shoes: [Shoe]
    @StateObject private var viewModel = RunViewModel()
    @State private var runState: RunState = .lobby
    @State private var isOutdoorMode: Bool = false

    @Binding var hideTabBar: Bool
    @Binding var selectedTab: MainTabView.Tab

    enum RunState {
        case lobby
        case active
        case summary(RunResult, Int?)  // result + optional score
    }

    @ViewBuilder
    var body: some View {
        switch runState {
            case .lobby:
                RunLobbyView(
                    onStartPlannedWorkout: { workout, outdoor in
                        isOutdoorMode = outdoor
                        viewModel.reset()
                        viewModel.loadPlannedWorkout(workout)
                        PostHogSDK.shared.capture("run_started", properties: ["is_planned": true, "mode": outdoor ? "outdoor" : "treadmill"])
                        withAnimation {
                            runState = .active
                            hideTabBar = true
                        }
                    },
                    onStartFreeRun: { outdoor, targetDistanceKm, targetDurationMinutes in
                        isOutdoorMode = outdoor
                        viewModel.reset()
                        // Set free run targets so voice coach can announce progress milestones
                        viewModel.targetDistanceKm = targetDistanceKm
                        viewModel.targetDurationMinutes = targetDurationMinutes
                        PostHogSDK.shared.capture("run_started", properties: ["is_planned": false, "mode": outdoor ? "outdoor" : "treadmill"])
                        withAnimation {
                            runState = .active
                            hideTabBar = true
                        }
                    }
                )

            case .active:
                if isOutdoorMode {
                    OutdoorRunView(viewModel: viewModel, onStartRun: {
                        let provider = makeProvider(outdoor: true)
                        viewModel.attach(provider: provider)
                    }, onFinishRun: {
                        let result = viewModel.buildRunResult()
                        viewModel.stopRun()
                        let score = RunScoringService.calculateScore(result: result)
                        withAnimation {
                            runState = .summary(result, score)
                        }
                    })
                } else {
                    RunView(viewModel: viewModel, onFinishRun: {
                        let result = viewModel.buildRunResult()
                        viewModel.stopRun()
                        let score = RunScoringService.calculateScore(result: result)
                        withAnimation {
                            runState = .summary(result, score)
                        }
                    })
                    // Treadmill runs have no in-view "begin" tap (they start when
                    // belt data arrives) — attach the provider here, or the run
                    // screen never hears a single packet.
                    .onAppear {
                        if !viewModel.hasActiveProvider {
                            viewModel.attach(provider: makeProvider(outdoor: false))
                        }
                    }
                }
                
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

    // MARK: - Provider Factory

    private func makeProvider(outdoor: Bool) -> RunDataProvider {
        if outdoor {
            return GPSRunDataProvider(locationManager: locationManager)
        } else {
            return BluetoothRunDataProvider(bluetoothManager: bluetoothManager)
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
            routeJSON: result.routeJSON,
            elevationGainMeters: result.elevationGainMeters,
            elevationLossMeters: result.elevationLossMeters,
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
    @State private var showBeginnerOnboarding = false

    var body: some View {
        Group {
            if let plan = plans.first {
                PlanView(plan: plan)
            } else {
                EmptyStateView(
                    showOnboarding: $showOnboarding,
                    showBeginnerOnboarding: $showBeginnerOnboarding
                )
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingContainerView()
        }
        .fullScreenCover(isPresented: $showBeginnerOnboarding) {
            BeginnerOnboardingContainerView()
        }
        .onAppear {
            archiveExtraPlans()
        }
        .task {
            // Fresh install: adopt a coach-authored server plan if one is
            // waiting (no-op when a local plan exists — PlanView reconciles).
            if plans.isEmpty {
                await PlanSyncService.shared.reconcile(context: modelContext)
            }
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
    @Binding var showBeginnerOnboarding: Bool

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
                    .frame(height: 16)

                // Beginner flow — tailored onboarding with runs, Peloton rides,
                // and light strength sessions.
                Button(action: {
                    PostHogSDK.shared.capture("onboarding_started_beginner")
                    showBeginnerOnboarding = true
                }) {
                    Text("Create Plan – M")
                        .font(.inter(size: 14, weight: .medium))
                        .foregroundColor(.stridePrimary)
                        .frame(width: buttonWidth)
                        .padding(.vertical, 14)
                        .overlay(
                            Capsule()
                                .stroke(Color.stridePrimary.opacity(0.4), lineWidth: 1)
                        )
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
