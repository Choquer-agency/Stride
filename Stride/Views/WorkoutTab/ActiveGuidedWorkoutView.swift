import SwiftUI

/// Active guided workout view with interval tracking and progression
struct ActiveGuidedWorkoutView: View {
    @ObservedObject var workoutManager: WorkoutManager
    @ObservedObject var bluetoothManager: BluetoothManager
    
    @State private var showSkipConfirmation = false
    @State private var showEndConfirmation = false
    @State private var hasShownCompletionHint = false
    @State private var hasShownCountdownWarning = false
    
    private var workout: PlannedWorkout? {
        workoutManager.plannedWorkout
    }
    
    private var intervals: [PlannedWorkout.Interval]? {
        workout?.intervals
    }
    
    private var currentInterval: PlannedWorkout.Interval? {
        guard let intervals = intervals,
              let progress = workoutManager.intervalProgress,
              progress.currentIntervalIndex < intervals.count else {
            return nil
        }
        return intervals[progress.currentIntervalIndex]
    }
    
    private var nextInterval: PlannedWorkout.Interval? {
        guard let intervals = intervals,
              let progress = workoutManager.intervalProgress,
              progress.currentIntervalIndex + 1 < intervals.count else {
            return nil
        }
        return intervals[progress.currentIntervalIndex + 1]
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let interval = currentInterval, let progress = workoutManager.intervalProgress {
                    // Section 1: Current Interval Header
                    intervalHeader(interval: interval, progress: progress)
                    
                    // Section 2: Target Display
                    targetDisplay(interval: interval)
                    
                    // Section 3: Progress Indicators
                    progressIndicators(interval: interval, progress: progress)
                    
                    // Section 4: Live Metrics
                    liveMetrics()
                    
                    // Section 5: Controls
                    controls(interval: interval, progress: progress)
                }
            }
            .padding()
        }
        .alert("Skip this interval?", isPresented: $showSkipConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Skip", role: .destructive) {
                workoutManager.skipCurrentInterval()
            }
        }
        .alert("End workout early?", isPresented: $showEndConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("End Workout", role: .destructive) {
                workoutManager.stopWorkout()
            }
        }
        .onChange(of: workoutManager.intervalProgress) { newProgress in
            if let progress = newProgress, let interval = currentInterval {
                checkForHints(progress: progress, interval: interval)
            }
        }
    }
    
    // MARK: - Section 1: Interval Header
    
    private func intervalHeader(interval: PlannedWorkout.Interval, progress: IntervalProgress) -> some View {
        VStack(spacing: 8) {
            // Interval type badge
            Text(interval.type.displayName.uppercased())
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(colorForIntervalType(interval.type))
                .cornerRadius(8)
            
            // Interval progress
            if let intervals = intervals {
                Text("Interval \(progress.currentIntervalIndex + 1) of \(intervals.count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
    
    // MARK: - Section 2: Target Display
    
    private func targetDisplay(interval: PlannedWorkout.Interval) -> some View {
        VStack(spacing: 12) {
            // Target pace (hero)
            if let targetPace = interval.targetPaceSecondsPerKm {
                VStack(spacing: 4) {
                    Text("TARGET PACE")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(targetPace.toPaceString())
                        .font(.system(size: 72, weight: .bold))
                        .minimumScaleFactor(0.5)
                }
            }
            
            // Current pace with intelligent color feedback
            if !workoutManager.isPaused {
                paceComparison(interval: interval, targetPace: interval.targetPaceSecondsPerKm)
            } else {
                Text("PAUSED")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
    
    private func paceComparison(interval: PlannedWorkout.Interval, targetPace: Double?) -> some View {
        let currentPace = workoutManager.liveStats.currentPaceSecPerKm
        let tolerance = paceToleranceForInterval(interval)
        
        let difference = abs(currentPace - (targetPace ?? 0))
        let color: Color
        
        if difference <= tolerance.green {
            color = .green
        } else if difference <= tolerance.yellow {
            color = .yellow
        } else {
            color = .red
        }
        
        return VStack(spacing: 4) {
            Text("CURRENT PACE")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(currentPace.toPaceString())
                .font(.system(size: 48, weight: .medium))
                .foregroundColor(color)
        }
    }
    
    // MARK: - Section 3: Progress Indicators
    
    private func progressIndicators(interval: PlannedWorkout.Interval, progress: IntervalProgress) -> some View {
        VStack(spacing: 16) {
            // Distance/Time progress
            if let targetDistance = interval.distanceKm {
                let completed = progress.distanceInCurrentInterval / 1000.0
                let progressPercent = progress.progressPercentage(for: interval)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(String(format: "%.2f / %.1f km", completed, targetDistance))
                            .font(.headline)
                        Spacer()
                        Text(String(format: "%.0f%%", progressPercent * 100))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    ProgressView(value: progressPercent)
                        .tint(.stridePrimary)
                }
            } else if let targetDuration = interval.durationSeconds {
                let elapsed = progress.timeInCurrentInterval
                let progressPercent = progress.progressPercentage(for: interval)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(Int(elapsed))s / \(Int(targetDuration))s")
                            .font(.headline)
                        Spacer()
                        Text(String(format: "%.0f%%", progressPercent * 100))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    ProgressView(value: progressPercent)
                        .tint(.stridePrimary)
                }
            }
            
            // Interval description
            Text(interval.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            // "What's Next" preview
            if let next = nextInterval {
                HStack {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundColor(.stridePrimary)
                    Text("Next: \(formatNextInterval(next))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            
            // Completion hint
            if progress.isIntervalTargetReached(interval: interval) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.stridePrimary)
                    Text("Interval complete — tap Next when ready")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .padding()
                .background(Color.stridePrimary.opacity(0.1))
                .cornerRadius(12)
            }
            
            // Countdown warning
            if progress.isNearCompletion(for: interval) && !progress.isIntervalTargetReached(interval: interval) {
                if let remaining = progress.remainingDistance(for: interval), remaining > 0 {
                    Text("\(Int(remaining))m remaining")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                } else if let remainingTime = progress.remainingTime(for: interval), remainingTime > 0 {
                    Text("\(Int(remainingTime))s remaining")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }
            }
            
            // Long pause message
            if workoutManager.isPaused, let pauseDuration = progress.pausedDuration(), pauseDuration > 180 {
                Text("Resume when ready — interval progress unchanged")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            }
            
            // Overall progress
            if let intervals = intervals {
                Text("\(progress.currentIntervalIndex + 1) / \(intervals.count) intervals complete")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
    
    // MARK: - Section 4: Live Metrics
    
    private func liveMetrics() -> some View {
        VStack(spacing: 12) {
            Text("LIVE METRICS")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 20) {
                metricItem(label: "Distance", value: String(format: "%.2f km", workoutManager.liveStats.totalDistanceMeters / 1000.0))
                metricItem(label: "Time", value: workoutManager.liveStats.durationSeconds.toTimeString())
                if let hr = workoutManager.liveStats.heartRate {
                    metricItem(label: "HR", value: "\(hr) bpm")
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
    
    private func metricItem(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Section 5: Controls
    
    private func controls(interval: PlannedWorkout.Interval, progress: IntervalProgress) -> some View {
        VStack(spacing: 12) {
            // Next Interval button
            Button(action: {
                workoutManager.advanceToNextInterval()
                hasShownCompletionHint = false
                hasShownCountdownWarning = false
            }) {
                HStack {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("Next Interval")
                        .fontWeight(.bold)
                }
                .font(.title3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(progress.isIntervalTargetReached(interval: interval) ? Color.stridePrimary : Color.green)
                .foregroundColor(.strideBlack)
                .cornerRadius(12)
            }
            
            HStack(spacing: 12) {
                // Pause/Resume button
                Button(action: {
                    if workoutManager.isPaused {
                        workoutManager.resumeWorkout()
                    } else {
                        workoutManager.pauseWorkout()
                    }
                }) {
                    HStack {
                        Image(systemName: workoutManager.isPaused ? "play.fill" : "pause.fill")
                        Text(workoutManager.isPaused ? "Resume" : "Pause")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray4))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                
                // Skip button
                Button(action: {
                    showSkipConfirmation = true
                }) {
                    HStack {
                        Image(systemName: "forward.fill")
                        Text("Skip")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray4))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            }
            
            // End Workout button
            Button(action: {
                showEndConfirmation = true
            }) {
                Text("End Workout")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red)
                    .cornerRadius(12)
            }
        }
        .padding()
    }
    
    // MARK: - Helpers
    
    private func checkForHints(progress: IntervalProgress, interval: PlannedWorkout.Interval) {
        // Completion hint with haptic
        if progress.isIntervalTargetReached(interval: interval) && !hasShownCompletionHint {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            hasShownCompletionHint = true
        }
        
        // Countdown warning with haptic
        if progress.isNearCompletion(for: interval) && !hasShownCountdownWarning {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            hasShownCountdownWarning = true
        }
        
        // Reset flags when new interval starts
        if progress.intervalStatus == .notStarted {
            hasShownCompletionHint = false
            hasShownCountdownWarning = false
        }
    }
    
    private func formatNextInterval(_ interval: PlannedWorkout.Interval) -> String {
        var parts: [String] = []
        
        if let distance = interval.distanceKm {
            parts.append(String(format: "%.1f km", distance))
        } else if let duration = interval.durationSeconds {
            parts.append("\(Int(duration / 60))min")
        }
        
        parts.append(interval.type.displayName)
        
        if let pace = interval.targetPaceSecondsPerKm {
            parts.append("@ \(pace.toPaceString())")
        }
        
        return parts.joined(separator: " ")
    }
    
    private struct PaceTolerance {
        let green: Double
        let yellow: Double
    }
    
    private func paceToleranceForInterval(_ interval: PlannedWorkout.Interval) -> PaceTolerance {
        switch interval.type {
        case .warmup, .recovery, .cooldown:
            // Wide tolerance for easy running
            return PaceTolerance(green: 15, yellow: 25)
        case .work:
            // Tight tolerance for work intervals
            return PaceTolerance(green: 5, yellow: 10)
        }
    }
    
    private func colorForIntervalType(_ type: PlannedWorkout.Interval.IntervalType) -> Color {
        switch type {
        case .warmup: return .blue
        case .work: return .red
        case .recovery: return .green
        case .cooldown: return .cyan
        }
    }
}
