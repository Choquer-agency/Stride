import SwiftUI
import SwiftData
import CoreLocation
import PostHog

struct MainTabView: View {
    @AppStorage(RunLobbyAppearance.storageKey) private var appearanceRaw = RunLobbyAppearance.black.rawValue
    @ObservedObject private var heartRateAuth = AuthService.shared
    @ObservedObject private var heartRate = HeartRateManager.shared
    @State private var selectedTab: Tab =
        ProcessInfo.processInfo.arguments.contains("--runview-demo-plan") ? .plan :
        (ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--runview-demo") }) ? .run : .plan)
    @State private var hideTabBar: Bool = false
    @State private var runInProgress = false
    @StateObject private var runViewModel = RunViewModel()
    private var appearance: RunLobbyAppearance { RunLobbyAppearance(rawValue: appearanceRaw) ?? .black }

    // Coach deep links (push taps) presented as sheets over whatever tab is active.
    @ObservedObject private var deepLinkRouter = DeepLinkRouter.shared
    @State private var presentedCheckinId: String?
    @State private var showCheckinFlow = false
    @State private var presentedReviewEventId: UUID?
    @State private var showReview = false
    @State private var showCoachInbox = false
    @State private var showCoachChat = false
    
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
            VStack(spacing: 0) {
                appHeader
                ZStack {
                    // Keep the run view and its session mounted across tab changes.
                    // Recreating this branch would discard the run and replay countdowns.
                    NavigationStack {
                        RunTabContainer(
                            viewModel: runViewModel,
                            hideTabBar: $hideTabBar,
                            selectedTab: $selectedTab,
                            runInProgress: $runInProgress
                        )
                    }
                    .opacity(selectedTab == .run ? 1 : 0)
                    .allowsHitTesting(selectedTab == .run)
                    .accessibilityHidden(selectedTab != .run)

                    switch selectedTab {
                    case .run:
                        EmptyView()
                    case .plan:
                        PlanTabContainer(onOpenProfile: { selectedTab = .profile })
                    case .stats:
                        NavigationStack {
                            StatsView(selectedTab: $selectedTab)
                        }
                    case .profile:
                        NavigationStack {
                            ProfileView(onOpenPlan: { selectedTab = .plan })
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if selectedTab != .run || !hideTabBar {
                    CustomTabBar(selectedTab: $selectedTab, screenWidth: geometry.size.width)
                        .animation(.none, value: selectedTab)
                }
            }
            .background {
                if selectedTab == .run && !hideTabBar { RunLobbyBackdrop().ignoresSafeArea() }
                else if selectedTab == .plan { PlanPageBackdrop().ignoresSafeArea() }
                else if selectedTab == .stats || selectedTab == .profile { StridePageBackdrop().ignoresSafeArea() }
                else { Color(.systemBackground).ignoresSafeArea() }
            }
        }

        .ignoresSafeArea(.keyboard, edges: .bottom)
        .preferredColorScheme(appearance.colorScheme)
        .onChange(of: heartRateAuth.currentUserID) { _, _ in
            heartRate.accountDidChange()
            heartRate.startScanning(owner: "app")
        }
        .onChange(of: hideTabBar) { _, hidden in RunLobbyPresentation.shared.isVisible = (selectedTab == .run && !hidden) || selectedTab == .plan }
        .onChange(of: selectedTab) { _, newTab in
            RunLobbyPresentation.shared.isVisible = (newTab == .run && !hideTabBar) || newTab == .plan
            PostHogSDK.shared.capture("tab_switched", properties: ["tab": newTab.title])
        }
        .onReceive(NotificationCenter.default.publisher(for: .strideSwitchToRunTab)) { _ in
            selectedTab = .run
        }
        .onAppear {
            if UserDefaults.standard.bool(forKey: "strideOpenRunFromActivity") {
                selectedTab = .run
                UserDefaults.standard.removeObject(forKey: "strideOpenRunFromActivity")
            }
            RunLobbyPresentation.shared.isVisible = (selectedTab == .run && !hideTabBar) || selectedTab == .plan
            heartRate.startScanning(owner: "app")
            consumeDeepLinkIfNeeded(deepLinkRouter.pendingLink)
        }
        .onDisappear {
            RunLobbyPresentation.shared.isVisible = false
            heartRate.stopAndDisconnect(owner: "app")
        }
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
        .sheet(isPresented: $showCoachChat) {
            NavigationStack { CoachChatView(trainingPlanId: nil) }
        }
    }

    private var appHeader: some View {
        VStack(spacing: 0) {
            if runInProgress && selectedTab != .run {
                Button {
                    selectedTab = .run
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: runViewModel.isPaused ? "pause.circle.fill" : "figure.run")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(runViewModel.isPaused ? "Run paused" : "Run in progress")
                                .font(.inter(size: 14, weight: .semibold))
                            Text(String(format: "%.2f km · %d:%02d",
                                        runViewModel.distance,
                                        Int(runViewModel.elapsedTime) / 60,
                                        Int(runViewModel.elapsedTime) % 60))
                                .font(.inter(size: 12, weight: .medium))
                                .monospacedDigit()
                        }
                        Spacer()
                        Text("Return to run")
                            .font(.inter(size: 14, weight: .semibold))
                        Image(systemName: "chevron.right")
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Color.stridePrimary)
                }
                .buttonStyle(.plain)
            }
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
        case .coachPlan:
            selectedTab = .plan
            deepLinkRouter.consume()
        case .coachChat:
            showCoachChat = true
            deepLinkRouter.consume()
        default:
            break
        }
    }
}

