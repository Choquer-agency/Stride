import Foundation
import SwiftUI
import CoreLocation
import Combine
import os.log

private let runLog = Logger(subsystem: "com.stride.app", category: "RunViewModel")

// MARK: - Run Result (snapshot of completed run data)
struct RunResult: Codable {
    var sessionID: UUID = UUID()
    var completedAt: Date = Date()
    var recoveryNotice: String? = nil
    let distanceKm: Double
    let durationSeconds: Double
    let avgPaceSecPerKm: Double
    let kmSplits: [KilometerSplit]

    // Planned workout reference (nil for free runs)
    let plannedWorkoutId: UUID?
    let plannedWorkoutTitle: String?
    let plannedWorkoutType: WorkoutType?
    let targetDistanceKm: Double?
    let targetPaceDescription: String?
    let targetDurationMinutes: Int?

    // Data source (for leaderboard eligibility)
    let dataSource: String  // "bluetooth_ftms" | "gps" | "manual"
    let treadmillBrand: String?

    // GPS route data (nil for treadmill runs)
    let routeJSON: String?
    let elevationGainMeters: Double?
    let elevationLossMeters: Double?

    // Heart rate (BLE broadcast or FTMS; nil when no monitor was connected)
    let avgHeartRate: Int?
    let maxHeartRate: Int?
    let hrSamplesJSON: String?

    // Full-run speed history for the completion chart; independent of the rolling live graph.
    var speedSamples: [RunSpeedSample] = []
    var plannedWorkoutDetails: String? = nil

    // Pause tracking
    let totalPauseDurationSeconds: Double
    let completedPauseDurations: [Double]

    var isPlannedRun: Bool { plannedWorkoutId != nil }
    var isOutdoorRun: Bool { dataSource == "gps" }

    /// Summary of pause events for notes, nil if no pauses
    var pauseSummary: String? {
        guard !completedPauseDurations.isEmpty else { return nil }
        let total = completedPauseDurations.reduce(0, +)
        let lines = completedPauseDurations.enumerated().map { i, dur in
            "Pause \(i + 1): \(formatPauseDuration(dur))"
        }
        return "Paused \(completedPauseDurations.count) time\(completedPauseDurations.count == 1 ? "" : "s") (total: \(formatPauseDuration(total)))\n" + lines.joined(separator: "\n")
    }

