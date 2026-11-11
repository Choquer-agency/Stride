import SwiftUI
import SwiftData
import CoreLocation
import MapboxMaps

enum RunMode: String, CaseIterable {
    case treadmill
    case outdoor
}

/// Account-scoped run access. Unlisted accounts retain all existing modes.
/// Add only confirmed Stride user UUIDs here; names and Apple relay emails are not identities.
/// Remove an override (or change it to `.standard`) to restore indoor running after
/// treadmill support is validated. December/REP support is deliberately not date-triggered.
struct AccountRunCapabilities {
    let allowsIndoorRunning: Bool

    static let standard = AccountRunCapabilities(allowsIndoorRunning: true)
    static let outdoorOnly = AccountRunCapabilities(allowsIndoorRunning: false)

    // Carson confirmed from his newly created account; Nicole remains pending.
    static let accountOverrides: [UUID: AccountRunCapabilities] = [
        UUID(uuidString: "825f9687-6ad2-4d4d-b3f0-06ec974e8dba")!: .outdoorOnly
    ]

    static func forUserID(_ userID: String?,
                          overrides: [UUID: AccountRunCapabilities] = accountOverrides) -> AccountRunCapabilities {
        guard let userID, let id = UUID(uuidString: userID) else { return .standard }
        return overrides[id] ?? .standard
    }

    func resolvedMode(_ requested: RunMode) -> RunMode {
        requested == .treadmill && !allowsIndoorRunning ? .outdoor : requested
    }
}

