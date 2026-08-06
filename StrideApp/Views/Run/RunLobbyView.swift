import SwiftUI
import SwiftData
import CoreLocation
import MapboxMaps

enum RunMode: String, CaseIterable {
    case treadmill
    case outdoor
}

struct RunLobbyView: View {
    @EnvironmentObject private var bluetoothManager: BluetoothManager
    @EnvironmentObject private var locationManager: LocationManager
    @Query(filter: #Predicate<TrainingPlan> { $0.isArchived == false }, sort: \TrainingPlan.createdAt, order: .reverse) private var plans: [TrainingPlan]

    var onStartPlannedWorkout: (Workout, Bool) -> Void
    var onStartFreeRun: (_ outdoor: Bool, _ targetDistanceKm: Double?, _ targetDurationMinutes: Int?) -> Void

    @AppStorage("lastRunMode") private var runModeRaw: String = RunMode.outdoor.rawValue
    @State private var selectedTab: LobbyTab = .todaysWorkout
    @State private var freeRunDistance: Double = 12.0
    @State private var freeRunDurationMinutes: Int = 30
    @State private var freeRunGoalMode: FreeRunGoalMode = .distance
    @State private var freeRunTargetPace: String? = nil
    @State private var showPaceEditor = false
    @State private var showDistanceEditor = false
    @State private var indicatorVisible: Bool = true

    enum FreeRunGoalMode: String {
        case distance
        case time
    }

    private var runMode: RunMode {
        get { RunMode(rawValue: runModeRaw) ?? .outdoor }
    }

    private func setRunMode(_ mode: RunMode) {
        runModeRaw = mode.rawValue
    }

    enum LobbyTab {
        case todaysWorkout
        case freeRun
    }

    private static let styleURI = StyleURI(rawValue: "mapbox://styles/choquer/cmnrp6hea002p01suci3bhyid")!

    // MARK: - Computed Properties

    private var isConnected: Bool {
        bluetoothManager.connectedDevice != nil
    }

    private var isConnecting: Bool {
        !isConnected && (bluetoothManager.connectionState == "Connecting..."
            || bluetoothManager.connectionState.hasPrefix("Reconnecting")
            || bluetoothManager.isScanning)
    }

    private var isGPSReady: Bool {
        locationManager.authorizationStatus == .authorizedWhenInUse
        || locationManager.authorizationStatus == .authorizedAlways
    }

    private var todaysWorkout: Workout? {
        guard let plan = plans.first,
              let currentWeek = plan.currentWeek else { return nil }
        return currentWeek.sortedWorkouts.first { workout in
            workout.isToday
            && !workout.isCompleted
            && workout.workoutType != .rest
            && workout.workoutType != .gym
            && workout.workoutType != .crossTraining
            && workout.workoutType != .mobility
        }
    }

    private var canStart: Bool {
        if runMode == .treadmill {
            return isConnected
        }
        return true
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background
            Color(.systemBackground).ignoresSafeArea()

            // Map background (outdoor only)
            if runMode == .outdoor {
                mapBackground
            }

            // Primary run setup
            VStack(spacing: 0) {
                StrideLogoView(height: 24)
                    .padding(.top, 18)

                if todaysWorkout != nil {
                    tabToggle
                        .padding(.top, 22)
                }

                if selectedTab == .todaysWorkout {
                    todaysWorkoutContent
                        .padding(.top, 20)
                } else {
                    freeRunContent
                        .padding(.top, 24)
                }

                Spacer()

                modeIndicator

                startButton
                    .padding(.top, 14)
                    .padding(.bottom, 96)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
        }
        .animation(.easeInOut(duration: 0.3), value: runMode)
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
        .onChange(of: todaysWorkout?.id) { _, workoutId in
            if workoutId == nil { selectedTab = .freeRun }
        }
        .onAppear {
            startBlinkingAnimation()
            if todaysWorkout == nil {
                selectedTab = .freeRun
            }
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestPermission()
            }
        }
        .sheet(isPresented: $showDistanceEditor) {
            distanceTimeEditorSheet
        }
        .sheet(isPresented: $showPaceEditor) {
            paceEditorSheet
        }
    }

    // MARK: - Map Background

