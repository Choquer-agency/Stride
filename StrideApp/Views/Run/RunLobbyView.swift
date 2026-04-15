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
            && workout.workoutType != .rest
            && workout.workoutType != .gym
            && workout.workoutType != .crossTraining
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

            // Fixed content overlay
            VStack(spacing: 0) {
                // Logo
                StrideLogoView(height: 35)
                    .padding(.top, 20)

                // "TODAYS WORKOUT" header
                HStack(spacing: 6) {
                    Image("FlagIcon")
                        .resizable()
                        .renderingMode(.template)
                        .frame(width: 14, height: 14)
                    Text("TODAYS WORKOUT")
                        .font(.barlowCondensed(size: 14, weight: .medium))
                        .tracking(1)
                }
                .foregroundColor(.stridePrimary)
                .padding(.top, 20)

                // Tab toggle
                tabToggle
                    .padding(.top, 24)

                // Tab content
                if selectedTab == .todaysWorkout {
                    todaysWorkoutContent
                        .padding(.top, 16)
                } else {
                    freeRunContent
                        .padding(.top, 20)
                }

                Spacer()

                // Mode indicator (tappable toggle)
                modeIndicator

                // Start button
                startButton
                    .padding(.top, 16)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 100)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
        }
        .animation(.easeInOut(duration: 0.3), value: runMode)
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
        .onAppear {
            startBlinkingAnimation()
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
            logo: LogoViewOptions(visibility: .hidden),
            attributionButton: AttributionButtonOptions(visibility: .hidden)
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
        HStack(spacing: 20) {
            if let workout = todaysWorkout {
                Button {
                    selectedTab = .todaysWorkout
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(workout.workoutType.color))
                            .frame(width: 12, height: 12)
                            .opacity(selectedTab == .todaysWorkout ? 1 : 0.4)

                        Text(workout.workoutType.displayName)
                            .font(.inter(size: 16, weight: selectedTab == .todaysWorkout ? .semibold : .medium))
                            .foregroundColor(selectedTab == .todaysWorkout ? .primary : .secondary)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }

            Button {
                selectedTab = .freeRun
            } label: {
                Text("Free Run")
                    .font(.inter(size: 16, weight: selectedTab == .freeRun ? .semibold : .medium))
                    .foregroundColor(selectedTab == .freeRun ? .primary : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .onAppear {
            // If no planned workout, default to free run
            if todaysWorkout == nil {
                selectedTab = .freeRun
            }
        }
    }

    // MARK: - Today's Workout Content

    private var todaysWorkoutContent: some View {
        VStack(spacing: 20) {
            if let workout = todaysWorkout {
                // Large distance + pace
                HStack(spacing: 16) {
                    if let distKm = workout.distanceKm, distKm > 0 {
                        VStack(spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(distKm.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(distKm))" : String(format: "%.1f", distKm))
                                    .font(.barlowCondensed(size: 82, weight: .medium))
                                Text("km")
                                    .font(.barlowCondensed(size: 28, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            Text("Distance")
                                .font(.inter(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }

                    if let pace = workout.paceDescription {
                        VStack(spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(pace)
                                    .font(.barlowCondensed(size: 82, weight: .medium))
                            }
                            Text("Pace")
                                .font(.inter(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Workout details
                VStack(spacing: 8) {
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
                    } else {
                        Text("\(workout.workoutType.displayName) — \(workout.distanceDisplay ?? "") at \(workout.paceDescription ?? "easy pace")")
                            .font(.inter(size: 13, weight: .regular))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
    }

    // MARK: - Free Run Content

    @State private var lastDragY: CGFloat? = nil

    private var freeRunContent: some View {
        VStack(spacing: 20) {
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
        VStack(spacing: 4) {
            Text(runMode == .outdoor ? "Outdoor" : "Treadmill")
                .font(.inter(size: 20, weight: .medium))
                .foregroundColor(.primary)

            HStack(spacing: 6) {
                Circle()
                    .fill(modeStatusColor)
                    .frame(width: 8, height: 8)
                    .opacity(isConnecting ? (indicatorVisible ? 1.0 : 0.3) : 1.0)

                Text(modeStatusLabel)
                    .font(.inter(size: 13, weight: .regular))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.3)) {
                setRunMode(runMode == .outdoor ? .treadmill : .outdoor)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if abs(value.translation.width) > abs(value.translation.height) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            setRunMode(runMode == .outdoor ? .treadmill : .outdoor)
                        }
                    }
                }
        )
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
            Text("Start Workout")
                .font(.inter(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(canStart ? Color.stridePrimary : Color.gray.opacity(0.4))
                .clipShape(Capsule())
        }
        .disabled(!canStart)
        .buttonStyle(PlainButtonStyle())
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