struct RunLobbyView: View {
    @EnvironmentObject private var bluetoothManager: BluetoothManager
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var heartRate = HeartRateManager.shared
    @Query(filter: #Predicate<TrainingPlan> { $0.isArchived == false }, sort: \TrainingPlan.createdAt, order: .reverse) private var plans: [TrainingPlan]

    var onStartPlannedWorkout: (Workout, Bool) -> Void
    var onStartFreeRun: (_ outdoor: Bool, _ targetDistanceKm: Double?, _ targetDurationMinutes: Int?, _ targetPace: String?) -> Void

    @AppStorage("lastRunMode") private var runModeRaw: String = RunMode.outdoor.rawValue
    @AppStorage("runLobbyGymSelected") private var gymSelectedForBackdrop = false
    @State private var selectedTab: LobbyTab = .todaysWorkout
    /// Flexible week: the run the athlete picked from this week's list.
    @State private var selectedWeekWorkoutId: UUID? = nil
    @State private var selectedSessionID: UUID?
    @State private var openedSession: Workout?
    @State private var freeRunDistance: Double = 12.0
    @State private var freeRunDurationMinutes: Int = 30
    @State private var freeRunGoalMode: FreeRunGoalMode = .distance
    @State private var freeRunTargetPace: String? = nil
    @State private var showHeartRatePicker = false
    @State private var showPaceEditor = false
    @State private var showDistanceEditor = false
    @State private var connectionCheckTime = Date()

    enum FreeRunGoalMode: String {
        case distance
        case time
    }

    private var runMode: RunMode {
        get { runCapabilities.resolvedMode(RunMode(rawValue: runModeRaw) ?? .outdoor) }
    }

    private func setRunMode(_ mode: RunMode) {
        runModeRaw = runCapabilities.resolvedMode(mode).rawValue
    }

    enum LobbyTab {
        case todaysWorkout
        case freeRun
    }


    // MARK: - Computed Properties

    private var isConnected: Bool {
        _ = connectionCheckTime
        return bluetoothManager.hasFreshTreadmillData
    }

    private var isConnecting: Bool {
        !isConnected && (bluetoothManager.connectionState == "Connecting..."
            || bluetoothManager.connectionState.hasPrefix("Reconnecting")
            || bluetoothManager.connectedDevice != nil
            || bluetoothManager.isScanning)
    }

    private var isGPSReady: Bool {
        locationManager.authorizationStatus == .authorizedWhenInUse
        || locationManager.authorizationStatus == .authorizedAlways
    }

    /// Flexible week (plan flag): every run in the current Monday–Sunday week
    /// is startable on any day, in any order. Past weeks are closed, next
    /// week opens Monday.
    private var isFlexibleWeek: Bool {
        plans.first?.isFlexibleSchedule ?? false
    }

    private static func isRunSession(_ workout: Workout) -> Bool {
        workout.workoutType != .rest
            && workout.workoutType != .gym
            && workout.workoutType != .crossTraining
            && workout.workoutType != .mobility
    }

    /// This week's runs still to do (flexible week only), in calendar order.
    private var remainingWeekRuns: [Workout] {
        guard isFlexibleWeek,
              let plan = plans.first,
              let currentWeek = plan.currentWeek else { return [] }
        return currentWeek.sortedWorkouts.filter { !$0.isCompleted && Self.isRunSession($0) }
    }

    /// Keep every active session for the day, including strength. Flexible plans
    /// keep their existing pick-any-run behavior and add today's non-run work.
    private var todaysSessions: [Workout] {
        TrainingSessionSelection.lobby(workouts: plans.first?.currentWeek?.sortedWorkouts ?? [], flexible: isFlexibleWeek)
    }
    private var todaysWorkout: Workout? {
        TrainingSessionSelection.preferred(in: todaysSessions, selectedID: selectedSessionID, fallbackID: selectedWeekWorkoutId)
    }
    private var selectedSessionIsRun: Bool { selectedWorkout.map(Self.isRunSession) ?? true }
    private var modeLockedToIndoor: Bool { selectedWorkout?.workoutType == .gym }
    private var runCapabilities: AccountRunCapabilities {
        AccountRunCapabilities.forUserID(lobbyAuth.currentUserID)
    }
    private var availableModes: [RunMode] {
        modeLockedToIndoor || runCapabilities.allowsIndoorRunning ? [.outdoor, .treadmill] : [.outdoor]
    }
    private var visibleMode: RunMode { modeLockedToIndoor ? .treadmill : runMode }

    /// Today's planned run when it's already done — drives the "in the books" state.
    /// Flexible week: the most recent run done this week, once none remain.
    private var completedTodaysWorkout: Workout? {
        guard let plan = plans.first,
              let currentWeek = plan.currentWeek else { return nil }
        if isFlexibleWeek {
            return currentWeek.sortedWorkouts
                .filter { $0.isCompleted && Self.isRunSession($0) }
                .max { ($0.completedAt ?? $0.date) < ($1.completedAt ?? $1.date) }
        }
        return currentWeek.sortedWorkouts.first { workout in
            workout.isToday
            && workout.isCompleted
            && Self.isRunSession(workout)
        }
    }

    private var canStart: Bool {
        if let workout = selectedWorkout {
            if workout.isCompleted { return true }
            if !Self.isRunSession(workout) { return true }
        }
        if runMode == .treadmill {
            return isConnected
        }
        return true
    }

    // MARK: - Body
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: compactLayout ? 10 : 14) {
                lobbyHeader
                Spacer(minLength: 12)
                HStack(alignment: .top, spacing: 12) {
                    tabToggle
                    Spacer(minLength: 0)
                    if isFlexibleWeek && remainingWeekRuns.count > 1 {
                        Menu {
                            ForEach(remainingWeekRuns, id: \.id) { workout in
                                Button(weekChipLabel(for: workout)) { selectedWeekWorkoutId = workout.id; selectedSessionID = workout.id; selectedTab = .todaysWorkout }
                            }
                        } label: { Image(systemName: "calendar").frame(width: 30, height: 30) }
                        .accessibilityLabel("Choose this week’s run")
                    }
                }.buttonStyle(.plain).foregroundStyle(mutedInk)
                lobbyTitle
                sessionPages
                VStack(spacing: 10) {
                    readinessRow
                    startButton
                }
            }
            .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 10)
            .frame(maxWidth: 600).frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { lobbyAvailableHeight = geometry.size.height }
            .onChange(of: geometry.size.height) { _, height in lobbyAvailableHeight = height }
        }
        .foregroundStyle(ink)
        .modifier(LobbyTransparentNavigation())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: "\(runModeRaw)-\(selectedWorkout?.id.uuidString ?? "")") {
            while !Task.isCancelled && visibleMode == .outdoor {
                locationManager.requestCurrentLocation()
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
        .onChange(of: locationManager.authorizationStatus) { _, _ in locationManager.requestCurrentLocation() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { connectionCheckTime = $0 }
        .onChange(of: todaysWorkout?.id) { _, workoutId in
            if workoutId == nil { selectedTab = .freeRun }
            gymSelectedForBackdrop = modeLockedToIndoor
        }
        .onChange(of: selectedTab) { _, _ in gymSelectedForBackdrop = modeLockedToIndoor }
        .onAppear {
            #if DEBUG
            for theme in RunLobbyAppearance.allCases where ProcessInfo.processInfo.arguments.contains("--lobby-theme-" + theme.rawValue) {
                appearanceRaw = theme.rawValue
            }
            if ProcessInfo.processInfo.arguments.contains("--lobby-second-session"), todaysSessions.count > 1 { selectedSessionID = todaysSessions[1].id }
            if ProcessInfo.processInfo.arguments.contains("--lobby-free") { selectedTab = .freeRun }
            if ProcessInfo.processInfo.arguments.contains("--lobby-treadmill") { setRunMode(.treadmill) }
            if ProcessInfo.processInfo.arguments.contains("--lobby-outdoor") { setRunMode(.outdoor) }
            #endif
            if todaysWorkout == nil {
                selectedTab = .freeRun
            }
            gymSelectedForBackdrop = modeLockedToIndoor
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestPermission()
            }
        }
        .sheet(item: $openedSession) { workout in
            WorkoutDetailView(workout: workout) {
                workout.toggleCompletion()
                try? modelContext.save()
            }.preferredColorScheme(.light)
        }
        .sheet(isPresented: $showHeartRatePicker) {
            NavigationStack {
                HeartRateMonitorPicker()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showHeartRatePicker = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showDistanceEditor) {
            distanceTimeEditorSheet
        }
        .sheet(isPresented: $showPaceEditor) {
            paceEditorSheet
        }
    }

    // MARK: - Approved glass lobby
    @AppStorage(RunLobbyAppearance.storageKey) private var appearanceRaw = RunLobbyAppearance.black.rawValue
    @ObservedObject private var lobbyAuth = AuthService.shared
    @State private var lobbyAvailableHeight: CGFloat = 698
    private var compactLayout: Bool { lobbyAvailableHeight < 750 }
    private var sessionCardHeight: CGFloat { compactLayout ? 310 : 335 }
    var onOpenProfile: () -> Void = {}

    private var appearance: RunLobbyAppearance { RunLobbyAppearance(rawValue: appearanceRaw) ?? .black }
    private var ink: Color { appearance.foreground }
    private var mutedInk: Color { appearance.secondary }
    private var selectedWorkout: Workout? { selectedTab == .todaysWorkout ? todaysWorkout : nil }
    private var profileInitials: String {
        switch lobbyAuth.authState {
        case .signedIn(let user), .needsProfile(let user):
            let name = user.name ?? user.displayName ?? ""
            let initials = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
            return initials.isEmpty ? "You" : initials.uppercased()
        default: return "You"
        }
    }
    private func sessionNumber(for workout: Workout?) -> Int? {
        guard let workout, let plan = plans.first else { return nil }
        let runs = plan.sortedWeeks.flatMap(\.sortedWorkouts).filter(Self.isRunSession).sorted { $0.date < $1.date }
        return runs.firstIndex(where: { $0.id == workout.id }).map { $0 + 1 }
    }

    private var lobbyHeader: some View {
        StridePageHeader(profileAction: onOpenProfile)
    }

    private var lobbyDisplayTitle: String {
        let title = selectedWorkout?.title ?? (completedTodaysWorkout != nil && selectedTab == .todaysWorkout ? "Session complete" : "Free Run")
        return selectedWorkout?.workoutType == .gym ? "GYM" : title.uppercased()
    }

    private var lobbyTitle: some View {
        VStack(alignment: .leading, spacing: compactLayout ? 5 : 8) {
            HStack {
                Text(Date(), format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .textCase(.uppercase).font(.runEyebrow(10)).foregroundStyle(mutedInk)
                Spacer()
                HStack(spacing: 0) {
                    ForEach(availableModes, id: \.self) { mode in
                        Button { switchMode(mode) } label: {
                            Text(mode == .outdoor ? "OUTDOOR" : "INDOOR")
                                .font(.runEyebrow(9))
                                .foregroundStyle(modeLockedToIndoor && mode == .outdoor ? ink.opacity(0.5) : ink)
                                .padding(.horizontal, 9).padding(.vertical, compactLayout ? 6 : 9)
                                .background(visibleMode == mode ? ink.opacity(0.10) : .clear, in: Capsule())
                        }
                        .disabled(modeLockedToIndoor)
                        .accessibilityAddTraits(visibleMode == mode ? .isSelected : [])
                    }
                }
                .padding(4)
                .background { Capsule().fill(.ultraThinMaterial).opacity(modeLockedToIndoor ? 0.5 : 1) }
                .overlay(Capsule().stroke(ink.opacity(modeLockedToIndoor ? 0.06 : 0.12), lineWidth: 0.5))
                .accessibilityHint(modeLockedToIndoor ? "Indoor only for gym sessions" : (runCapabilities.allowsIndoorRunning ? "Choose outdoor or indoor running" : "Outdoor running"))
            }
            HStack(alignment: .center, spacing: 11) {
                if selectedTab == .todaysWorkout && todaysSessions.count > 1 {
                    let current = (todaysSessions.firstIndex(where: { $0.id == todaysWorkout?.id }) ?? 0) + 1
                    VStack(spacing: 0) {
                        Text("\(current)")
                        Rectangle().fill(Color.stridePrimary).frame(height: 1)
                        Text("\(todaysSessions.count)")
                    }
                    .font(.barlowCondensed(size: compactLayout ? 16 : 19))
                    .monospacedDigit()
                    .foregroundStyle(Color.stridePrimary)
                    .frame(width: 18, height: compactLayout ? 40 : 48)
                    .accessibilityLabel("Session \(current) of \(todaysSessions.count)")
                }
                Text(lobbyDisplayTitle)
                    .font(.barlowCondensed(size: compactLayout ? 40 : 48)).foregroundStyle(ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }.buttonStyle(.plain).foregroundStyle(ink)
    }

    private var sessionPages: some View {
        VStack(spacing: 8) {
            if selectedTab == .todaysWorkout && todaysSessions.count > 1 {
                TabView(selection: Binding(get: { todaysWorkout?.id }, set: { selectedSessionID = $0 })) {
                    ForEach(todaysSessions, id: \.id) { workout in
                        Group {
                            if Self.isRunSession(workout) { sessionCard(for: workout) }
                            else { strengthCard(workout) }
                        }
                        .padding(.horizontal, 9)
                        .tag(Optional(workout.id))
                    }
                }.tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: sessionCardHeight)
                HStack(spacing: 7) {
                    ForEach(todaysSessions, id: \.id) { workout in
                        Button { withAnimation { selectedSessionID = workout.id } } label: {
                            Circle().fill(todaysWorkout?.id == workout.id ? ink : ink.opacity(0.25)).frame(width: 5, height: 5).padding(.vertical, 5)
                        }.accessibilityLabel(workout.title).accessibilityAddTraits(todaysWorkout?.id == workout.id ? .isSelected : [])
                    }
                    Text("SWIPE FOR NEXT SESSION")
                        .font(.runEyebrow(9)).foregroundStyle(mutedInk).padding(.leading, 5)
                }.buttonStyle(.plain)
            } else if let workout = selectedWorkout, !Self.isRunSession(workout) {
                strengthCard(workout)
            } else { sessionCard(for: selectedWorkout) }
        }
    }
    private func strengthCard(_ workout: Workout) -> some View {
        let items = GymSessionModel.prescriptionItems(from: workout.details ?? workout.title)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(workout.workoutType == .gym ? "TODAY'S WORK" : workout.title.uppercased())
                    .font(.barlowCondensed(size: compactLayout ? 30 : 34))
                    .lineLimit(1).minimumScaleFactor(0.75)
                Spacer()
                Text("\(items.count) \(items.count == 1 ? "MOVE" : "MOVES")")
                    .font(.runEyebrow(9)).foregroundStyle(mutedInk)
            }.padding(.bottom, 12)
            Rectangle().fill(ink.opacity(0.12)).frame(height: 0.5)
            if items.isEmpty {
                Text(workout.details ?? workout.title)
                    .font(.inter(size: 14)).foregroundStyle(mutedInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 16)
            } else {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        let exercise = GymSessionModel.parseExercise(item)
                        HStack(alignment: .top, spacing: 12) {
                            Text(String(format: "%02d", index + 1))
                                .font(.runEyebrow(10)).foregroundStyle(Color.stridePrimary)
                                .frame(width: 24, alignment: .leading).padding(.top, 5)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(exercise.name.uppercased())
                                    .font(.barlowCondensed(size: 22)).foregroundStyle(ink)
                                if !exercise.scheme.isEmpty {
                                    Text(exercise.scheme).font(.inter(size: 12)).foregroundStyle(mutedInk)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(.vertical, 10)
                        if index < items.count - 1 {
                            Rectangle().fill(ink.opacity(0.08)).frame(height: 0.5)
                        }
                    }
                }.padding(.trailing, 6)
            }.frame(maxHeight: .infinity)
            if items.count > 3 {
                HStack {
                    Spacer()
                    Text("SCROLL FOR ALL MOVES ↓")
                        .font(.runEyebrow(9)).foregroundStyle(Color.stridePrimary)
                }.padding(.top, 7)
            }
            }
        }
        .padding(compactLayout ? 18 : 20).foregroundStyle(ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: sessionCardHeight, alignment: .top)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(
            LinearGradient(colors: [appearance == .white ? .white : .white.opacity(0.45), ink.opacity(0.12)],
                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.6))
        .accessibilityIdentifier("gymSessionCard")
    }

    private func sessionCard(for workout: Workout?) -> some View {
        VStack(alignment: .leading, spacing: compactLayout ? 10 : 14) {
            HStack {
                Text(sessionNumber(for: workout).map { String(format: "SESSION / %03d", $0) } ?? "FREE RUN")
                    .font(.runEyebrow(10)).foregroundStyle(mutedInk)
                Spacer()
                Label(runMode == .outdoor ? "OUTDOOR" : "TREADMILL", systemImage: runMode == .outdoor ? "location.north" : "waveform.path")
                    .font(.runEyebrow(9)).padding(.horizontal, 10).padding(.vertical, 7)
                    .overlay(Capsule().stroke(ink.opacity(0.16), lineWidth: 0.5))
            }
            if selectedTab == .freeRun {
                freeGoalControls
            } else if let workout {
                distanceDisplay(value: workout.distanceKm.map { String(format: "%.1f", $0) } ?? workout.durationMinutes.map(String.init) ?? "—",
                                unit: workout.distanceKm != nil ? "km" : "min")
            } else {
                distanceDisplay(value: "—", unit: "km")
            }
            Rectangle().fill(ink.opacity(0.12)).frame(height: 0.5)
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("TARGET PACE /KM").font(.runEyebrow(10)).foregroundStyle(mutedInk)
                    if selectedTab == .freeRun {
                        Button { showPaceEditor = true } label: {
                            Text(freeRunTargetPace.map(compactPace) ?? "Set pace")
                                .font(.barlowCondensed(size: compactLayout ? 29 : 32)).foregroundStyle(ink)
                        }.buttonStyle(.plain)
                    } else {
                        Text(workout?.paceDescription.map(compactPace) ?? "By effort")
                            .font(.barlowCondensed(size: compactLayout ? 29 : 32)).lineLimit(2).foregroundStyle(ink)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 8) {
                    Text("TARGET HEART RATE").font(.runEyebrow(10)).foregroundStyle(mutedInk)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(workout.flatMap { HeartRateZones.band(for: $0.workoutType) } ?? "—")
                            .font(.barlowCondensed(size: compactLayout ? 29 : 32))
                        Text("BPM").font(.runEyebrow(8)).foregroundStyle(mutedInk)
                    }
                }.frame(maxWidth: .infinity, alignment: .trailing)
            }
            Rectangle().fill(ink.opacity(0.12)).frame(height: 0.5)
            sessionFlow(for: workout)
        }
        .padding(compactLayout ? 18 : 20).foregroundStyle(ink)
        .frame(height: sessionCardHeight, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 26).fill(.ultraThinMaterial)
            if appearance == .red { RoundedRectangle(cornerRadius: 26).fill(Color.stridePrimary.opacity(0.10)) }
        }
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(
            LinearGradient(colors: [appearance == .white ? .white : .white.opacity(0.45), ink.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.6))
        .accessibilityIdentifier("runSessionCard")
    }

    private func distanceDisplay(value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value).font(.barlowCondensed(size: compactLayout ? 86 : 100)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6).frame(height: compactLayout ? (selectedTab == .freeRun ? 70 : 82) : 108, alignment: .bottom)
            Text(unit).font(.barlowCondensed(size: 29)).foregroundStyle(mutedInk)
            Spacer(minLength: 0)
        }.padding(.top, 2).padding(.bottom, 2)
    }

    private var freeGoalControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Menu {
                    Button("Distance") { freeRunGoalMode = .distance }
                    Button("Time") { freeRunGoalMode = .time }
                } label: {
                    Label(freeRunGoalMode == .distance ? "DISTANCE GOAL" : "TIME GOAL", systemImage: "chevron.down")
                        .font(.runEyebrow(10)).foregroundStyle(mutedInk)
                }
                Spacer()
                Button("Edit") { showDistanceEditor = true }.font(.runEyebrow(11)).foregroundStyle(ink)
            }
            Button { showDistanceEditor = true } label: {
                distanceDisplay(value: freeRunGoalMode == .distance ? String(format: "%.1f", freeRunDistance) : "\(freeRunDurationMinutes)",
                                unit: freeRunGoalMode == .distance ? "km" : "min")
            }.buttonStyle(.plain)
        }
    }

    private func sessionFlow(for workout: Workout?) -> some View {
        let levels = workout.map { RunSessionProfile.levels(details: $0.details, totalKm: $0.distanceKm, easyPace: $0.paceDescription,
            allowSteady: [WorkoutType.easyRun, .recovery, .longRun, .tempoRun, .race].contains($0.workoutType)) } ?? Array(repeating: 0.3, count: 48)
        return VStack(spacing: compactLayout ? 6 : 10) {
            HStack {
                Text("SESSION FLOW / \(workout?.workoutType.displayName.uppercased() ?? "FREE")")
                Spacer(minLength: 6)
                if let estimate = durationEstimate(for: workout) { Text(estimate) }
            }.font(.runEyebrow(9)).foregroundStyle(mutedInk)
            if levels.isEmpty {
                Text("See the session guide for this workout").font(.inter(size: 12)).foregroundStyle(mutedInk)
            } else {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                        RoundedRectangle(cornerRadius: 1).fill(Color.stridePrimary.opacity(appearance == .white ? 0.65 : 0.8))
                            .frame(maxWidth: .infinity).frame(height: 5 + (compactLayout ? 20 : 25) * level)
                    }
                }.frame(height: compactLayout ? 25 : 31, alignment: .bottom)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Planned session effort profile. \(workout?.details ?? "Steady effort")")
            }
        }
    }

    private func durationEstimate(for workout: Workout?) -> String? {
        if let duration = workout?.durationMinutes { return "\(duration) MIN" }
        guard let workout, let km = workout.distanceKm,
              let range = RunScoringService.parsePaceRange(workout.paceDescription) else { return nil }
        return "~\(Int((km * range.min / 60).rounded()))–\(Int((km * range.max / 60).rounded())) MIN"
    }

    private var readinessRow: some View {
        TimelineView(.periodic(from: .now, by: 2)) { context in
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Circle().fill(selectedSessionIsRun ? readinessColor(at: context.date) : Color.green).frame(width: 5, height: 5)
                    Text(selectedSessionIsRun ? readinessText(at: context.date) : "Guided session ready").lineLimit(2)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button { showHeartRatePicker = true } label: {
                    HStack(spacing: 5) {
                        if let bpm = heartRate.currentBPM, heartRate.isConnected {
                            Image(systemName: "heart.fill").foregroundStyle(Color.stridePrimary).font(.system(size: 9))
                            // Decorative connection pulse follows BPM; the number is the measured value.
                            LobbyHeartRatePulse(bpm: bpm).frame(width: 40, height: 16)
                            Text("\(bpm)").font(.barlowCondensed(size: 20))
                            Text("BPM · LIVE").font(.runEyebrow(8))
                        } else {
                            Image(systemName: "heart").foregroundStyle(Color.stridePrimary)
                            Text(heartRate.isConnected ? "HR waiting" : "HR monitor +")
                        }
                    }
                }.buttonStyle(.plain).accessibilityLabel(heartRate.currentBPM.map { "Heart rate \($0) beats per minute. Choose monitor" } ?? "Choose heart rate monitor")
            }.font(.runEyebrow(10)).foregroundStyle(mutedInk)
        }
    }

    private func gpsHasFix(at date: Date) -> Bool {
        guard isGPSReady, let fix = locationManager.currentLocation else { return false }
        return fix.horizontalAccuracy >= 0 && fix.horizontalAccuracy <= 50 && abs(fix.timestamp.timeIntervalSince(date)) < 30
    }
    private func readinessText(at date: Date) -> String {
        if visibleMode == .treadmill { return modeLockedToIndoor ? "Guided session ready" : modeStatusLabel(.treadmill) }
        if !isGPSReady { return "Enable location" }
        return gpsHasFix(at: date) ? "GPS ready" : "Finding GPS…"
    }
    private func readinessColor(at date: Date) -> Color {
        if visibleMode == .treadmill { return modeLockedToIndoor || isConnected ? .stridePrimary : .orange }
        return gpsHasFix(at: date) ? .stridePrimary : .orange
    }

    // MARK: - Tab Toggle

    private var tabToggle: some View {
        HStack(spacing: 24) {
            lobbyTabButton(.todaysWorkout, title: isFlexibleWeek ? "THIS WEEK’S SESSION" : "TODAY’S SESSION")
            lobbyTabButton(.freeRun, title: "FREE RUN")
        }.accessibilityElement(children: .contain).accessibilityLabel("Run session")
    }
    private func lobbyTabButton(_ tab: LobbyTab, title: String) -> some View {
        Button { selectedTab = tab } label: {
            Text(title).font(.runEyebrow(11)).foregroundStyle(selectedTab == tab ? ink : mutedInk)
                .padding(.bottom, 10)
                .overlay(alignment: .bottom) { Rectangle().fill(selectedTab == tab ? Color.stridePrimary : .clear).frame(height: 1.5) }
        }.buttonStyle(.plain).accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
    }

    // MARK: - Today's Workout Content

    // MARK: - Flexible Week Picker

    /// Chips for every run still open this week; the athlete taps the one
    /// she's about to do. Suggested day is shown, never enforced.
    private func weekRunPicker(current: Workout) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(remainingWeekRuns, id: \.id) { run in
                    let isSelected = run.id == current.id
                    Button {
                        selectedWeekWorkoutId = run.id
                    } label: {
                        VStack(spacing: 2) {
                            Text(run.shortDayOfWeek.uppercased())
                                .font(.inter(size: 10, weight: .semibold))
                                .foregroundColor(isSelected ? .white.opacity(0.85) : .secondary)
                            Text(weekChipLabel(for: run))
                                .font(.inter(size: 13, weight: .semibold))
                                .foregroundColor(isSelected ? .white : .primary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(isSelected ? Color.stridePrimary : Color(.secondarySystemBackground).opacity(0.9))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: 340)
    }

    private func weekChipLabel(for run: Workout) -> String {
        if let km = run.distanceKm, km > 0 {
            let dist = km == floor(km) ? "\(Int(km)) km" : String(format: "%.1f km", km)
            return "\(run.workoutType.displayName) · \(dist)"
        }
        if let mins = run.durationMinutes, mins > 0 {
            return "\(run.workoutType.displayName) · \(mins) min"
        }
        return run.workoutType.displayName
    }

    // MARK: - Completed Today Card

    private func completedTodayCard(_ workout: Workout) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28)).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 6) {
                Text(isFlexibleWeek ? "This week’s runs are in the books" : "Today’s session is in the books")
                    .font(.inter(size: 15, weight: .semibold))
                Text(completedSummary(for: workout))
                    .font(.inter(size: 12)).foregroundStyle(.secondary)
                Text(isFlexibleWeek ? "Next week opens Monday. Free Run is available below." : "Rest up for tomorrow. Free Run is available below.")
                    .font(.inter(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.green.opacity(0.18), lineWidth: 1))
    }

    private func completedSummary(for workout: Workout) -> String {
        var parts: [String] = [workout.title]
        if let km = workout.actualDistanceKm ?? workout.distanceKm {
            parts.append(km == floor(km) ? "\(Int(km)) km" : String(format: "%.1f km", km))
        }
        if let pace = workout.actualPaceDisplay {
            parts.append(pace)
        }
        return parts.joined(separator: "  ·  ")
    }

    private func compactPace(_ pace: String) -> String {
        pace
            .replacingOccurrences(of: " /km", with: "")
            .replacingOccurrences(of: "/km", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func switchMode(_ mode: RunMode) {
        guard !modeLockedToIndoor else { return }
        withAnimation(.easeInOut(duration: 0.25)) { setRunMode(mode) }
    }

    private func modeStatusLabel(_ mode: RunMode) -> String {
        if mode == .outdoor {
            return isGPSReady ? "Ready" : "GPS Unavailable"
        } else {
            if isConnected {
                // "Connected" alone can lie — show whether data actually flows.
                if bluetoothManager.packetCount > 0 {
                    return "Connected - \(bluetoothManager.connectedDevice?.name ?? "Treadmill")"
                } else if bluetoothManager.subscriptionState == "Subscribed" {
                    return "Connected — waiting for data (start the belt)"
                } else {
                    return "Connected — no data: \(bluetoothManager.subscriptionState)"
                }
            } else if isConnecting {
                return "Connecting..."
            } else {
                return "Disconnected"
            }
        }
    }

    // MARK: - Start Button

    private var startButton: some View {
        Button {
            guard runMode != .treadmill || bluetoothManager.hasFreshTreadmillData else { return }
            if selectedTab == .todaysWorkout, let workout = todaysWorkout {
                if workout.isCompleted || !Self.isRunSession(workout) { openedSession = workout }
                else { onStartPlannedWorkout(workout, runMode == .outdoor) }
            } else {
                onStartFreeRun(
                    runMode == .outdoor,
                    freeRunGoalMode == .distance ? freeRunDistance : nil,
                    freeRunGoalMode == .time ? freeRunDurationMinutes : nil,
                    freeRunTargetPace
                )
            }
        } label: {
            HStack { Text(startButtonTitle.uppercased()); Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 23, weight: .light)) }
                .padding(.horizontal, 21)
                .font(.barlowCondensed(size: 23, weight: .semibold))
                .foregroundColor(appearance == .red ? .stridePrimary : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(appearance == .red ? Color.white : Color.stridePrimary)
                .clipShape(Capsule())
        }
        .disabled(!canStart)
        .buttonStyle(LobbyStartButtonStyle())
    }

    private var startButtonTitle: String {
        if let workout = selectedWorkout {
            if workout.isCompleted { return "View Completed Session" }
            if !Self.isRunSession(workout) { return "Open Session" }
        }
        if runMode == .treadmill && !isConnected { return "Connect Treadmill to Start" }
        return "Start Session"
    }

    // MARK: - Distance/Time Editor Sheet

    @State private var editorDistanceWhole: Int = 12
    @State private var editorDistanceDecimal: Int = 0
    @State private var editorDurationMinutes: Int = 30

    private var distanceTimeEditorSheet: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text(freeRunGoalMode == .distance ? "Set Distance" : "Set Duration")
                    .font(.inter(size: 20, weight: .semibold))

                if freeRunGoalMode == .distance {
                    HStack(spacing: 4) {
                        Picker("Whole", selection: $editorDistanceWhole) {
                            ForEach(0...100, id: \.self) { n in
                                Text("\(n)").tag(n)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 80)

                        Text(".")
                            .font(.barlowCondensed(size: 48, weight: .medium))

                        Picker("Decimal", selection: $editorDistanceDecimal) {
                            ForEach(0...9, id: \.self) { n in
                                Text("\(n)").tag(n)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 60)

                        Text("km")
                            .font(.inter(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack(spacing: 4) {
                        Picker("Minutes", selection: $editorDurationMinutes) {
                            ForEach(Array(stride(from: 5, through: 300, by: 5)), id: \.self) { m in
                                Text("\(m)").tag(m)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 100)

                        Text("min")
                            .font(.inter(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                Button {
                    if freeRunGoalMode == .distance {
                        freeRunDistance = Double(editorDistanceWhole) + Double(editorDistanceDecimal) / 10.0
                    } else {
                        freeRunDurationMinutes = editorDurationMinutes
                    }
                    showDistanceEditor = false
                } label: {
                    Text("Done")
                        .font(.inter(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.stridePrimary)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 32)

                Spacer()
            }
            .padding(.top, 32)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showDistanceEditor = false }
                        .foregroundColor(.secondary)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            editorDistanceWhole = Int(freeRunDistance)
            editorDistanceDecimal = Int((freeRunDistance * 10).truncatingRemainder(dividingBy: 10))
            editorDurationMinutes = freeRunDurationMinutes
        }
    }

    // MARK: - Pace Editor Sheet

    @State private var paceMinutes: Int = 5
    @State private var paceSeconds: Int = 0

    private var paceEditorSheet: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("Set Target Pace")
                    .font(.inter(size: 20, weight: .semibold))

                HStack(spacing: 4) {
                    Picker("Minutes", selection: $paceMinutes) {
                        ForEach(2...12, id: \.self) { m in
                            Text("\(m)").tag(m)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 80)

                    Text(":")
                        .font(.barlowCondensed(size: 48, weight: .medium))

                    Picker("Seconds", selection: $paceSeconds) {
                        ForEach(0..<60, id: \.self) { s in
                            Text(String(format: "%02d", s)).tag(s)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 80)

                    Text("/km")
                        .font(.inter(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 16) {
                    Button {
                        freeRunTargetPace = String(format: "%d:%02d/km", paceMinutes, paceSeconds)
                        showPaceEditor = false
                    } label: {
                        Text("Set Pace")
                            .font(.inter(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.stridePrimary)
                            .clipShape(Capsule())
                    }

                    if freeRunTargetPace != nil {
                        Button {
                            freeRunTargetPace = nil
                            showPaceEditor = false
                        } label: {
                            Text("Clear")
                                .font(.inter(size: 16, weight: .semibold))
                                .foregroundColor(.stridePrimary)
                                .padding(.vertical, 14)
                                .padding(.horizontal, 24)
                                .overlay(Capsule().stroke(Color.stridePrimary, lineWidth: 1.5))
                        }
                    }
                }
                .padding(.horizontal, 32)

                Spacer()
            }
            .padding(.top, 32)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showPaceEditor = false }
                        .foregroundColor(.secondary)
                }
            }
        }
        .presentationDetents([.medium])
    }


}

/// Native glass on current iOS; frosted material keeps the same treatment on older phones.
private struct LobbyGlassCard: ViewModifier {
    let cornerRadius: CGFloat
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(.white.opacity(0.35), lineWidth: 0.5))
        }
    }
}

#Preview {
    RunLobbyView(
        onStartPlannedWorkout: { _, _ in },
        onStartFreeRun: { _, _, _, _ in }
    )
    .environmentObject(BluetoothManager())
    .environmentObject(LocationManager())
    .modelContainer(for: TrainingPlan.self, inMemory: true)
}

#if DEBUG
/// Stable, isolated plan for reviewing setup screens without changing athlete data.
@MainActor
private final class RunLobbyDashboardFixture: ObservableObject {
    let container: ModelContainer
    init() {
        container = try! ModelContainer(for: TrainingPlan.self, RunLog.self, Shoe.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let args = ProcessInfo.processInfo.arguments
        guard !args.contains("--lobby-no-plan") else { return }
        let today = Calendar.current.startOfDay(for: Date())
        let monday = StatsTrainingData.week(containing: today).start
        let start = Calendar.current.date(byAdding: .weekOfYear, value: -10, to: monday)!
        let plan = TrainingPlan(raceType: .marathon,
            raceDate: Calendar.current.date(byAdding: .day, value: 91, to: today)!, raceName: "Maui Marathon",
            currentWeeklyMileage: 60, longestRecentRun: 20, fitnessLevel: .intermediate, startDate: start,
            isFlexibleSchedule: args.contains("--lobby-flexible"))
        let week = Week(weekNumber: 11)
        week.plan = plan
        let intervals = args.contains("--lobby-intervals")
        let easyPreview = args.contains("--lobby-easy")
        let workout = Workout(date: today, workoutType: easyPreview ? .easyRun : (intervals ? .intervals : .longRun),
            title: easyPreview ? "Easy Run" : (intervals ? "Cruise Intervals" : "Long Run with MP Finish"),
            details: easyPreview ? "Keep a relaxed, conversational effort." : intervals
                ? "Warm-up: 2 km at 6:00–6:30/km. Main set: 4 × 5 min at 5:00–5:15/km with 2 min easy float between. Cool-down: 2 km at 6:00–6:30/km."
                : "Long Run with MP Finish — Total: 24 km. First 21 km at 6:00–6:30/km, final 3 km at 5:30/km (adjusted MP, RPE 5–6). Practise your race-day drinks and fueling.",
            distanceKm: easyPreview ? 6 : (intervals ? 12 : 24), paceDescription: "6:00–6:30/km")
        workout.week = week
        if args.contains("--lobby-completed") {
            workout.isCompleted = true; workout.completedAt = Date()
            workout.actualDistanceKm = 24
        }
        container.mainContext.insert(plan)
        container.mainContext.insert(week)
        container.mainContext.insert(workout)
        if plan.isFlexibleSchedule {
            let easy = Workout(date: monday, workoutType: .easyRun, title: "Easy Run",
                details: "Keep a relaxed, conversational effort.", distanceKm: 4, paceDescription: "6:15–6:45/km")
            easy.week = week
            container.mainContext.insert(easy)
        }
        if args.contains("--runview-demo-plan") {
            week.theme = "Build phase"
            workout.isCompleted = true; workout.actualDistanceKm = workout.distanceKm
            for offset in 0..<7 {
                guard let date = Calendar.current.date(byAdding: .day, value: offset, to: monday), !Calendar.current.isDate(date, inSameDayAs: today) else { continue }
                let distance: Double? = [nil, 6, 12, 15, nil, 5, 26][offset]
                let session = Workout(date: date, workoutType: offset == 4 ? .gym : distance == nil ? .rest : offset == 2 ? .intervals : .easyRun,
                    title: offset == 4 ? "Strength" : distance == nil ? "Rest" : offset == 2 ? "VO₂ Intervals" : "Easy Run",
                    distanceKm: distance, paceDescription: offset == 2 ? "5 × 1 km" : "6:00–6:30/km")
                session.week = week; container.mainContext.insert(session)
            }
        }
        if args.contains("--lobby-multi") || args.contains("--runview-demo-plan") {
            let gym = Workout(date: today, workoutType: .gym, title: "Core Endurance & Stability",
                details: "Core endurance — Goblet Squat 3×8 @ 12 kg; Side Plank 3×30 sec/side @ BW; Dead Bug 3×10", durationMinutes: 35)
            gym.week = week; container.mainContext.insert(gym)
            let nextWeek = Week(weekNumber: 12); nextWeek.plan = plan; container.mainContext.insert(nextWeek)
            for offset in 7..<14 {
                let session = Workout(date: Calendar.current.date(byAdding: .day, value: offset, to: monday)!, workoutType: .easyRun, title: "Easy Run", distanceKm: 6)
                session.week = nextWeek; container.mainContext.insert(session)
            }
        }
        try! container.mainContext.save()
    }
}

struct RunLobbyDashboardPreview: View {
    @StateObject private var fixture = RunLobbyDashboardFixture()
    var body: some View {
        MainTabView().modelContainer(fixture.container)
    }
}

#endif

// MARK: - Shared backdrop (also extends behind the floating tab bar)
struct RunLobbyBackdrop: View {
    @ObservedObject private var lobbyAuth = AuthService.shared
    @AppStorage(RunLobbyAppearance.storageKey) private var appearanceRaw = RunLobbyAppearance.black.rawValue
    @AppStorage("lastRunMode") private var runModeRaw = RunMode.outdoor.rawValue
    @AppStorage("runLobbyGymSelected") private var gymSelectedForBackdrop = false
    private var appearance: RunLobbyAppearance { RunLobbyAppearance(rawValue: appearanceRaw) ?? .black }
    private static let puck: UIImage = {
        UIGraphicsImageRenderer(size: CGSize(width: 26, height: 26)).image { context in
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 26, height: 26))
            UIColor(Color.stridePrimary).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 3, y: 3, width: 20, height: 20))
        }
    }()
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                appearance.background
                if AccountRunCapabilities.forUserID(lobbyAuth.currentUserID)
                    .resolvedMode(RunMode(rawValue: runModeRaw) ?? .outdoor) == .outdoor && !gymSelectedForBackdrop {
                    Map(initialViewport: .followPuck(zoom: 15.5, bearing: .constant(0), pitch: 45)) {
                        Puck2D(bearing: .heading).topImage(Self.puck).scale(0.7)
                    }
                    .mapStyle(.standard(theme: .monochrome, lightPreset: appearance == .white ? .day : .night,
                        showPointOfInterestLabels: false, showTransitLabels: false, show3dObjects: true))
                    .ornamentOptions(OrnamentOptions(scaleBar: ScaleBarViewOptions(visibility: .hidden),
                        compass: CompassViewOptions(visibility: .hidden)))
                    .overlay {
                        LinearGradient(colors: [appearance.background.opacity(0.65), .clear, appearance.background.opacity(0.4)], startPoint: .top, endPoint: .bottom)
                    }
                } else {
                    Image(appearance.imageName).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading).clipped()
                        .blur(radius: 0.5)
                        .overlay(Color.black.opacity(appearance == .black ? 0.40 : 0.15))
                }
                Canvas { context, size in
                    var dots = Path()
                    for x in stride(from: 0.0, to: size.width, by: 4) {
                        for y in stride(from: 0.0, to: size.height, by: 4) {
                            dots.addEllipse(in: CGRect(x: x, y: y, width: 0.7, height: 0.7))
                        }
                    }
                    context.fill(dots, with: .color(appearance.foreground.opacity(appearance == .white ? 0.07 : 0.10)))
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// A visual beat indicator, not an ECG measurement. Only shown with fresh live BPM.
private struct LobbyHeartRatePulse: View {
    let bpm: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if reduceMotion {
                Image(systemName: "waveform.path.ecg").resizable().scaledToFit().foregroundStyle(Color.stridePrimary)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                    let phase = timeline.date.timeIntervalSinceReferenceDate * Double(max(30, min(bpm, 220))) / 60
                    LobbyPulseWave(phase: phase).stroke(Color.stridePrimary, style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                }
            }
        }.accessibilityHidden(true)
    }
}

