import Foundation

/// Status of an individual interval during a guided workout
enum IntervalStatus: Codable, Equatable {
    case notStarted
    case inProgress
    case completed
    case skipped
}

/// Immutable state tracker for interval progress using reducer pattern
/// Prevents state bugs during app backgrounding, Bluetooth dropouts, and view re-renders
struct IntervalProgress: Codable, Equatable {
    // Current state
    let currentIntervalIndex: Int
    let intervalStatus: IntervalStatus
    
    // Tracking data for current interval
    let intervalStartDistance: Double  // meters
    let intervalStartTime: Date
    
    // Pause tracking
    let isPaused: Bool
    let pauseStartTime: Date?
    let totalPausedDuration: TimeInterval
    
    // Completion tracking for all intervals
    let completedIntervals: [UUID: IntervalStatus]  // intervalId -> status
    
    // Current progress (set by updateProgress)
    let currentDistance: Double  // total meters
    let currentTime: Date
    
    // MARK: - Computed Properties
    
    /// Distance covered in current interval (meters)
    var distanceInCurrentInterval: Double {
        return max(0, currentDistance - intervalStartDistance)
    }
    
    /// Time elapsed in current interval (excluding pauses)
    var timeInCurrentInterval: TimeInterval {
        let elapsed = currentTime.timeIntervalSince(intervalStartTime)
        return max(0, elapsed - totalPausedDuration)
    }
    
    // MARK: - Initialization
    
    /// Create initial state when starting a guided workout
    static func initial(startDistance: Double, startTime: Date) -> IntervalProgress {
        return IntervalProgress(
            currentIntervalIndex: 0,
            intervalStatus: .notStarted,
            intervalStartDistance: startDistance,
            intervalStartTime: startTime,
            isPaused: false,
            pauseStartTime: nil,
            totalPausedDuration: 0,
            completedIntervals: [:],
            currentDistance: startDistance,
            currentTime: startTime
        )
    }
    
    // MARK: - State Transitions
    
    /// Start tracking an interval
    func startInterval(index: Int, startDistance: Double, startTime: Date) -> IntervalProgress {
        return IntervalProgress(
            currentIntervalIndex: index,
            intervalStatus: .inProgress,
            intervalStartDistance: startDistance,
            intervalStartTime: startTime,
            isPaused: isPaused,
            pauseStartTime: pauseStartTime,
            totalPausedDuration: 0,  // Reset pause duration for new interval
            completedIntervals: completedIntervals,
            currentDistance: startDistance,
            currentTime: startTime
        )
    }
    
    /// Update progress with new distance and time data
    func updateProgress(currentDistance: Double, currentTime: Date) -> IntervalProgress {
        return IntervalProgress(
            currentIntervalIndex: currentIntervalIndex,
            intervalStatus: intervalStatus,
            intervalStartDistance: intervalStartDistance,
            intervalStartTime: intervalStartTime,
            isPaused: isPaused,
            pauseStartTime: pauseStartTime,
            totalPausedDuration: totalPausedDuration,
            completedIntervals: completedIntervals,
            currentDistance: currentDistance,
            currentTime: currentTime
        )
    }
    
    /// Advance to next interval
    func advanceToNext(intervalId: UUID, nextIndex: Int, currentDistance: Double, currentTime: Date) -> IntervalProgress {
        var updatedCompletions = completedIntervals
        updatedCompletions[intervalId] = .completed
        
        return IntervalProgress(
            currentIntervalIndex: nextIndex,
            intervalStatus: .notStarted,
            intervalStartDistance: currentDistance,
            intervalStartTime: currentTime,
            isPaused: isPaused,
            pauseStartTime: pauseStartTime,
            totalPausedDuration: 0,  // Reset for new interval
            completedIntervals: updatedCompletions,
            currentDistance: currentDistance,
            currentTime: currentTime
        )
    }
    
