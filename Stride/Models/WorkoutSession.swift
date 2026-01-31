import Foundation

/// Status of an interval completion
enum IntervalCompletionState: String, Codable {
    case completed  // Finished normally
    case skipped    // User skipped intentionally
    case partial    // Interval started but workout ended early
}

/// Tracks completion of a single interval in a guided workout
struct IntervalCompletion: Codable, Identifiable {
    let id: UUID
    let intervalId: UUID  // Reference to PlannedWorkout.Interval
    let startTime: Date
    let endTime: Date?  // nil if skipped
    let targetPaceSecondsPerKm: Double?
    let actualAvgPaceSecondsPerKm: Double?  // nil if skipped
    let distanceMeters: Double
    let status: IntervalCompletionState
    
    init(
        id: UUID = UUID(),
        intervalId: UUID,
        startTime: Date,
        endTime: Date? = nil,
        targetPaceSecondsPerKm: Double? = nil,
        actualAvgPaceSecondsPerKm: Double? = nil,
        distanceMeters: Double,
        status: IntervalCompletionState
    ) {
        self.id = id
        self.intervalId = intervalId
        self.startTime = startTime
        self.endTime = endTime
        self.targetPaceSecondsPerKm = targetPaceSecondsPerKm
        self.actualAvgPaceSecondsPerKm = actualAvgPaceSecondsPerKm
        self.distanceMeters = distanceMeters
        self.status = status
    }
}

/// Helper struct to make pause intervals codable
struct PauseInterval: Codable {
    let start: Date
    let end: Date
}

/// Complete workout session with memory-efficient sample management
struct WorkoutSession: Codable, Identifiable {
    let id: UUID
    let startTime: Date
    var endTime: Date
    
    // Memory-efficient sample storage:
    // - recentSamples: Only last ~300 samples for live chart visualization and split calculation
    // - splits: All aggregated data we need for history/analysis
    var recentSamples: [WorkoutSample] = []
    var splits: [Split]
    
    // Time tracking for disconnections/pauses
    var accumulatedActiveTime: TimeInterval = 0
    private var codablePauseIntervals: [PauseInterval] = []
    
    // User-editable fields
    var workoutTitle: String?
    var effortRating: Int? // 1-10 scale
    var notes: String?
    
    // Weekly adaptation tracking
    var fatigueLevel: Int? // 1-5 scale (1=fresh, 5=exhausted)
    var injuryFlag: Bool? // true if experiencing pain/injury
    var injuryNotes: String? // optional details about injury
    
    // Guided workout tracking
    var plannedWorkoutId: UUID? // reference to PlannedWorkout
    var intervalCompletions: [IntervalCompletion]? // track each interval
    
    // Computed property for easier access
    var pauseIntervals: [(Date, Date)] {
        get {
            codablePauseIntervals.map { ($0.start, $0.end) }
        }
        set {
            codablePauseIntervals = newValue.map { PauseInterval(start: $0.0, end: $0.1) }
        }
    }
    
    init(startTime: Date = Date()) {
        self.id = UUID()
        self.startTime = startTime
        self.endTime = startTime
        self.recentSamples = []
        self.splits = []
        self.accumulatedActiveTime = 0
        self.codablePauseIntervals = []
    }
    
    // MARK: - Computed Properties
    
    var durationSeconds: Double {
        // Use accumulated active time if available (for workouts with disconnections)
        // Otherwise fall back to simple time difference
        if accumulatedActiveTime > 0 {
            return accumulatedActiveTime
        }
        return endTime.timeIntervalSince(startTime)
    }
    
    var totalDistanceMeters: Double {
        // Use most recent sample
        return recentSamples.last?.totalDistanceMeters ?? 0
    }
    
    var totalDistanceKm: Double {
        return totalDistanceMeters / 1000.0
    }
    
    var avgSpeedMps: Double {
        guard durationSeconds > 0 else { return 0 }
        return totalDistanceMeters / durationSeconds
    }
    
    var avgPaceSecondsPerKm: Double {
        guard avgSpeedMps > 0 else { return 0 }
        return 1000.0 / avgSpeedMps
    }
    
    var fastestSplit: Split? {
        return splits.min(by: { $0.splitTimeSeconds < $1.splitTimeSeconds })
    }
    
    var slowestSplit: Split? {
        return splits.max(by: { $0.splitTimeSeconds < $1.splitTimeSeconds })
    }
    
    /// Estimated calories burned based on distance and pace
    var estimatedCalories: Int {
        // MET calculation: Calories = MET × weight(kg) × duration(hours)
        let durationHours = durationSeconds / 3600.0
        let avgPaceMinPerKm = avgPaceSecondsPerKm / 60.0
        
        // Estimate MET based on pace (faster = higher MET)
        // Pace ranges: <4 min/km = 15 MET, 4-5 = 12, 5-6 = 10, 6-7 = 8, >7 = 7
        let met: Double
        if avgPaceMinPerKm < 4.0 {
            met = 15.0
        } else if avgPaceMinPerKm < 5.0 {
            met = 12.0
        } else if avgPaceMinPerKm < 6.0 {
            met = 10.0
        } else if avgPaceMinPerKm < 7.0 {
            met = 8.0
        } else {
            met = 7.0
        }
        
        // Assume average weight of 70kg
        let weightKg = 70.0
        let calories = met * weightKg * durationHours
        
        return Int(calories)
    }
    
    // MARK: - Summary for Index
    
    struct Summary: Codable, Identifiable {
        let id: UUID
        let startTime: Date
        let durationSeconds: Double
        let totalDistanceMeters: Double
        let avgPaceSecondsPerKm: Double
        
        init(from session: WorkoutSession) {
            self.id = session.id
            self.startTime = session.startTime
            self.durationSeconds = session.durationSeconds
            self.totalDistanceMeters = session.totalDistanceMeters
            self.avgPaceSecondsPerKm = session.avgPaceSecondsPerKm
        }
    }
    
    var summary: Summary {
        return Summary(from: self)
    }
}