    private static let redPuckImage: UIImage = {
        let size: CGFloat = 28
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))
            UIColor(Color.stridePrimary).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 3, y: 3, width: size - 6, height: size - 6))
        }
    }()

    private var mapBackground: some View {
        Map(initialViewport: .followPuck(zoom: 16, bearing: .constant(0), pitch: 45)) {
            Puck2D(bearing: .heading)
                .topImage(Self.redPuckImage)
                .scale(0.7)
        }
        .mapStyle(MapStyle(uri: Self.styleURI))
        .ornamentOptions(OrnamentOptions(
            scaleBar: ScaleBarViewOptions(visibility: .hidden),
            compass: CompassViewOptions(visibility: .hidden),
            logo: LogoViewOptions(margins: CGPoint(x: -10000, y: -10000)),
            attributionButton: AttributionButtonOptions(margins: CGPoint(x: -10000, y: -10000))
        ))
        .ignoresSafeArea()
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.15),
                    .init(color: .white, location: 0.45),
                    .init(color: .white, location: 0.65),
                    .init(color: .clear, location: 0.82),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Tab Toggle

    private var tabToggle: some View {
        HStack(spacing: 4) {
            if todaysWorkout != nil {
                Button {
                    selectedTab = .todaysWorkout
                } label: {
                    Text("Today")
                        .font(.inter(size: 14, weight: .semibold))
                        .foregroundColor(selectedTab == .todaysWorkout ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(selectedTab == .todaysWorkout ? Color.white : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
            }

            Button {
                selectedTab = .freeRun
            } label: {
                Text("Free Run")
                    .font(.inter(size: 14, weight: .semibold))
                    .foregroundColor(selectedTab == .freeRun ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(selectedTab == .freeRun ? Color.white : Color.clear)
                    .clipShape(Capsule())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(4)
        .frame(maxWidth: 300)
        .background(Color(.secondarySystemBackground).opacity(0.9))
        .clipShape(Capsule())
    }

    // MARK: - Today's Workout Content

    private var todaysWorkoutContent: some View {
        VStack(spacing: 18) {
            if let workout = todaysWorkout {
                VStack(spacing: 4) {
                    Text(workout.title)
                        .font(.inter(size: 22, weight: .semibold))
                        .multilineTextAlignment(.center)
                    Text(workout.workoutType.displayName)
                        .font(.inter(size: 13, weight: .medium))
                        .foregroundStyle(Color(workout.workoutType.color))
                }

                HStack(alignment: .top, spacing: 12) {
                    if let distKm = workout.distanceKm, distKm > 0 {
                        metricCard(title: "Distance") {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(distKm.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(distKm))" : String(format: "%.1f", distKm))
                                    .font(.barlowCondensed(size: 54, weight: .medium))
                                Text("km")
                                    .font(.barlowCondensed(size: 22, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if let pace = workout.paceDescription {
                        metricCard(title: "Target Pace") {
                            Text(compactPace(pace))
                                .font(.barlowCondensed(size: 42, weight: .medium))
                                .minimumScaleFactor(0.72)
                                .lineLimit(1)
                            Text("/km")
                                .font(.barlowCondensed(size: 20, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: 520)

                // Workout details
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 14, weight: .medium))
                        Text("Workout Details")
                            .font(.inter(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.primary)

                    if let details = workout.details, !details.isEmpty {
                        Text(details)
                            .font(.inter(size: 13, weight: .regular))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .lineLimit(3)
                    } else {
                        Text("\(workout.workoutType.displayName) — \(workout.distanceDisplay ?? "") at \(workout.paceDescription ?? "easy pace")")
                            .font(.inter(size: 13, weight: .regular))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }

    private func metricCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) { content() }
                .frame(maxWidth: .infinity, minHeight: 66)
            Text(title)
                .font(.inter(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(Color(.secondarySystemBackground).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func compactPace(_ pace: String) -> String {
        pace
            .replacingOccurrences(of: " /km", with: "")
            .replacingOccurrences(of: "/km", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Free Run Content

    @State private var lastDragY: CGFloat? = nil

    private var freeRunContent: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("Run your way")
                    .font(.inter(size: 22, weight: .semibold))
                Text("Set a goal or simply head out")
                    .font(.inter(size: 13))
                    .foregroundStyle(.secondary)
            }

            // Value display — tap to open picker, drag to adjust
            VStack(spacing: 0) {
                if freeRunGoalMode == .distance {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String(format: "%.1f", freeRunDistance))
                            .font(.barlowCondensed(size: 82, weight: .medium))
                            .foregroundColor(.primary)
                        Text("km")
                            .font(.barlowCondensed(size: 82, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.3))
                            .frame(height: 1)
                            .offset(y: 6)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showDistanceEditor = true
                    }
                    .gesture(
                        DragGesture(minimumDistance: 5)
                            .onChanged { value in
                                if let lastY = lastDragY {
                                    let delta = -(value.location.y - lastY) / 50
                                    freeRunDistance = max(0.5, min(100, freeRunDistance + delta))
                                }
                                lastDragY = value.location.y
                            }
                            .onEnded { _ in
                                lastDragY = nil
                                freeRunDistance = (freeRunDistance * 2).rounded() / 2
                            }
                    )
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(freeRunDurationMinutes)")
                            .font(.barlowCondensed(size: 82, weight: .medium))
                            .foregroundColor(.primary)
                        Text("min")
                            .font(.barlowCondensed(size: 82, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.3))
                            .frame(height: 1)
                            .offset(y: 6)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showDistanceEditor = true
                    }
                    .gesture(
                        DragGesture(minimumDistance: 5)
                            .onChanged { value in
                                if let lastY = lastDragY {
                                    let delta = -(value.location.y - lastY) / 30
                                    freeRunDurationMinutes = max(5, min(300, freeRunDurationMinutes + Int(delta)))
                                }
                                lastDragY = value.location.y
                            }
                            .onEnded { _ in
                                lastDragY = nil
                                freeRunDurationMinutes = max(5, ((freeRunDurationMinutes + 2) / 5) * 5)
                            }
                    )
                }

                // Tappable label to toggle distance/time — more spacing from line
                Menu {
                    Button {
                        freeRunGoalMode = .distance
                    } label: {
                        Label("Distance", systemImage: "ruler")
                    }
                    Button {
                        freeRunGoalMode = .time
                    } label: {
                        Label("Time", systemImage: "clock")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(freeRunGoalMode == .distance ? "Distance" : "Time")
                            .font(.inter(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 14)
                }
            }

            // Set target pace — white button with red glow shadow
            Button {
                showPaceEditor = true
            } label: {
                if let pace = freeRunTargetPace {
                    VStack(spacing: 2) {
                        Text(pace)
                            .font(.barlowCondensed(size: 32, weight: .medium))
                            .foregroundColor(.primary)
                        Text("Target Pace")
                            .font(.inter(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Set Target Pace")
                        .font(.inter(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: Color.stridePrimary.opacity(0.20), radius: 7, x: 3, y: 5)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // MARK: - Mode Indicator

    private var modeIndicator: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                runModeButton(.outdoor, title: "Outdoor", icon: "location.fill")
                treadmillModeButton
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(modeStatusColor)
                    .frame(width: 7, height: 7)
                    .opacity(isConnecting ? (indicatorVisible ? 1 : 0.35) : 1)
                Text(modeStatusLabel)
                    .font(.inter(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func runModeButton(_ mode: RunMode, title: String, icon: String) -> some View {
        let selected = runMode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { setRunMode(mode) }
        } label: {
            Label(title, systemImage: icon)
                .font(.inter(size: 13, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(selected ? Color.strideBrandBlack : Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var treadmillModeButton: some View {
        let selected = runMode == .treadmill
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { setRunMode(.treadmill) }
        } label: {
            HStack(spacing: 7) {
                TreadmillIconView(size: 18, color: selected ? .white : .primary)
                Text("Treadmill")
            }
            .font(.inter(size: 13, weight: .semibold))
            .foregroundStyle(selected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(selected ? Color.strideBrandBlack : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var modeStatusColor: Color {
        if runMode == .outdoor {
            return isGPSReady ? .green : .orange
        } else {
            return isConnected ? .green : .red
        }
    }

    private var modeStatusLabel: String {
        if runMode == .outdoor {
            return isGPSReady ? "Ready" : "GPS Unavailable"
        } else {
            if isConnected {
                return "Connected - \(bluetoothManager.connectedDevice?.name ?? "Treadmill")"
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
            if selectedTab == .todaysWorkout, let workout = todaysWorkout {
                onStartPlannedWorkout(workout, runMode == .outdoor)
            } else {
                onStartFreeRun(
                    runMode == .outdoor,
                    freeRunGoalMode == .distance ? freeRunDistance : nil,
                    freeRunGoalMode == .time ? freeRunDurationMinutes : nil
                )
            }
        } label: {
            Text(startButtonTitle)
                .font(.inter(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(canStart ? Color.stridePrimary : Color.gray.opacity(0.4))
                .clipShape(Capsule())
        }
        .disabled(!canStart)
        .buttonStyle(PlainButtonStyle())
    }

    private var startButtonTitle: String {
        if runMode == .treadmill && !isConnected { return "Connect Treadmill to Start" }
        if selectedTab == .todaysWorkout, todaysWorkout != nil { return "Start Today's Run" }
        return runMode == .outdoor ? "Start Outdoor Run" : "Start Treadmill Run"
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

    // MARK: - Helpers

    private func startBlinkingAnimation() {
        withAnimation(
            .easeInOut(duration: 1.0)
            .repeatForever(autoreverses: true)
        ) {
            indicatorVisible = false
        }
    }
}

#Preview {
    RunLobbyView(
        onStartPlannedWorkout: { _, _ in },
        onStartFreeRun: { _, _, _ in }
    )
    .environmentObject(BluetoothManager())
    .environmentObject(LocationManager())
    .modelContainer(for: TrainingPlan.self, inMemory: true)
}