    /// Skip the current interval
    func skipInterval(intervalId: UUID, nextIndex: Int, currentDistance: Double, currentTime: Date) -> IntervalProgress {
        var updatedCompletions = completedIntervals
        updatedCompletions[intervalId] = .skipped
        
        return IntervalProgress(
            currentIntervalIndex: nextIndex,
            intervalStatus: .notStarted,
            intervalStartDistance: currentDistance,
            intervalStartTime: currentTime,
            isPaused: isPaused,
            pauseStartTime: pauseStartTime,
            totalPausedDuration: 0,  // Reset for new interval
            completedIntervals: updatedCompletions,
            currentDistance: currentDistance,
            currentTime: currentTime
        )
    }
    
    /// Pause interval progress
    func pauseProgress(pauseTime: Date) -> IntervalProgress {
        return IntervalProgress(
            currentIntervalIndex: currentIntervalIndex,
            intervalStatus: intervalStatus,
            intervalStartDistance: intervalStartDistance,
            intervalStartTime: intervalStartTime,
            isPaused: true,
            pauseStartTime: pauseTime,
            totalPausedDuration: totalPausedDuration,
            completedIntervals: completedIntervals,
            currentDistance: currentDistance,
            currentTime: currentTime
        )
    }
    
    /// Resume interval progress
    func resumeProgress(resumeTime: Date) -> IntervalProgress {
        // Calculate additional paused duration
        let additionalPause = pauseStartTime.map { resumeTime.timeIntervalSince($0) } ?? 0
        
        return IntervalProgress(
            currentIntervalIndex: currentIntervalIndex,
            intervalStatus: intervalStatus,
            intervalStartDistance: intervalStartDistance,
            intervalStartTime: intervalStartTime,
            isPaused: false,
            pauseStartTime: nil,
            totalPausedDuration: totalPausedDuration + additionalPause,
            completedIntervals: completedIntervals,
            currentDistance: currentDistance,
            currentTime: resumeTime
        )
    }
    
    // MARK: - Query Methods
    
    /// Check if current interval has reached its target
    func isIntervalTargetReached(interval: PlannedWorkout.Interval) -> Bool {
        // Check distance-based completion
        if let targetDistance = interval.distanceKm {
            let targetMeters = targetDistance * 1000
            return distanceInCurrentInterval >= targetMeters
        }
        
        // Check time-based completion
        if let targetDuration = interval.durationSeconds {
            return timeInCurrentInterval >= targetDuration
        }
        
        return false
    }
    
    /// Get progress percentage for current interval (0.0 to 1.0)
    func progressPercentage(for interval: PlannedWorkout.Interval) -> Double {
        // Distance-based progress
        if let targetDistance = interval.distanceKm {
            let targetMeters = targetDistance * 1000
            guard targetMeters > 0 else { return 0 }
            return min(1.0, distanceInCurrentInterval / targetMeters)
        }
        
        // Time-based progress
        if let targetDuration = interval.durationSeconds {
            guard targetDuration > 0 else { return 0 }
            return min(1.0, timeInCurrentInterval / targetDuration)
        }
        
        return 0
    }
    
    /// Check if we're near the end of the interval (80-90% for countdown warning)
    func isNearCompletion(for interval: PlannedWorkout.Interval) -> Bool {
        let progress = progressPercentage(for: interval)
        return progress >= 0.8 && progress < 1.0
    }
    
    /// Get remaining distance in current interval (meters)
    func remainingDistance(for interval: PlannedWorkout.Interval) -> Double? {
        guard let targetDistance = interval.distanceKm else { return nil }
        let targetMeters = targetDistance * 1000
        return max(0, targetMeters - distanceInCurrentInterval)
    }
    
    /// Get remaining time in current interval (seconds)
    func remainingTime(for interval: PlannedWorkout.Interval) -> TimeInterval? {
        guard let targetDuration = interval.durationSeconds else { return nil }
        return max(0, targetDuration - timeInCurrentInterval)
    }
    
    /// Get how long we've been paused (if currently paused)
    func pausedDuration() -> TimeInterval? {
        guard isPaused, let pauseStart = pauseStartTime else { return nil }
        return Date().timeIntervalSince(pauseStart)
    }
}