private struct LobbyPulseWave: Shape {
    let phase: Double
    func path(in rect: CGRect) -> Path {
        func triangle(_ x: Double, center: Double, width: Double, height: Double) -> Double {
            max(0, 1 - abs(x - center) / width) * height
        }
        return Path { path in
            for index in 0...100 {
                let x = Double(index) / 100
                let beat = (phase - (1 - x) * 1.6).truncatingRemainder(dividingBy: 1)
                let t = beat < 0 ? beat + 1 : beat
                let signal = triangle(t, center: 0.18, width: 0.035, height: 0.12)
                    - triangle(t, center: 0.32, width: 0.025, height: 0.20)
                    + triangle(t, center: 0.37, width: 0.035, height: 0.85)
                    - triangle(t, center: 0.43, width: 0.03, height: 0.35)
                    + triangle(t, center: 0.62, width: 0.08, height: 0.18)
                let point = CGPoint(x: x * rect.width, y: rect.midY - signal * rect.height * 0.6)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
    }
}

private struct LobbyTransparentNavigation: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.containerBackground(.clear, for: .navigation)
        } else {
            content.background { RunLobbyBackdrop().ignoresSafeArea() }
        }
    }
}

/// Preserve contrast even when the treadmill must be connected before starting.
private struct LobbyStartButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