// MARK: - Custom Tab Bar
struct CustomTabBar: View {
    @AppStorage(RunLobbyAppearance.storageKey) private var appearanceRaw = RunLobbyAppearance.black.rawValue
    @Binding var selectedTab: MainTabView.Tab
    let screenWidth: CGFloat
    private var appearance: RunLobbyAppearance { RunLobbyAppearance(rawValue: appearanceRaw) ?? .black }
    private var style: StridePageStyle { .init(appearance: appearance) }
    private var pillWidth: CGFloat { min(screenWidth - 32, 430) }
    var body: some View {
        HStack(spacing: 3) {
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
        .padding(6)
        .frame(width: pillWidth, height: 68)
        .stridePageCard(style, radius: 26)
        .shadow(color: .black.opacity(appearance == .white ? 0.10 : 0.23), radius: 18, y: 6)
        .frame(maxWidth: .infinity)
        .frame(height: 82)
    }
}

// MARK: - Tab Bar Button
struct TabBarButton<Icon: View>: View {
    @AppStorage(RunLobbyAppearance.storageKey) private var appearanceRaw = RunLobbyAppearance.black.rawValue
    let tab: MainTabView.Tab
    @Binding var selectedTab: MainTabView.Tab
    let icon: (Color) -> Icon
    let title: String
    