    private func formatPauseDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins > 0 {
            return "\(mins)m \(secs)s"
        }
        return "\(secs)s"
    }
    
    /// Formatted average pace as M:SS /km
    var avgPaceDisplay: String {
        guard avgPaceSecPerKm > 0 && avgPaceSecPerKm < 3600 else { return "--:--" }
        let minutes = Int(avgPaceSecPerKm) / 60
        let seconds = Int(avgPaceSecPerKm) % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
    
    /// Formatted duration as HH:MM:SS
    var durationDisplay: String {
        let totalSeconds = Int(durationSeconds)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
    
    /// Formatted distance
    var distanceDisplay: String {
        if distanceKm == floor(distanceKm) {
            return "\(Int(distanceKm))"
        }
        return String(format: "%.2f", distanceKm)
    }
}

/// Codable heart-rate sample persisted to RunLog.hrSamplesJSON — `t` is
/// seconds of elapsed run time, matching the server's hr_samples_json shape.
struct RunSpeedSample: Codable {
    let t: TimeInterval
    let kmh: Double
}

struct CodableHRSample: Codable {
    let t: TimeInterval
    let bpm: Int
}

extension HeartRateZone {
    /// Map a BPM to a training zone. Uses the same ~187 max-HR assumption as
    /// HeartRateZones.band(for:) until per-athlete max HR lands.
    static func zone(forBPM bpm: Int) -> HeartRateZone {
        switch bpm {
        case ..<113: return .zone1        // < 60%
        case 113..<131: return .zone2     // 60–70%
        case 131..<149: return .zone3     // 70–80%
        case 149..<168: return .zone4     // 80–90%
        default: return .zone5            // 90%+
        }
    }
}

// MARK: - Pace Zone (live pace vs. target comparison)
enum PaceZone {
    case onPace          // within target range → Green
    case slightlySlow    // 1-20 sec/km over max → Blue
    case tooSlow         // >20 sec/km over max → Red
    case slightlyFast    // 1-10 sec/km under min → Green (still good)
    case tooFast         // >10 sec/km under min → Orange
    case noTarget        // free run or no pace data

    var color: Color {
        switch self {
        case .onPace, .slightlyFast: return .green
        case .slightlySlow: return .blue
        case .tooSlow: return Color.stridePrimary
        case .tooFast: return .orange
        case .noTarget: return .primary
        }
    }

    /// True for any zone where the runner has drifted off the target pace —
    /// used to gate the fast "back on pace" recovery path.
    var isOffPace: Bool {
        switch self {
        case .tooSlow, .slightlySlow, .tooFast, .slightlyFast: return true
        case .onPace, .noTarget: return false
        }
    }

    var statusText: String {
        switch self {
        case .onPace, .slightlyFast: return "On Pace"
        case .slightlySlow: return "Slightly Slow"
        case .tooSlow: return "Too Slow"
        case .tooFast: return "Too Fast"
        case .noTarget: return ""
        }
    }

    /// Color for the status text label (separate from `color` used elsewhere).
    /// Blue = too fast, grey = on pace, orange = too slow.
    var statusColor: Color {
        switch self {
        case .tooFast: return .blue
        case .onPace, .slightlyFast: return Color(.systemGray)
        case .slightlySlow, .tooSlow: return Color.stridePrimary
        case .noTarget: return .primary
        }
    }
}

// MARK: - Split Feedback (shown briefly after each km)
struct SplitFeedback: Identifiable {
    let id = UUID()
    let pace: String              // e.g. "4:32"
    let diffSeconds: Int?         // nil on first split
    let category: Category

    enum Category {
        case faster    // green — beat the fastest
        case neutral   // white — within 3 sec
        case slower    // orange — 3+ sec slower
    }
}

class RunViewModel: ObservableObject {
    // MARK: - Published Properties (matching RunView's UI bindings)
    @Published var elapsedTime: TimeInterval = 0          // seconds (validated, never regresses)
    @Published var distance: Double = 0.0                 // km (validated, never regresses)
    @Published var speedKmh: Double = 0
    @Published var currentPace: String = "--:--"          // M:SS /km (smoothed)
    @Published var paceDrift: String = "--"               // "+X.Xs" or "-X.Xs"
    @Published var heartRate: Int = 0                     // live BPM (BLE broadcast or FTMS), 0 = no signal
    @Published var heartRateZone: HeartRateZone = .zone2
    @Published var hrSourceConnected: Bool = false        // true while a BLE HR broadcaster is attached
    @Published var kilometerSplits: [KilometerSplit] = []
    @Published var paceGraphDataPoints: [Double] = []     // normalized 0-1 for PaceGraphView
    @Published var paceGraphHeartRates: [Int?] = []
    @Published var paceGraphDistances: [Double] = []
    @Published var intervalPrescriptionWarning: String?
    @Published var paceGraphPaces: [Double] = []          // raw sec/km window for the target-band graph
    @Published var splitFeedback: SplitFeedback? = nil

    // MARK: - Planned Workout Target (optional, set when running a planned workout)
    @Published var plannedWorkoutTitle: String?
    private var plannedWorkoutDetails: String?
    @Published var plannedWorkoutType: WorkoutType?
    @Published var targetDistanceKm: Double?
    private var plannedPaceDescription: String?
    @Published var targetPaceDescription: String?
    @Published var targetDurationMinutes: Int?
    @Published var isPlannedRun: Bool = false

    // MARK: - Interval Mode (structured fartleks/intervals auto-advance)
    @Published var pacePhaseAnnouncement: String?
    private var progressionSegments: [IntervalSegment] = []
    private var progressionIndex = 0
    private var lastPacePhaseChangeTime: TimeInterval = -.infinity
    @Published var intervalSegments: [IntervalSegment] = []
    @Published var intervalIndex: Int = 0
    @Published var intervalPhaseRemaining: Double = 0          // timed phases
    @Published var intervalPhaseDistanceDone: Double = 0       // distance phases
    @Published var intervalComplete: Bool = false
    private var segmentStartTime: TimeInterval = 0
    private var segmentStartDistance: Double = 0
    private var lastCountdownTick: Int = -1
    private var basePaceMin: Double?
    private var basePaceMax: Double?

    var intervalPhaseElapsed: Double { max(0, elapsedTime - segmentStartTime) }

    @Published var isStrideWorkout = false
    var stridePreparationCountdown: Int? {
        guard isStrideWorkout, !intervalComplete, currentIntervalSegment?.paceText == "Get ready for a stride" else { return nil }
        return max(1, Int(ceil(intervalPhaseRemaining)))
    }
    var isIntervalWorkout: Bool { !intervalSegments.isEmpty }
    var currentIntervalSegment: IntervalSegment? {
        guard intervalIndex < intervalSegments.count else { return intervalSegments.last }
        return intervalSegments[intervalIndex]
    }
    var nextIntervalSegment: IntervalSegment? {
        let next = intervalIndex + 1
        guard next < intervalSegments.count else { return nil }
        return intervalSegments[next]
    }

    // MARK: - Pace Zone & Progress (live target comparison)
    @Published var targetPaceMinSec: Double?     // faster boundary (lower sec/km)
    @Published var targetPaceMaxSec: Double?     // slower boundary (higher sec/km)
    @Published var paceZone: PaceZone = .noTarget

    /// Point-of-no-return flag: once set, we stop nagging about pace and let the
    /// runner focus on finishing the distance. One-way — never flips back during a run.
    @Published private(set) var distanceOnlyMode: Bool = false

    // MARK: - Planned Workout Reference
    var plannedWorkoutId: UUID?

    /// For time-based workouts: remaining seconds (countdown).
    var remainingTimeSeconds: TimeInterval? {
        guard let target = targetDurationMinutes, isPlannedRun else { return nil }
        return max(Double(target) * 60.0 - elapsedTime, 0)
    }

    /// Whether this is a time-based workout (has duration target but no distance target).
    var isTimeBasedWorkout: Bool {
        isPlannedRun && targetDurationMinutes != nil && targetDistanceKm == nil
    }

    /// Whether this workout is distance-focused (long runs, or easy/free runs at 8km+).
    /// Used to suppress total-time readouts on mid-run splits so the runner isn't
    /// distracted by cumulative clock time until the finish.
    var isDistanceFocusedWorkout: Bool {
        if plannedWorkoutType == .longRun { return true }
        if let target = targetDistanceKm, target >= 8 {
            // Easy / unplanned runs at 8km+ count as distance-focused.
            if plannedWorkoutType == .easyRun || plannedWorkoutType == nil { return true }
        }
        return false
    }

    // MARK: - GPS / Route State
    @Published var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published var isPaused: Bool = false
    @Published var currentAltitude: Double?
    @Published var currentPauseDuration: TimeInterval = 0
    /// Completed pause durations (only pauses followed by resume, not end)
    private(set) var completedPauseDurations: [TimeInterval] = []

    // MARK: - Internal State
    private var dataProvider: RunDataProvider?
    private(set) var sessionID = UUID()
    private var recoveryOwnerID: String?
    private var lastCheckpointAt: Date?
    private var runFinishedAt: Date?
    private var lifecycleCancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in self?.persistRunCheckpoint(force: true) }
            .store(in: &lifecycleCancellables)
    }

    func prepareRecovery(ownerID: String) {
        recoveryOwnerID = ownerID
    }

    private func persistRunCheckpoint(force: Bool = false) {
        guard let recoveryOwnerID, dataProvider != nil else { return }
        let now = Date()
        guard force || lastCheckpointAt.map({ now.timeIntervalSince($0) >= 5 }) != false else { return }
        if !isPaused, !runStopped, let start = displayTimerStart {
            elapsedTime = max(elapsedTime, now.timeIntervalSince(start) - displayTimerPausedDuration)
        }
        do {
            try RunRecoveryStore.save(buildRunResult(), ownerID: recoveryOwnerID)
            lastCheckpointAt = now
        } catch {
            runLog.error("Could not checkpoint run: \(error.localizedDescription)")
        }
    }

    // Heart-rate capture (BLE broadcast subscription + per-run sample log)
    private var hrCancellables = Set<AnyCancellable>()
    private var hrSamples: [(t: TimeInterval, bpm: Int)] = []
    private var speedSamples: [RunSpeedSample] = []

    /// Whether a data provider is already attached (guards double-attach on re-appear).
    var hasActiveProvider: Bool { dataProvider != nil }
    private let paceSmoother = PaceSmoother()
    private let liveSpeedSmoother = LiveSpeedSmoother()
    @Published private(set) var workoutCompleted = false
    private var runStopped = false
    private let autoPauseService = AutoPauseService()
    private let voiceCoach = VoiceCoachService()
    private lazy var midRunCoach = MidRunCoachingService(voiceCoach: voiceCoach)

    // Kilometer split tracking
    private var lastRecordedKm: Int = 0
    private var lastKmElapsedTime: TimeInterval = 0       // elapsed time at last km boundary
    private var lastKmDistance: Double = 0                 // distance (m) at last km boundary

    // Pace graph: rolling (distance, pace) samples for distance-based windowing
    private struct PaceGraphSample {
        let distanceMeters: Double   // cumulative distance at this sample
        let pace: Double             // smoothed pace in sec/km
        let bpm: Int?
    }
    private var paceGraphSamples: [PaceGraphSample] = []
    /// The graph shows the last 500 metres of pace data
    private let graphWindowMeters: Double = 500.0
    /// Adaptive Y-axis: minimum range in sec/km so steady-state noise looks flat
    private let minYAxisRange: Double = 30.0

    // Split feedback auto-dismiss timer
    private var splitFeedbackTimer: Timer?

    // Pace drift: 50m rolling window, only after 1+ km completed
    private var driftSamples: [(distance: Double, time: Double)] = []
    private let driftWindowMeters: Double = 50.0

    // MARK: - Display Timer (ticks every second for GPS runs)
    private var displayTimer: Timer?
    private var displayTimerStart: Date?
    private var displayTimerPausedDuration: TimeInterval = 0
    private var displayTimerPauseStart: Date?

    // MARK: - Fallback Timer (app-side backup)
    private var runStartTime: Date?                       // wall-clock time when first data arrived
    private var appElapsedTime: TimeInterval = 0          // app-computed elapsed time as fallback
    private var usingFallbackTimer: Bool = false          // true if treadmill time regressed

    // MARK: - Anomaly Tracking
    private var timeAnomalyCount: Int = 0                 // number of time regressions detected
    private var distanceAnomalyCount: Int = 0             // number of distance regressions detected
    private var lastTreadmillTime: TimeInterval = 0       // previous treadmill-reported time (for jump detection)

    /// Maximum forward jump in seconds between two consecutive packets before flagging an anomaly.
    /// At 2.5 Hz update rate, normal gap is ~0.4s. 30s allows for pauses/throttling.
    private let maxReasonableTimeJump: TimeInterval = 30

    // MARK: - Setup

    /// Call this once to wire up a data provider (Bluetooth or GPS).
    func attach(provider: RunDataProvider) {
        self.dataProvider = provider
        runStopped = false
        startHeartRateCapture()

        // Wire auto-pause for GPS outdoor runs
        if provider.dataSourceType == "gps" {
            autoPauseService.isEnabled = true
            autoPauseService.onAutoPause = { [weak self] in
                DispatchQueue.main.async { self?.pauseRun() }
            }
            autoPauseService.onAutoResume = { [weak self] in
                DispatchQueue.main.async { self?.resumeRun() }
            }
            // Feed the auto-pause detector from the raw GPS tick so it keeps
            // receiving speed samples while paused and can trigger resume.
            if let gps = provider as? GPSRunDataProvider {
                gps.onSpeedTick = { [weak self] speed in
                    self?.autoPauseService.processSample(speedMps: speed)
                }
            }
        } else {
            autoPauseService.isEnabled = false
        }

        provider.onRunSample = { [weak self] sample in
            self?.handleRunSample(sample)
        }
        provider.start()

        // Every run uses a workout-relative clock, including gaps between BLE packets.
        startDisplayTimer()
        let state = liveActivityState()
        let id = sessionID.uuidString
        let title = plannedWorkoutTitle ?? "Free Run"
        let isOutdoor = provider.dataSourceType == "gps"
        Task { @MainActor in
            RunLiveActivityCoordinator.shared.start(sessionID: id, title: title,
                                                    isOutdoor: isOutdoor, state: state)
        }
    }

    // MARK: - Heart Rate Capture

    /// Start the BLE heart-rate scanner and subscribe to its readings.
    /// Fitbit/Pixel watches broadcast during exercises when "Broadcast heart
    /// rate" is on; chest straps broadcast always. FTMS console HR (treadmill)
    /// flows in via handleRunSample as a fallback.
    private func startHeartRateCapture() {
        hrSamples = []
        speedSamples = []
        // HeartRateManager is @MainActor; RunViewModel is not — hop over.
        Task { @MainActor [weak self] in
            guard let self else { return }
            let manager = HeartRateManager.shared
            manager.startScanning()

            manager.$currentBPM
                .receive(on: DispatchQueue.main)
                .sink { [weak self] bpm in
                    guard let self else { return }
                    if let bpm, bpm > 0 { self.recordHeartRate(bpm) }
                    // An absent watch reading must not erase the treadmill's HR fallback.
                    else if self.hrSamples.last.map({ self.elapsedTime - $0.t > 10 }) != false { self.heartRate = 0 }
                }
                .store(in: &self.hrCancellables)

            manager.$isConnected
                .receive(on: DispatchQueue.main)
                .sink { [weak self] connected in
                    self?.hrSourceConnected = connected
                }
                .store(in: &self.hrCancellables)
        }
    }

    /// Update live UI state and append to the run's HR log (~1Hz cap).
    private func recordHeartRate(_ bpm: Int) {
        heartRate = bpm
        heartRateZone = HeartRateZone.zone(forBPM: bpm)
        guard !isPaused else { return }
        // Cap logging at one sample per second of elapsed run time
        if let last = hrSamples.last, elapsedTime - last.t < 1.0 { return }
        hrSamples.append((t: elapsedTime, bpm: bpm))
    }

    private func stopHeartRateCapture() {
        hrCancellables.removeAll()
        hrSourceConnected = false
        Task { @MainActor in
            HeartRateManager.shared.stopAndDisconnect()
        }
    }

    private func startDisplayTimer() {
        displayTimerStart = Date()
        displayTimerPausedDuration = 0
        displayTimerPauseStart = nil
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.tickDisplayTimer()
            }
        }
    }

    private func tickDisplayTimer() {
        guard !runStopped, let start = displayTimerStart else { return }
        if isPaused {
            // Update current pause duration
            if let pauseStart = displayTimerPauseStart {
                currentPauseDuration = Date().timeIntervalSince(pauseStart)
            }
            return
        }
        elapsedTime = Date().timeIntervalSince(start) - displayTimerPausedDuration
        updateIntervalEngine()
        publishLiveActivity()
        checkWorkoutCompletion()
        persistRunCheckpoint()
    }

    /// Load a planned workout's targets into the view model.
    func loadPlannedWorkout(_ workout: Workout) {
        isPlannedRun = true
        plannedWorkoutId = workout.id
        plannedWorkoutTitle = workout.title
        plannedWorkoutDetails = workout.details
        plannedWorkoutType = workout.workoutType
        targetDistanceKm = workout.distanceKm
        plannedPaceDescription = workout.paceDescription
        targetPaceDescription = workout.paceDescription
        targetDurationMinutes = workout.durationMinutes

        pacePhaseAnnouncement = nil
        progressionIndex = 0
        lastPacePhaseChangeTime = -.infinity
        progressionSegments = IntervalWorkoutParser.progression(workout.details, totalKm: workout.distanceKm)

        // Structured workout? Build the auto-advancing segment list.
        intervalSegments = IntervalWorkoutParser.parse(workout.details ?? workout.title)
        isStrideWorkout = false
        if intervalSegments.isEmpty {
            intervalSegments = IntervalWorkoutParser.strides(workout.details ?? workout.title,
                totalKm: workout.distanceKm, easyPace: workout.paceDescription)
            isStrideWorkout = !intervalSegments.isEmpty
        }
        intervalPrescriptionWarning = nil
        if intervalSegments.isEmpty, [.intervals, .fartlek, .hillRepeats].contains(workout.workoutType) {
            intervalPrescriptionWarning = workout.details ?? workout.title
        }
        segmentStartTime = 0
        segmentStartDistance = 0
        intervalPhaseDistanceDone = 0
        intervalIndex = 0
        intervalComplete = false
        if let first = intervalSegments.first {
            intervalPhaseRemaining = first.durationSec ?? 0
        }

        // Parse pace range for lane guidance
        if let range = RunScoringService.parsePaceRange(workout.paceDescription) {
            if range.min == range.max {
                // Single pace value — apply ±15 sec/km buffer
                targetPaceMinSec = range.min - 15
                targetPaceMaxSec = range.max + 15
            } else {
                targetPaceMinSec = range.min
                targetPaceMaxSec = range.max
            }
        }
        basePaceMin = targetPaceMinSec
        basePaceMax = targetPaceMaxSec
        if let first = intervalSegments.first { applyIntervalPace(first) }
        if let first = progressionSegments.first {
            applyIntervalPace(first)
            targetPaceDescription = first.paceText
        }
    }

    /// Snapshot the current run state into a RunResult for the summary screen.
    func buildRunResult() -> RunResult {
        let avgPace: Double = distance > 0 ? elapsedTime / distance : 0

        // Extract route/elevation from GPS provider if applicable
        let routeJSON: String?
        let elevGain: Double?
        let elevLoss: Double?
        if let gpsProvider = dataProvider as? GPSRunDataProvider {
            routeJSON = gpsProvider.encodeRouteJSON()
            elevGain = gpsProvider.elevationGain > 0 ? gpsProvider.elevationGain : nil
            elevLoss = gpsProvider.elevationLoss > 0 ? gpsProvider.elevationLoss : nil
        } else if let simProvider = dataProvider as? SimulatedGPSRunDataProvider {
            routeJSON = simProvider.encodeRouteJSON()
            elevGain = simProvider.elevationGain > 0 ? simProvider.elevationGain : nil
            elevLoss = simProvider.elevationLoss > 0 ? simProvider.elevationLoss : nil
        } else {
            routeJSON = nil
            elevGain = nil
            elevLoss = nil
        }

        // Heart rate summary from the per-run sample log
        let avgHR: Int? = hrSamples.isEmpty ? nil : hrSamples.map(\.bpm).reduce(0, +) / hrSamples.count
        let maxHR: Int? = hrSamples.map(\.bpm).max()
        let hrJSON: String? = {
            guard !hrSamples.isEmpty else { return nil }
            let codable = hrSamples.map { CodableHRSample(t: $0.t, bpm: $0.bpm) }
            guard let data = try? JSONEncoder().encode(codable) else { return nil }
            return String(data: data, encoding: .utf8)
        }()

        return RunResult(
            sessionID: sessionID,
            completedAt: runFinishedAt ?? Date(),
            distanceKm: distance,
            durationSeconds: elapsedTime,
            avgPaceSecPerKm: avgPace,
            kmSplits: kilometerSplits,
            plannedWorkoutId: isPlannedRun ? plannedWorkoutId : nil,
            plannedWorkoutTitle: plannedWorkoutTitle,
            plannedWorkoutType: plannedWorkoutType,
            targetDistanceKm: targetDistanceKm,
            targetPaceDescription: plannedPaceDescription ?? targetPaceDescription,
            targetDurationMinutes: targetDurationMinutes,
            dataSource: dataProvider?.dataSourceType ?? "manual",
            treadmillBrand: dataProvider?.deviceName,
            routeJSON: routeJSON,
            elevationGainMeters: elevGain,
            elevationLossMeters: elevLoss,
            avgHeartRate: avgHR,
            maxHeartRate: maxHR,
            hrSamplesJSON: hrJSON,
            speedSamples: speedSamples,
            plannedWorkoutDetails: plannedWorkoutDetails,
            totalPauseDurationSeconds: displayTimerPausedDuration,
            completedPauseDurations: completedPauseDurations
        )
    }

    /// Reset all state for a new run.
    func reset() {
        finishLiveActivity()
        if let recoveryOwnerID { RunRecoveryStore.remove(ownerID: recoveryOwnerID) }
        recoveryOwnerID = nil
        lastCheckpointAt = nil
        runFinishedAt = nil
        sessionID = UUID()
        // Stop any active provider
        dataProvider?.stop()
        dataProvider = nil

        workoutCompleted = false
        consolePace = nil
        consolePaceTimestamp = nil
        runStopped = false
        elapsedTime = 0
        distance = 0.0
        speedKmh = 0
        currentPace = "--:--"
        paceDrift = "--"
        heartRate = 0
        heartRateZone = .zone2
        stopHeartRateCapture()
        hrSamples = []
        speedSamples = []
        kilometerSplits = []
        paceGraphDataPoints = []
        paceGraphPaces = []
        paceGraphHeartRates = []
        paceGraphDistances = []
        intervalPrescriptionWarning = nil
        paceGraphSamples = []
        isStrideWorkout = false
        progressionSegments = []
        progressionIndex = 0
        pacePhaseAnnouncement = nil
        intervalSegments = []
        intervalIndex = 0
        intervalPhaseRemaining = 0
        intervalPhaseDistanceDone = 0
        intervalComplete = false
        segmentStartTime = 0
        segmentStartDistance = 0
        lastRecordedKm = 0
        lastKmElapsedTime = 0
        lastKmDistance = 0
        driftSamples = []
        paceSmoother.reset()
        liveSpeedSmoother.reset()

        // Reset split feedback
        splitFeedbackTimer?.invalidate()
        splitFeedbackTimer = nil
        splitFeedback = nil

        // Reset fallback timer
        runStartTime = nil
        appElapsedTime = 0
        usingFallbackTimer = false

        // Reset anomaly tracking
        timeAnomalyCount = 0
        distanceAnomalyCount = 0
        lastTreadmillTime = 0

        // Clear planned workout targets
        isPlannedRun = false
        plannedWorkoutId = nil
        plannedWorkoutTitle = nil
        plannedWorkoutDetails = nil
        plannedWorkoutType = nil
        targetDistanceKm = nil
        targetPaceDescription = nil
        plannedPaceDescription = nil
        targetDurationMinutes = nil

        // Clear pace zone
        targetPaceMinSec = nil
        targetPaceMaxSec = nil
        paceZone = .noTarget
        distanceOnlyMode = false

        // Clear GPS state
        routeCoordinates = []
        isPaused = false
        completedPauseDurations = []
        currentAltitude = nil
        autoPauseService.reset()
        voiceCoach.reset()
        midRunCoach.reset()

        // Stop display timer
        displayTimer?.invalidate()
        displayTimer = nil
        displayTimerStart = nil
        displayTimerPausedDuration = 0
        displayTimerPauseStart = nil
    }

    // MARK: - Stop Run (called when finishing, before summary screen)

    /// Stops the data provider, timer, and voice coach without clearing state.
    /// Call this after buildRunResult() so the summary screen still has data.
    func stopRun() {
        finishLiveActivity()
        runFinishedAt = runFinishedAt ?? Date()
        runStopped = true
        persistRunCheckpoint(force: true)
        dataProvider?.stop()
        stopHeartRateCapture()
        displayTimer?.invalidate()
        displayTimer = nil
        voiceCoach.reset()
        midRunCoach.reset()
        autoPauseService.reset()
    }

    // MARK: - Pause / Resume

    func pauseRun() {
        guard !runStopped else { return }
        dataProvider?.pause()
        isPaused = true
        publishLiveActivity(force: true)
        displayTimerPauseStart = Date()
        voiceCoach.announcePaused()
        persistRunCheckpoint(force: true)
    }

    func resumeRun() {
        guard !runStopped else { return }
        liveSpeedSmoother.reset()
        paceSmoother.reset()
        dataProvider?.resume()
        if let pauseStart = displayTimerPauseStart {
            let pauseDuration = Date().timeIntervalSince(pauseStart)
            displayTimerPausedDuration += pauseDuration
            completedPauseDurations.append(pauseDuration)
        }
        displayTimerPauseStart = nil
        currentPauseDuration = 0
        isPaused = false
        publishLiveActivity(force: true)
        candidateZoneSince = elapsedTime
        voiceCoach.delayPaceUpdates(after: elapsedTime)
        voiceCoach.announceResumed()
    }

    // MARK: - Unified Data Handler

    private func handleRunSample(_ sample: RunSample) {
        guard !runStopped, !isPaused else { return }
        // The workout clock starts when Start is pressed, independent of console totals.
        // An independent timer also continues through temporary BLE outages.
        // 2. Distance — validated: never allow regression (meters -> km)
        if let distanceMeters = sample.totalDistanceMeters {
            let newDistanceKm = distanceMeters / 1000.0
            if newDistanceKm >= distance {
                distance = newDistanceKm
            } else {
                // REGRESSION DETECTED: provider sent a lower distance
                distanceAnomalyCount += 1
                runLog.error(
                    "Distance regression anomaly #\(self.distanceAnomalyCount): provider sent \(distanceMeters)m but current is \(self.distance * 1000.0)m. Ignoring."
                )
                // Keep the existing (higher) distance value
            }
        }

        if let speed = sample.speedMps {
            recordSpeedSample(speed)
        }

        // 3. GPS route coordinates (for live map drawing)
        if let coordinate = sample.coordinate {
            routeCoordinates.append(coordinate)
        }
        if let altitude = sample.altitudeMeters {
            currentAltitude = altitude
        }

        // 3b. Auto-pause detection runs off GPSRunDataProvider.onSpeedTick so it
        // keeps receiving samples while paused. Nothing to do here.

        // 3c. Heart rate from the provider (FTMS consoles report it). The BLE
        // broadcast path takes priority — only use console HR when no
        // broadcaster is attached, so we don't interleave two sources.
        if let bpm = sample.heartRate, bpm > 0, !hrSourceConnected {
            recordHeartRate(bpm)
        }

        // Apply distance boundaries before comparing this sample with the target.
        updateIntervalEngine()

        // Live console speed describes current effort; odometer pace describes
        // distance over time. Do not force these different measurements to agree.
        let fallback = paceSmoother.addSample(
            distanceMeters: distance * 1000.0,
            elapsedTime: elapsedTime
        ).smoothedPace
        let pace: Double
        if dataProvider?.dataSourceType == "bluetooth_ftms" {
            if let speed = sample.speedMps, speed.isFinite, speed >= 0 {
                pace = liveSpeedSmoother.addSample(speedMps: speed, timestamp: sample.timestamp)
            } else {
                // A continuation packet may omit speed; retain the latest live
                // value briefly instead of alternating with odometer estimates.
                pace = lastConsolePace(at: sample.timestamp) ?? fallback
            }
            if let speed = sample.speedMps, speed.isFinite, speed >= 0 {
                consolePace = pace
                consolePaceTimestamp = sample.timestamp
            }
        } else {
            pace = fallback
        }
        if pace > 0 {
            currentPace = formatPace(secondsPerKm: pace)

            // Feed pace graph (pass current distance in metres for distance-based windowing)
            appendPaceGraphSample(pace, atDistanceMeters: distance * 1000.0)

            // 5. Pace Drift — current pace vs. completed-km baseline
            updatePaceDrift()

            // 6. Pace Zone — compare current pace to target range
            updatePaceZone(pace)
        } else {
            candidateZoneSince = elapsedTime
            // Stopped, or not enough window yet — show --:-- for pace
            speedKmh = 0
        currentPace = "--:--"
            paceDrift = "--"
        }



        voiceCoach.checkPaceUpdate(
            distanceKm: distance, elapsedTime: elapsedTime, pace: pace,
            targetMin: targetPaceMinSec, targetMax: targetPaceMaxSec,
            reliable: pace.isFinite && pace > 0 && elapsedTime >= 12 &&
                (paceZone == .noTarget || elapsedTime - candidateZoneSince >= 12)
        )

        // 7. Kilometer Split Detection
        checkForKilometerSplit()
        persistRunCheckpoint()
        publishLiveActivity()

        if checkWorkoutCompletion() { return }

        // 8. Voice: progress milestones (halfway, "X km to go", time checkpoints)
        voiceCoach.checkProgressMilestones(
            currentDistanceKm: distance,
            elapsedTime: elapsedTime,
            targetDistanceKm: targetDistanceKm,
            targetDurationMinutes: targetDurationMinutes
        )

        // 9. Intelligent mid-run coaching (terrain + finish push + performance context)
        let routePoints: [RoutePoint]?
        let isGPS: Bool
        if let gpsProvider = dataProvider as? GPSRunDataProvider {
            routePoints = gpsProvider.routePoints
            isGPS = true
        } else if let simProvider = dataProvider as? SimulatedGPSRunDataProvider {
            routePoints = simProvider.routePoints
            isGPS = true
        } else {
            routePoints = nil
            isGPS = false
        }
        midRunCoach.update(
            routePoints: routePoints,
            currentDistanceKm: distance,
            targetDistanceKm: targetDistanceKm,
            elapsedTime: elapsedTime,
            smoothedPaceSecPerKm: nil, // pace zone already handles smoothing
            kmSplits: kilometerSplits,
            isGPSRun: isGPS
        )
    }

    private func liveActivityState() -> StrideRunAttributes.ContentState {
        StrideRunAttributes.ContentState(
            pace: currentPace,
            distanceKm: distance,
            targetDistanceKm: targetDistanceKm,
            elapsedSeconds: Int(elapsedTime),
            heartRate: heartRate > 0 ? heartRate : nil,
            isPaused: isPaused,
            updatedAt: Date()
        )
    }

    private func publishLiveActivity(force: Bool = false) {
        guard dataProvider != nil, !runStopped else { return }
        let id = sessionID.uuidString
        let state = liveActivityState()
        Task { @MainActor in
            RunLiveActivityCoordinator.shared.publish(sessionID: id, state: state, force: force)
        }
    }

    private func finishLiveActivity() {
        let id = sessionID.uuidString
        let state = liveActivityState()
        Task { @MainActor in
            RunLiveActivityCoordinator.shared.finish(sessionID: id, state: state)
        }
    }

    /// Full-run history is independent of the rolling 500 m graph. Missing speed
    /// fields never call this method, while real stops remain zero-speed readings.
    private func recordSpeedSample(_ speedMps: Double) {
        guard !isPaused, !runStopped, speedMps.isFinite, speedMps >= 0 else { return }
        speedKmh = speedMps * 3.6
        if speedSamples.last.map({ elapsedTime - $0.t >= 1 }) ?? true {
            speedSamples.append(RunSpeedSample(t: elapsedTime, kmh: speedKmh))
        }
    }

    private var consolePace: Double?
    private var consolePaceTimestamp: Date?

    private func lastConsolePace(at timestamp: Date) -> Double? {
        guard let last = consolePaceTimestamp,
              timestamp.timeIntervalSince(last) <= 3 else { return nil }
        return consolePace
    }

    /// Structured sessions finish after their final phase, including cooldown.
    /// Otherwise distance takes precedence over an estimated duration.
    @discardableResult
    private func checkWorkoutCompletion() -> Bool {
        guard !runStopped, !isPaused else { return false }
        let reached: Bool
        if isIntervalWorkout && !isStrideWorkout {
            reached = intervalComplete
        } else if let target = targetDistanceKm, target > 0 {
            reached = distance >= target
        } else if let minutes = targetDurationMinutes, minutes > 0 {
            reached = elapsedTime >= Double(minutes) * 60
        } else {
            reached = false
        }
        guard reached else { return false }
        stopRun()
        voiceCoach.announceWorkoutCompleted()
        workoutCompleted = true
        return true
    }

    // MARK: - Pace Formatting

    private func formatPace(secondsPerKm: Double) -> String {
        guard secondsPerKm > 0 && secondsPerKm < 3600 else { return "--:--" }
        let minutes = Int(secondsPerKm) / 60
        let seconds = Int(secondsPerKm) % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    /// Format seconds/km as "M:SS /km" for display in boundary labels.
    static func formatPaceDisplay(secondsPerKm: Double) -> String {
        guard secondsPerKm > 0 && secondsPerKm < 3600 else { return "--:--" }
        let minutes = Int(secondsPerKm) / 60
        let seconds = Int(secondsPerKm) % 60
        return "\(minutes):\(String(format: "%02d", seconds)) /km"
    }

    // MARK: - Pace Zone

    /// The zone we're currently evaluating (may differ from the announced `paceZone`
    /// because we require sustained residency before announcing).
    private var candidateZone: PaceZone = .noTarget
    private var candidateZoneSince: TimeInterval = 0
    /// Sustained duration before announcing a new off-pace zone — stays generous to
    /// avoid false positives from transient pace noise.
    private let sustainedZoneDuration: TimeInterval = 30.0
    /// Shorter window for the recovery transition (off-pace → on-pace) so runners
    /// get fast confirmation that their micro-adjustments worked.
    private let recoveryZoneDuration: TimeInterval = 12.0

    private func updatePaceZone(_ smoothedPace: Double) {
        guard let minPace = targetPaceMinSec, let maxPace = targetPaceMaxSec,
              minPace.isFinite, maxPace.isFinite, minPace > 0, maxPace >= minPace,
              smoothedPace.isFinite, smoothedPace > 0 else {
            paceZone = .noTarget
            candidateZone = .noTarget
            candidateZoneSince = elapsedTime
            return
        }

        let newZone: PaceZone
        if smoothedPace >= minPace && smoothedPace <= maxPace {
            newZone = .onPace
        } else if smoothedPace < minPace {
            let diff = minPace - smoothedPace
            newZone = diff > 10 ? .tooFast : .slightlyFast
        } else {
            let diff = smoothedPace - maxPace
            newZone = diff > 20 ? .tooSlow : .slightlySlow
        }

        // Track how long we've been in the candidate zone.
        if newZone != candidateZone {
            candidateZone = newZone
            candidateZoneSince = elapsedTime
        }

        // Asymmetric gating: recovery (off-pace → on-pace) uses a shorter window so
        // runners hear "back on pace" quickly after a correction.
        let isRecovery = candidateZone == .onPace && paceZone.isOffPace
        let requiredDuration = isRecovery ? recoveryZoneDuration : sustainedZoneDuration

        let sustained = elapsedTime - candidateZoneSince >= requiredDuration
        if sustained && candidateZone != paceZone {
            let oldZone = paceZone
            paceZone = candidateZone

            // Suppress pace-zone voice once we've pivoted to distance-only; UI still updates.
            if !distanceOnlyMode {
                // Compute how far off target so the voice alert can say specific seconds.
                let targetMid = ((minPace + maxPace) / 2.0)
                let diffSeconds = Int(round(smoothedPace - targetMid))
                voiceCoach.announcePaceZoneChange(from: oldZone, to: paceZone, diffSeconds: diffSeconds)
            }
        }
    }

    // MARK: - Pace Pivot (point of no return)

    /// After halfway, if the runner's last two splits were both so far off the
    /// required finish pace that they can't realistically catch up, flip to
    /// distance-only mode: suppress pace-zone alerts and play a single handoff cue.
    /// One-way — we don't flip back even if a later split surges.
    private func evaluatePacePivot() {
        guard !distanceOnlyMode else { return }
        guard let target = targetDistanceKm, target > 0 else { return }
        guard let targetMax = targetPaceMaxSec, targetPaceMinSec != nil else { return }
        guard kilometerSplits.count >= 2 else { return }

        let distRemaining = target - distance
        guard distRemaining > 0.2 else { return }    // too close to finish to matter

        let pastHalfway = distance >= target * 0.5
        let targetTotalTime = targetMax * target
        let timeOverrun = elapsedTime >= targetTotalTime

        // Hard pivot: already past the target clock regardless of distance progress.
        if timeOverrun {
            triggerPacePivot(reason: "over target time")
            return
        }

        // Soft pivot: past halfway AND last two splits were both >30s/km slower
        // than the pace required to still finish at the target's slow edge.
        guard pastHalfway else { return }
        let timeRemaining = targetTotalTime - elapsedTime
        let requiredPace = timeRemaining / distRemaining

        let recent = kilometerSplits.suffix(2).compactMap { split -> Double? in
            guard let secs = split.pace.toSeconds else { return nil }
            return Double(secs)
        }
        guard recent.count == 2 else { return }

        let deficitThreshold: Double = 30.0    // sec/km
        if recent.allSatisfy({ $0 > requiredPace + deficitThreshold }) {
            triggerPacePivot(reason: "two splits >\(Int(deficitThreshold))s/km off required")
        }
    }

    private func triggerPacePivot(reason: String) {
        distanceOnlyMode = true
        voiceCoach.announceDistancePivot()
        runLog.info("Pace pivot → distance-only at km \(self.distance) (\(reason))")
    }

    // MARK: - Pace Drift

    private func updatePaceDrift() {
        // No baseline until at least 1 km is completed
        guard lastRecordedKm >= 1 else {
            paceDrift = "--"
            return
        }

        let currentDistanceMeters = distance * 1000.0

        // Append sample to drift ring buffer
        driftSamples.append((distance: currentDistanceMeters, time: elapsedTime))

        // Trim samples older than the 50m window behind current distance
        let cutoff = currentDistanceMeters - driftWindowMeters
        if cutoff > 0 {
            driftSamples.removeAll { $0.distance < cutoff }
        }

        // Need enough samples to span the window
        guard let first = driftSamples.first, let last = driftSamples.last else {
            paceDrift = "--"
            return
        }

        let span = last.distance - first.distance
        guard span >= driftWindowMeters else {
            // Still bootstrapping the 50m window
            paceDrift = "--"
            return
        }

        // Windowed pace: sec/km over the last 50m
        let windowedPace = (last.time - first.time) / (span / 1000.0)

        // Baseline: average pace of all completed kms
        let baseline = lastKmElapsedTime / Double(lastRecordedKm)

        let drift = windowedPace - baseline  // positive = slower, negative = faster

        if abs(drift) < 0.5 {
            paceDrift = "0.0s"
        } else if drift > 0 {
            paceDrift = "+\(String(format: "%.1f", drift))s"
        } else {
            paceDrift = "\(String(format: "%.1f", drift))s"
        }
    }

    // MARK: - Kilometer Split Detection

    private func checkForKilometerSplit() {
        let totalDistanceMeters = distance * 1000.0
        let currentKm = Int(floor(totalDistanceMeters / 1000.0))

        // Check if we've crossed a new km boundary
        guard currentKm > lastRecordedKm && currentKm >= 1 else { return }

        // Log every km we might have missed (in case of a data gap)
        for km in (lastRecordedKm + 1)...currentKm {
            let kmElapsedTime = elapsedTime // time at this km boundary

            // ONE source of truth: split pace = split time. A 1 km segment's
            // pace IS its elapsed time — display, voice, and the math must
            // always agree (speed-sample averaging drifted from clock time).
            let kmSegmentTime: TimeInterval = km == 1 ? kmElapsedTime : kmElapsedTime - lastKmElapsedTime
            let paceSecPerKm: Double = kmSegmentTime

            let paceString = formatPace(secondsPerKm: paceSecPerKm)

            // Cumulative time formatted as HH:MM:SS (unchanged — real wall-clock time)
            let cumulativeTime = formatCumulativeTime(kmElapsedTime)

            let split = KilometerSplit(
                kilometer: km,
                pace: paceString,
                time: cumulativeTime,
                isFastest: false,
                diffFromFastest: nil
            )

            kilometerSplits.append(split)
            lastKmElapsedTime = kmElapsedTime
            lastKmDistance = distance * 1000.0
        }

        lastRecordedKm = currentKm

        // Show split feedback card for the most recent split
        if let latestSplit = kilometerSplits.last {
            showSplitFeedback(for: latestSplit)

            // Voice: announce the completed km split, unless this km coincides with
            // a milestone that will speak its own line (halfway, finish) — in which case
            // the milestone announcement replaces the standard split.
            // The finishing km belonged to the preceding target. Let the new phase
            // instruction take priority rather than judging it against the faster target.
            if elapsedTime - lastPacePhaseChangeTime > 3, let paceSeconds = latestSplit.pace.toSeconds {
                let avgPace = distance > 0 ? elapsedTime / distance : 0
                let kmDouble = Double(latestSplit.kilometer)

                // Halfway collision: km boundary == target/2 and halfway not yet announced.
                let halfwayOnThisKm: Bool = {
                    guard let target = targetDistanceKm, target > 0 else { return false }
                    guard !voiceCoach.halfwayAnnounced else { return false }
                    return abs(target / 2.0 - kmDouble) < 0.05
                }()

                // Finish collision: km boundary == target (exact whole-km target).
                let finishOnThisKm: Bool = {
                    guard let target = targetDistanceKm, target > 0 else { return false }
                    return abs(target - kmDouble) < 0.05
                }()

                if finishOnThisKm {
                    // Fire the celebratory finish announcement in place of the standard split.
                    let trend = midRunCoach.performanceTrend(kmSplits: kilometerSplits)
                    let avgPaceAll = distance > 0 ? elapsedTime / distance : 0
                    let heldTarget: Bool = {
                        guard let minP = targetPaceMinSec, let maxP = targetPaceMaxSec else { return false }
                        return avgPaceAll >= minP && avgPaceAll <= maxP
                    }()
                    voiceCoach.announceTargetReached(
                        finalKm: latestSplit.kilometer,
                        finalSplitPaceSecPerKm: Double(paceSeconds),
                        totalElapsedTime: elapsedTime,
                        trend: trend,
                        withinTargetPace: heldTarget
                    )
                    midRunCoach.onKmSplitAnnounced()
                } else if halfwayOnThisKm {
                    // Suppress the standard split — checkProgressMilestones will fire
                    // the halfway announcement on this same sample, which already
                    // includes km-down / km-to-go / total time.
                    midRunCoach.onKmSplitAnnounced()
                } else {
                    // Every split states where the athlete stands vs target —
                    // even after a pace pivot, information keeps flowing.
                    let comparison: String? = {
                        guard let minP = targetPaceMinSec, let maxP = targetPaceMaxSec else { return nil }
                        let pace = Double(paceSeconds)
                        if pace < minP - 1 { return "\(Int(minP - pace)) seconds ahead of target." }
                        if pace > maxP + 1 { return "\(Int(pace - maxP)) seconds behind target." }
                        return "Right on target."
                    }()
                    voiceCoach.announceKmSplit(
                        kilometer: latestSplit.kilometer,
                        paceSecPerKm: Double(paceSeconds),
                        totalElapsedTime: elapsedTime,
                        avgPaceSecPerKm: latestSplit.kilometer >= 2 ? avgPace : nil,
                        isDistanceFocused: isDistanceFocusedWorkout,
                        targetComparison: comparison
                    )
                    midRunCoach.onKmSplitAnnounced()
                }
            }
        }

        // Re-evaluate fastest split
        markFastestSplit()

        // Evaluate whether to pivot to distance-only coaching.
        evaluatePacePivot()
    }

    /// Find the fastest split, mark it with isFastest, and compute diff-from-fastest for each split.
    private func markFastestSplit() {
        guard !kilometerSplits.isEmpty else { return }

        // Parse pace strings back to seconds for comparison
        var fastestIndex = 0
        var fastestSeconds: Int = Int.max

        for (index, split) in kilometerSplits.enumerated() {
            if let seconds = split.pace.toSeconds, seconds < fastestSeconds {
                fastestSeconds = seconds
                fastestIndex = index
            }
        }

        // Rebuild splits with correct isFastest flags and diff-from-fastest
        kilometerSplits = kilometerSplits.enumerated().map { (index, split) in
            let diff: Int? = split.pace.toSeconds.map { $0 - fastestSeconds }
            return KilometerSplit(
                kilometer: split.kilometer,
                pace: split.pace,
                time: split.time,
                isFastest: index == fastestIndex,
                diffFromFastest: diff
            )
        }
    }

    // MARK: - Split Feedback

    private func showSplitFeedback(for split: KilometerSplit) {
        guard let splitSeconds = split.pace.toSeconds else { return }

        // Find current fastest pace (excluding the new split)
        let priorSplits = kilometerSplits.dropLast()
        let fastestSeconds = priorSplits.compactMap { $0.pace.toSeconds }.min()

        let category: SplitFeedback.Category
        let diffSeconds: Int?

        if let fastest = fastestSeconds {
            let diff = splitSeconds - fastest
            diffSeconds = diff
            if diff <= 0 {
                category = .faster
            } else if diff <= 3 {
                category = .neutral
            } else {
                category = .slower
            }
        } else {
            // First split — no comparison available
            diffSeconds = nil
            category = .neutral
        }

        splitFeedback = SplitFeedback(
            pace: split.pace,
            diffSeconds: diffSeconds,
            category: category
        )

        // Auto-dismiss after 45 seconds (user can also swipe to dismiss)
        splitFeedbackTimer?.invalidate()
        splitFeedbackTimer = Timer.scheduledTimer(withTimeInterval: 45.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.splitFeedback = nil
            }
        }
    }

    private func formatCumulativeTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    // MARK: - Pace Graph

    // MARK: - Interval Engine

    private func updateProgressionPace() {
        guard !isPaused, !runStopped, progressionSegments.count > 1 else { return }
        var boundary = 0.0
        var activeIndex = 0
        for index in 0..<(progressionSegments.count - 1) {
            boundary += progressionSegments[index].distanceKm ?? 0
            if distance >= boundary { activeIndex = index + 1 }
        }
        guard activeIndex != progressionIndex else { return }
        progressionIndex = activeIndex
        lastPacePhaseChangeTime = elapsedTime
        let segment = progressionSegments[activeIndex]
        applyIntervalPace(segment)
        targetPaceDescription = segment.paceText
        candidateZone = .noTarget
        candidateZoneSince = elapsedTime
        distanceOnlyMode = false
        let distanceText = VoiceCoachService.spokenDistance(segment.distanceKm ?? 0)
        pacePhaseAnnouncement = "Final \(distanceText) km · Target \(segment.paceText) /km"
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        voiceCoach.announcePacePhase(paceText: segment.paceText, distanceKm: segment.distanceKm ?? 0)
    }

    private func updateIntervalEngine() {
        updateProgressionPace()
        guard !isPaused, !runStopped, isIntervalWorkout, !intervalComplete,
              intervalIndex < intervalSegments.count else { return }
        let segment = intervalSegments[intervalIndex]

        if let duration = segment.durationSec {
            let inPhase = elapsedTime - segmentStartTime
            intervalPhaseRemaining = max(0, duration - inPhase)
            // Three rising pings lead into the next phase, including recovery.
            let whole = Int(ceil(intervalPhaseRemaining))
            if whole <= 3, whole >= 1, whole != lastCountdownTick {
                lastCountdownTick = whole
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                IntervalCuePlayer.shared.countdown(whole)
            }
            if inPhase >= duration {
                let boundary = segmentStartTime + duration
                advanceIntervalSegment()
                if !intervalComplete {
                    segmentStartTime = boundary
                    updateIntervalEngine()
                }
            }
        } else if let dist = segment.distanceKm {
            intervalPhaseDistanceDone = max(0, distance - segmentStartDistance)
            if intervalPhaseDistanceDone >= dist { advanceIntervalSegment() }
        }
    }

    private func advanceIntervalSegment() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        IntervalCuePlayer.shared.completed()
        lastCountdownTick = -1
        segmentStartTime = elapsedTime
        segmentStartDistance = distance
        intervalPhaseDistanceDone = 0

        if intervalIndex + 1 < intervalSegments.count {
            intervalIndex += 1
            let segment = intervalSegments[intervalIndex]
            intervalPhaseRemaining = segment.durationSec ?? 0
            applyIntervalPace(segment)
        } else {
            intervalComplete = true
            if isStrideWorkout {
                targetPaceMinSec = basePaceMin
                targetPaceMaxSec = basePaceMax
            }
        }
    }

    private func applyIntervalPace(_ segment: IntervalSegment) {
        // Every phase owns its target, including warm-up, recovery and cool-down.
        targetPaceMinSec = segment.paceBounds?.min
        targetPaceMaxSec = segment.paceBounds?.max
        paceZone = .noTarget
    }

    private func appendPaceGraphSample(_ paceSecPerKm: Double, atDistanceMeters currentDistance: Double) {
        guard paceSecPerKm > 0 && paceSecPerKm < 3600 else { return }

        // Store sample with its cumulative distance
        paceGraphSamples.append(PaceGraphSample(distanceMeters: currentDistance, pace: paceSecPerKm, bpm: heartRate > 0 ? heartRate : nil))

        // Trim to the last 500 metres of data
        let cutoff = currentDistance - graphWindowMeters
        if cutoff > 0 {
            paceGraphSamples.removeAll { $0.distanceMeters < cutoff }
        }

        let paces = paceGraphSamples.map { $0.pace }
        paceGraphPaces = paces
        paceGraphHeartRates = paceGraphSamples.map { $0.bpm }
        paceGraphDistances = paceGraphSamples.map { $0.distanceMeters }

        // Normalize: faster pace (lower sec/km) = higher on graph (closer to 1.0)
        guard let rawMin = paces.min(),
              let rawMax = paces.max() else {
            paceGraphDataPoints = paces.map { _ in 0.5 }
            return
        }

        // Adaptive Y-axis: use at least minYAxisRange (30s) so steady-state noise
        // appears as gentle ripples, but expand when real variation is larger (intervals).
        let actualRange = rawMax - rawMin
        let displayRange = max(actualRange, minYAxisRange)
        let midpoint = (rawMin + rawMax) / 2.0
        let displayMin = midpoint - displayRange / 2.0
        let displayMax = midpoint + displayRange / 2.0

        guard displayMax > displayMin else {
            paceGraphDataPoints = paces.map { _ in 0.5 }
            return
        }

        // Invert: lower pace (faster) = higher value on graph
        paceGraphDataPoints = paces.map { pace in
            1.0 - ((pace - displayMin) / (displayMax - displayMin))
        }
    }
}


