import Foundation
import SwiftUI
import Combine
import os.log

private let runLog = Logger(subsystem: "com.stride.app", category: "RunViewModel")

// MARK: - Run Result (snapshot of completed run data)
struct RunResult {
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
    let dataSource: String  // "bluetooth_ftms" | "manual"
    let treadmillBrand: String?

    var isPlannedRun: Bool { plannedWorkoutId != nil }
    
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
    @Published var currentPace: String = "--:--"          // M:SS /km (smoothed)
    @Published var paceDrift: String = "--"               // "+X.Xs" or "-X.Xs"
    @Published var heartRate: Int = 0                     // placeholder until Garmin phase
    @Published var heartRateZone: HeartRateZone = .zone2  // placeholder until Garmin phase
    @Published var kilometerSplits: [KilometerSplit] = []
    @Published var paceGraphDataPoints: [Double] = []     // normalized 0-1 for PaceGraphView
    @Published var splitFeedback: SplitFeedback? = nil

    // MARK: - Planned Workout Target (optional, set when running a planned workout)
    @Published var plannedWorkoutTitle: String?
    @Published var plannedWorkoutType: WorkoutType?
    @Published var targetDistanceKm: Double?
    @Published var targetPaceDescription: String?
    @Published var targetDurationMinutes: Int?
    @Published var isPlannedRun: Bool = false

    // MARK: - Pace Zone & Progress (live target comparison)
    @Published var targetPaceMinSec: Double?     // faster boundary (lower sec/km)
    @Published var targetPaceMaxSec: Double?     // slower boundary (higher sec/km)
    @Published var paceZone: PaceZone = .noTarget

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

    // MARK: - Internal State
    private var bluetoothManager: BluetoothManager?
    private let paceSmoother = PaceSmoother()

    // Kilometer split tracking
    private var lastRecordedKm: Int = 0
    private var lastKmElapsedTime: TimeInterval = 0       // elapsed time at last km boundary
    private var lastKmDistance: Double = 0                 // distance (m) at last km boundary

    // Pace graph: rolling (distance, pace) samples for distance-based windowing
    private struct PaceGraphSample {
        let distanceMeters: Double   // cumulative distance at this sample
        let pace: Double             // smoothed pace in sec/km
    }
    private var paceGraphSamples: [PaceGraphSample] = []
    /// The graph shows the last 500 metres of pace data
    private let graphWindowMeters: Double = 500.0
    /// Adaptive Y-axis: minimum range in sec/km so steady-state noise looks flat
    private let minYAxisRange: Double = 30.0

    // Split feedback auto-dismiss timer
    private var splitFeedbackTimer: Timer?

    // Speed samples for current km segment (used to compute split pace from speed, not elapsed time)
    private var currentKmSpeedSamples: [Double] = []      // raw speed in m/s

    // Pace drift: 50m rolling window, only after 1+ km completed
    private var driftSamples: [(distance: Double, time: Double)] = []
    private let driftWindowMeters: Double = 50.0

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

    /// Call this once to wire up the BluetoothManager callback.
    func attach(bluetoothManager: BluetoothManager) {
        self.bluetoothManager = bluetoothManager
        bluetoothManager.onTreadmillData = { [weak self] sample in
            self?.handleTreadmillData(sample)
        }
    }

    /// Load a planned workout's targets into the view model.
    func loadPlannedWorkout(_ workout: Workout) {
        isPlannedRun = true
        plannedWorkoutId = workout.id
        plannedWorkoutTitle = workout.title
        plannedWorkoutType = workout.workoutType
        targetDistanceKm = workout.distanceKm
        targetPaceDescription = workout.paceDescription
        targetDurationMinutes = workout.durationMinutes

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
    }
    
    /// Snapshot the current run state into a RunResult for the summary screen.
    func buildRunResult() -> RunResult {
        let avgPace: Double = distance > 0 ? elapsedTime / distance : 0
        let isBluetooth = bluetoothManager?.connectedDevice != nil

        return RunResult(
            distanceKm: distance,
            durationSeconds: elapsedTime,
            avgPaceSecPerKm: avgPace,
            kmSplits: kilometerSplits,
            plannedWorkoutId: isPlannedRun ? plannedWorkoutId : nil,
            plannedWorkoutTitle: plannedWorkoutTitle,
            plannedWorkoutType: plannedWorkoutType,
            targetDistanceKm: targetDistanceKm,
            targetPaceDescription: targetPaceDescription,
            targetDurationMinutes: targetDurationMinutes,
            dataSource: isBluetooth ? "bluetooth_ftms" : "manual",
            treadmillBrand: bluetoothManager?.connectedDevice?.name
        )
    }

    /// Reset all state for a new run.
    func reset() {
        elapsedTime = 0
        distance = 0.0
        currentPace = "--:--"
        paceDrift = "--"
        heartRate = 0
        kilometerSplits = []
        paceGraphDataPoints = []
        paceGraphSamples = []
        lastRecordedKm = 0
        lastKmElapsedTime = 0
        lastKmDistance = 0
        currentKmSpeedSamples = []
        driftSamples = []
        paceSmoother.reset()

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
        plannedWorkoutType = nil
        targetDistanceKm = nil
        targetPaceDescription = nil
        targetDurationMinutes = nil

        // Clear pace zone
        targetPaceMinSec = nil
        targetPaceMaxSec = nil
        paceZone = .noTarget
    }

    // MARK: - Treadmill Data Handler