    private var isSelected: Bool {
        selectedTab == tab
    }
    private var appearance: RunLobbyAppearance { RunLobbyAppearance(rawValue: appearanceRaw) ?? .black }
    private var style: StridePageStyle { .init(appearance: appearance) }
    private var selectedFill: Color { appearance == .red ? .white : .stridePrimary }
    private var selectedInk: Color { appearance == .red ? .stridePrimary : .white }
    
    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
            }
        }) {
            VStack(spacing: 1) {
                icon(isSelected ? selectedInk : style.muted)
                    .frame(height: 26)
                Text(title.uppercased())
                    .font(.barlowCondensed(size: 14))
                    .tracking(0.6)
                    .foregroundStyle(isSelected ? selectedInk : style.muted)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 55)
            .background(isSelected ? selectedFill : .clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
    @ObservedObject var viewModel: RunViewModel
    @State private var runState: RunState = .lobby
    @State private var isOutdoorMode: Bool = false
    @State private var runSaveError: String?

    @Binding var hideTabBar: Bool
    @Binding var selectedTab: MainTabView.Tab
    @Binding var runInProgress: Bool

    private var isActiveRun: Bool {
        if case .active = runState { return true }
        return false
    }

    enum RunState {
        case lobby
        case active
        case summary(RunResult, Int?)  // result + optional score
    }

    @ViewBuilder
    var body: some View {
        content
            .onChange(of: isActiveRun, initial: true) { _, active in
                runInProgress = active
            }
            .onAppear {
                restoreInterruptedRunIfNeeded()
                seedDemoRunIfRequested()
                if !isActiveRun {
                    Task { @MainActor in
                        RunLiveActivityCoordinator.shared.endOrphanedActivities()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .strideStartPlannedWorkout)) { notification in
                guard let workout = notification.object as? Workout else { return }
                selectedTab = .run
                guard case .lobby = runState else { return }
                isOutdoorMode = allowedOutdoorMode(UserDefaults.standard.string(forKey: "lastRunMode") != RunMode.treadmill.rawValue)
                viewModel.reset()
                protectRunSession()
                viewModel.loadPlannedWorkout(workout)
                PostHogSDK.shared.capture("run_started", properties: ["is_planned": true, "mode": isOutdoorMode ? "outdoor" : "treadmill"])
                withAnimation {
                    runState = .active
                    hideTabBar = true
                }
            }
            .alert("Run wasn't saved", isPresented: Binding(
                get: { runSaveError != nil }, set: { if !$0 { runSaveError = nil } }
            )) {
                Button("OK", role: .cancel) { runSaveError = nil }
            } message: {
                Text(runSaveError ?? "Your recovery checkpoint is still available. Try saving again.")
            }
            .onChange(of: viewModel.workoutCompleted) { _, completed in
                guard completed, case .active = runState else { return }
                let result = viewModel.buildRunResult()
                withAnimation {
                    runState = .summary(result, RunScoringService.calculateScore(result: result))
                    selectedTab = .run
                }
            }
    }

    /// UI-iteration hook: launch with --runview-demo to land straight on the
    /// treadmill run screen with realistic mid-run state. No effect otherwise.
    private func seedDemoRunIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        let wantsIntervals = args.contains("--runview-demo-intervals") || args.contains("--runview-demo-warmup")
        let wantsOutdoor = args.contains("--runview-demo-outdoor") || args.contains("--runview-demo-countdown")
        guard args.contains(where: { $0.hasPrefix("--runview-demo") }),
              !args.contains("--runview-demo-lobby"),
              !args.contains("--runview-demo-plan"),
              case .lobby = runState else { return }
        viewModel.isPlannedRun = true
        viewModel.plannedWorkoutTitle = "Long Run"
        viewModel.plannedWorkoutType = .longRun
        viewModel.targetDistanceKm = 12
        viewModel.targetPaceMinSec = 360
        viewModel.targetPaceMaxSec = 390
        viewModel.paceZone = .onPace
        viewModel.distance = 5.43
        viewModel.elapsedTime = 34 * 60 + 9
        viewModel.currentPace = "6:25"
        viewModel.paceDrift = "+3.0s"
        viewModel.paceGraphPaces = [383, 385, 384, 386, 385, 383, 382, 384, 386, 388,
                                    385, 383, 384, 500, 545, 548, 544, 470, 392, 386,
                                    384, 383, 385, 384, 386, 385]
        viewModel.speedKmh = 9.35
        viewModel.heartRate = 142
        viewModel.hrSourceConnected = true
        viewModel.paceGraphHeartRates = viewModel.paceGraphPaces.enumerated().map { index, _ in 137 + index % 12 }
        viewModel.paceGraphDistances = viewModel.paceGraphPaces.indices.map { Double($0) * 20 }
        viewModel.kilometerSplits = [
            KilometerSplit(kilometer: 1, pace: "6:24", time: "6:24", isFastest: false, diffFromFastest: 4),
            KilometerSplit(kilometer: 2, pace: "6:20", time: "12:44", isFastest: true, diffFromFastest: 0),
            KilometerSplit(kilometer: 3, pace: "6:28", time: "19:12", isFastest: false, diffFromFastest: 8),
            KilometerSplit(kilometer: 4, pace: "6:23", time: "25:35", isFastest: false, diffFromFastest: 3),
            KilometerSplit(kilometer: 5, pace: "6:26", time: "32:01", isFastest: false, diffFromFastest: 6),
        ]
        if wantsIntervals {
            viewModel.plannedWorkoutTitle = "Fartlek"
            viewModel.plannedWorkoutType = .fartlek
            viewModel.targetDistanceKm = 8
            viewModel.intervalSegments = IntervalWorkoutParser.parse(
                """
                Warm-up: 2.5 km at 6:00–6:30/km
                Main set: 3 km of alternations — 10 × 1 min at roughly 4:45–5:00/km effort (RPE 7) with 1 min easy float between
                Cool-down: 2.5 km at 6:00–6:30/km
                """)
            viewModel.intervalIndex = 5      // work rep 3 of 10
            viewModel.intervalPhaseRemaining = 37
            viewModel.currentPace = "4:52"
            viewModel.distance = 3.61
            viewModel.elapsedTime = 19 * 60 + 42
        }
        if args.contains("--runview-demo-warmup") {
            viewModel.intervalIndex = 0
            viewModel.intervalPhaseDistanceDone = 1
            viewModel.distance = 1
            viewModel.elapsedTime = 6 * 60 + 12
        }
        if wantsIntervals, let segment = viewModel.currentIntervalSegment {
            viewModel.targetPaceMinSec = segment.paceBounds?.min
            viewModel.targetPaceMaxSec = segment.paceBounds?.max
        }
        if wantsOutdoor {
            if !wantsIntervals {
                viewModel.plannedWorkoutTitle = "Sunday Long Run"
                viewModel.targetDistanceKm = 26
                viewModel.distance = 14.20
                viewModel.elapsedTime = 88 * 60 + 4
                viewModel.currentPace = "6:12"
            }
            viewModel.heartRate = 141
            // Simulator-only route to review the live map styling without GPS.
            viewModel.routeCoordinates = [
                CLLocationCoordinate2D(latitude: 49.2774, longitude: -123.1205),
                CLLocationCoordinate2D(latitude: 49.2790, longitude: -123.1205),
                CLLocationCoordinate2D(latitude: 49.2798, longitude: -123.1220),
                CLLocationCoordinate2D(latitude: 49.2812, longitude: -123.1220),
                CLLocationCoordinate2D(latitude: 49.2827, longitude: -123.1207),
            ]
        }
        isOutdoorMode = wantsOutdoor
        runState = .active
        hideTabBar = true
        if args.contains("--runview-demo-paused") { viewModel.pauseRun() }
        if args.contains("--runview-demo-summary") {
            let duration = viewModel.elapsedTime
            let samples = stride(from: 0.0, through: duration, by: 5).enumerated().map { index, t in
                RunSpeedSample(t: t, kmh: 9.5 + sin(Double(index) / 14) * 0.7)
            }
            let hr = samples.enumerated().map { index, point in
                CodableHRSample(t: point.t, bpm: 132 + min(20, index / 10) + index % 4)
            }
            let result = RunResult(
                distanceKm: viewModel.distance, durationSeconds: duration,
                avgPaceSecPerKm: duration / viewModel.distance, kmSplits: viewModel.kilometerSplits,
                plannedWorkoutId: nil, plannedWorkoutTitle: "Long Run", plannedWorkoutType: .longRun,
                targetDistanceKm: 12, targetPaceDescription: "6:00–6:30/km", targetDurationMinutes: nil,
                dataSource: "bluetooth_ftms", treadmillBrand: "Assault Runner",
                routeJSON: nil, elevationGainMeters: nil, elevationLossMeters: nil,
                avgHeartRate: 145, maxHeartRate: 155,
                hrSamplesJSON: (try? JSONEncoder().encode(hr)).flatMap { String(data: $0, encoding: .utf8) },
                speedSamples: samples, totalPauseDurationSeconds: 0, completedPauseDurations: []
            )
            runState = .summary(result, nil)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch runState {
            case .lobby:
                RunLobbyView(
                    onStartPlannedWorkout: { workout, outdoor in
                        guard outdoor || bluetoothManager.hasFreshTreadmillData else { return }
                        isOutdoorMode = allowedOutdoorMode(outdoor)
                        viewModel.reset()
                        protectRunSession()
                        viewModel.loadPlannedWorkout(workout)
                        PostHogSDK.shared.capture("run_started", properties: ["is_planned": true, "mode": isOutdoorMode ? "outdoor" : "treadmill"])
                        withAnimation {
                            runState = .active
                            hideTabBar = true
                        }
                    },
                    onStartFreeRun: { outdoor, targetDistanceKm, targetDurationMinutes, targetPace in
                        guard outdoor || bluetoothManager.hasFreshTreadmillData else { return }
                        isOutdoorMode = allowedOutdoorMode(outdoor)
                        viewModel.reset()
                        protectRunSession()
                        // Set free run targets so voice coach can announce progress milestones
                        viewModel.targetDistanceKm = targetDistanceKm
                        viewModel.targetDurationMinutes = targetDurationMinutes
                        viewModel.targetPaceDescription = targetPace
                        if let range = RunScoringService.parsePaceRange(targetPace) {
                            viewModel.targetPaceMinSec = range.min == range.max ? range.min - 15 : range.min
                            viewModel.targetPaceMaxSec = range.min == range.max ? range.max + 15 : range.max
                        }
                        PostHogSDK.shared.capture("run_started", properties: ["is_planned": false, "mode": isOutdoorMode ? "outdoor" : "treadmill"])
                        withAnimation {
                            runState = .active
                            hideTabBar = true
                        }
                    },
                    onOpenProfile: { selectedTab = .profile }
                )

            case .active:
                if isOutdoorMode {
                    OutdoorRunView(viewModel: viewModel, onStartRun: {
                        if ProcessInfo.processInfo.arguments.contains("--runview-demo-countdown") { return }
                        guard !viewModel.hasActiveProvider else { return }
                        let provider = makeProvider(outdoor: true)
                        viewModel.attach(provider: provider)
                    }, onFinishRun: {
                        let result = viewModel.buildRunResult()
                        viewModel.stopRun()
                        let score = RunScoringService.calculateScore(result: result)
                        withAnimation {
                            runState = .summary(result, score)
                        }
                    }, onOpenApp: { selectedTab = .plan })
                } else {
                    RunView(viewModel: viewModel, onFinishRun: {
                        let result = viewModel.buildRunResult()
                        viewModel.stopRun()
                        let score = RunScoringService.calculateScore(result: result)
                        withAnimation {
                            runState = .summary(result, score)
                        }
                    }, onOpenApp: { selectedTab = .plan })
                    // Treadmill runs have no in-view "begin" tap (they start when
                    // belt data arrives) — attach the provider here, or the run
                    // screen never hears a single packet.
                    .onAppear {
                        // Keep simulator screenshot fixtures stable without starting a real run clock.
                        guard !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--runview-demo") }) else { return }
                        if !viewModel.hasActiveProvider {
                            viewModel.attach(provider: makeProvider(outdoor: false))
                        }
                    }
                }
                
            case .summary(let result, let score):
                RunSummaryView(result: result, score: score, shoes: Array(shoes), onSave: { feedbackRating, notes, shoeId, shoeName, coachNotes in
                    PostHogSDK.shared.capture("run_completed", properties: [
                        "distance_km": result.distanceKm,
                        "duration_seconds": result.durationSeconds,
                        "is_planned": result.isPlannedRun,
                    ])
                    guard saveRun(result: result, score: score, feedbackRating: feedbackRating, notes: notes, shoeId: shoeId, shoeName: shoeName, coachNotes: coachNotes) else { return }
                    if let owner = AuthService.shared.currentUserID { RunRecoveryStore.remove(ownerID: owner) }
                    viewModel.reset()
                    AuthService.shared.endWorkoutProtection(result.sessionID)
                    withAnimation {
                        runState = .lobby
                        hideTabBar = false
                        selectedTab = .stats
                    }
                })
        }
    }

    private func protectRunSession() {
        guard let owner = AuthService.shared.currentUserID else { return }
        viewModel.prepareRecovery(ownerID: owner)
        AuthService.shared.beginWorkoutProtection(viewModel.sessionID)
    }

    private func restoreInterruptedRunIfNeeded() {
        guard case .lobby = runState,
              !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--runview-demo") }),
              let owner = AuthService.shared.currentUserID,
              let checkpoint = RunRecoveryStore.load(ownerID: owner),
              checkpoint.result.distanceKm > 0 || checkpoint.result.durationSeconds > 0 else { return }
        let id = checkpoint.result.sessionID
        // A crash after a successful save must not insert the same run or mileage twice.
        let existing = (try? modelContext.fetch(FetchDescriptor<RunLog>(predicate: #Predicate { $0.id == id }))) ?? []
        guard existing.isEmpty else {
            RunRecoveryStore.remove(ownerID: owner)
            AuthService.shared.endWorkoutProtection(id)
            return
        }
        var result = checkpoint.result
        result.recoveryNotice = "Recovered interrupted run at the last saved checkpoint. Review and save these recorded values; any running after the checkpoint is not included."
        AuthService.shared.beginWorkoutProtection(result.sessionID)
        isOutdoorMode = result.isOutdoorRun
        runState = .summary(result, RunScoringService.calculateScore(result: result))
        selectedTab = .run
        hideTabBar = true
    }

    /// Enforce account access at each real run entry point as well as in the lobby.
    private func allowedOutdoorMode(_ requestedOutdoor: Bool) -> Bool {
        AccountRunCapabilities.forUserID(AuthService.shared.currentUserID)
            .resolvedMode(requestedOutdoor ? .outdoor : .treadmill) == .outdoor
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

    private func saveRun(result: RunResult, score: Int?, feedbackRating: Int?, notes: String, shoeId: UUID? = nil, shoeName: String? = nil, coachNotes: String? = nil) -> Bool {
        let sessionID = result.sessionID
        if let existing = try? modelContext.fetch(FetchDescriptor<RunLog>(predicate: #Predicate { $0.id == sessionID })), !existing.isEmpty { return true }
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
        let combinedNotes = [result.recoveryNotice, trimmedNotes.isEmpty ? nil : trimmedNotes].compactMap { $0 }.joined(separator: "\n")
        let notesValue = combinedNotes.isEmpty ? nil : combinedNotes

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
            avgHeartRate: result.avgHeartRate,
            maxHeartRate: result.maxHeartRate,
            hrSamplesJSON: result.hrSamplesJSON,
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
        if let encoded = try? JSONEncoder().encode(result.speedSamples), !result.speedSamples.isEmpty {
            runLog.speedSamplesJSON = String(data: encoded, encoding: .utf8)
        }
        let review = coachNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
        runLog.coachNotes = review?.isEmpty == false ? review : nil
        runLog.id = result.sessionID
        runLog.completedAt = result.completedAt
        modelContext.insert(runLog)

        // B) For planned runs, also update Workout as a display cache
        if let workout {
            // Flexible week: a session run on a different day than scheduled
            // moves to the day it was actually done.
            if workout.week?.plan?.isFlexibleSchedule == true,
               !Calendar.current.isDate(workout.date, inSameDayAs: result.completedAt) {
                workout.date = result.completedAt
            }
            workout.isCompleted = true
            workout.completedAt = result.completedAt
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

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            runSaveError = "Your run is still in the recovery checkpoint. Please try saving again."
            return false
        }

        // Sync to server
        RunSyncService.shared.syncPendingRuns()

        // Haptic feedback
        Haptics.notification(.success)
        return true
    }
}

// MARK: - Plan Tab Container
struct PlanTabContainer: View {
    var onOpenProfile: () -> Void = {}
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<TrainingPlan> { $0.isArchived == false }, sort: \TrainingPlan.createdAt, order: .reverse) private var plans: [TrainingPlan]
    @State private var showOnboarding = false
    @State private var showBeginnerOnboarding = false

    var body: some View {
        Group {
            if let plan = plans.first {
                PlanView(plan: plan, onOpenProfile: onOpenProfile)
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