/// Account-scoped, atomic snapshots survive process termination and auth-screen rebuilds.
/// Recovery opens the last measured state for review; it never invents unrecorded distance/time.
enum RunRecoveryStore {
    struct Checkpoint: Codable {
        let ownerID: String
        let savedAt: Date
        let result: RunResult
    }

    private static func fileURL(ownerID: String) -> URL? {
        guard let id = UUID(uuidString: ownerID),
              let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return directory.appendingPathComponent("stride-run-\(id.uuidString.lowercased()).json")
    }

    static func save(_ result: RunResult, ownerID: String) throws {
        guard let url = fileURL(ownerID: ownerID) else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Checkpoint(ownerID: ownerID, savedAt: Date(), result: result))
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try data.write(to: url, options: options)
    }

    static func load(ownerID: String) -> Checkpoint? {
        guard let url = fileURL(ownerID: ownerID), let data = try? Data(contentsOf: url),
              let checkpoint = try? JSONDecoder().decode(Checkpoint.self, from: data),
              checkpoint.ownerID.lowercased() == ownerID.lowercased(),
              checkpoint.result.distanceKm.isFinite, checkpoint.result.distanceKm >= 0,
              checkpoint.result.durationSeconds.isFinite, checkpoint.result.durationSeconds >= 0 else { return nil }
        return checkpoint
    }

    static func remove(ownerID: String) {
        guard let url = fileURL(ownerID: ownerID) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