    private func handleTreadmillData(_ sample: ParsedTreadmillSample) {
        // Start the app-side fallback timer on the very first data packet
        if runStartTime == nil {
            runStartTime = Date()
        }

        // Update app-side elapsed time on every packet (independent of treadmill)
        appElapsedTime = Date().timeIntervalSince(runStartTime!)

        // 1. Elapsed Time — validated: never allow regression
        if let treadmillTime = sample.elapsedTime {
            let newTime = TimeInterval(treadmillTime)

            if newTime >= elapsedTime {
                // Normal case: time moved forward (or stayed the same)

                // Check for unreasonable forward jump
                let jump = newTime - lastTreadmillTime
                if lastTreadmillTime > 0 && jump > maxReasonableTimeJump {
                    timeAnomalyCount += 1
                    runLog.warning(
                        "Time jump anomaly #\(self.timeAnomalyCount): \(self.lastTreadmillTime)s -> \(newTime)s (jump: \(jump)s)"
                    )
                }

                elapsedTime = newTime
                lastTreadmillTime = newTime
                usingFallbackTimer = false
            } else {
                // REGRESSION DETECTED: treadmill sent a lower time than we already have.
                // Discard the bad value and switch to app-side fallback timer.
                timeAnomalyCount += 1
                runLog.error(
                    "Time regression anomaly #\(self.timeAnomalyCount): treadmill sent \(newTime)s but current is \(self.elapsedTime)s. Using fallback timer."
                )
                usingFallbackTimer = true
                elapsedTime = appElapsedTime
            }
        } else if usingFallbackTimer {
            // No treadmill time in this packet and we're in fallback mode — use app timer
            elapsedTime = appElapsedTime
        }

        // 2. Distance — validated: never allow regression (meters -> km)
        if let distanceMeters = sample.totalDistanceMeters {
            let newDistanceKm = distanceMeters / 1000.0
            if newDistanceKm >= distance {
                distance = newDistanceKm
            } else {
                // REGRESSION DETECTED: treadmill sent a lower distance
                distanceAnomalyCount += 1
                runLog.error(
                    "Distance regression anomaly #\(self.distanceAnomalyCount): treadmill sent \(distanceMeters)m but current is \(self.distance * 1000.0)m. Ignoring."
                )
                // Keep the existing (higher) distance value
            }
        }

        // 3. Pace — smooth raw speed, then format
        if let rawSpeedMps = sample.speedMps, rawSpeedMps > 0 {
            let (_, pace) = paceSmoother.addSample(speedMps: rawSpeedMps)
            currentPace = formatPace(secondsPerKm: pace)

            // Accumulate raw speed for per-km split pace calculation
            currentKmSpeedSamples.append(rawSpeedMps)

            // Feed pace graph (pass current distance in metres for distance-based windowing)
            appendPaceGraphSample(pace, atDistanceMeters: distance * 1000.0)

            // 4. Pace Drift — current pace vs. completed-km baseline
            updatePaceDrift()

            // 5. Pace Zone — compare current pace to target range
            updatePaceZone(pace)
        } else if let rawSpeedMps = sample.speedMps, rawSpeedMps <= 0 {
            // Treadmill is stopped/paused — show --:-- for pace
            currentPace = "--:--"
            paceDrift = "--"
        }

        // 5. Kilometer Split Detection
        checkForKilometerSplit()
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

    private func updatePaceZone(_ smoothedPace: Double) {
        guard let minPace = targetPaceMinSec, let maxPace = targetPaceMaxSec else {
            paceZone = .noTarget
            return
        }

        if smoothedPace >= minPace && smoothedPace <= maxPace {
            paceZone = .onPace
        } else if smoothedPace < minPace {
            // Running faster than target (lower sec/km = faster)
            let diff = minPace - smoothedPace
            paceZone = diff > 10 ? .tooFast : .slightlyFast
        } else {
            // Running slower than target (higher sec/km = slower)
            let diff = smoothedPace - maxPace
            paceZone = diff > 20 ? .tooSlow : .slightlySlow
        }
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

            // Compute pace from accumulated speed samples (matches live pace & treadmill display).
            // Falls back to elapsed-time-based pace only if no speed samples exist.
            let paceSecPerKm: Double
            if !currentKmSpeedSamples.isEmpty {
                let avgSpeed = currentKmSpeedSamples.reduce(0, +) / Double(currentKmSpeedSamples.count)
                paceSecPerKm = avgSpeed > 0 ? 1000.0 / avgSpeed : 0
            } else {
                // Fallback: time-based pace (less accurate on self-powered treadmills)
                let kmSegmentTime: TimeInterval = km == 1 ? kmElapsedTime : kmElapsedTime - lastKmElapsedTime
                paceSecPerKm = kmSegmentTime
            }

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

            // Reset speed samples for the next km segment
            currentKmSpeedSamples.removeAll()
        }

        lastRecordedKm = currentKm

        // Show split feedback card for the most recent split
        if let latestSplit = kilometerSplits.last {
            showSplitFeedback(for: latestSplit)
        }

        // Re-evaluate fastest split
        markFastestSplit()
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

    private func appendPaceGraphSample(_ paceSecPerKm: Double, atDistanceMeters currentDistance: Double) {
        guard paceSecPerKm > 0 && paceSecPerKm < 3600 else { return }

        // Store sample with its cumulative distance
        paceGraphSamples.append(PaceGraphSample(distanceMeters: currentDistance, pace: paceSecPerKm))

        // Trim to the last 500 metres of data
        let cutoff = currentDistance - graphWindowMeters
        if cutoff > 0 {
            paceGraphSamples.removeAll { $0.distanceMeters < cutoff }
        }

        let paces = paceGraphSamples.map { $0.pace }

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
