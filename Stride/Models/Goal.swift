import Foundation

/// Represents a training goal with target event date and optional time
struct Goal: Codable, Identifiable {
    let id: UUID
    let type: GoalType
    let targetTime: TimeInterval?  // in seconds (nil for completion goals)
    let eventDate: Date
    let createdAt: Date
    var isActive: Bool
    
    // User-facing fields (added now for future use)
    var title: String?       // e.g. "BMO Half Marathon"
    var notes: String?       // user context, e.g. "Aim: sub 1:35"
    
    // Distance fields (ALWAYS required - both race and time goals need distance)
    var raceDistance: RaceDistance?
    var customDistanceKm: Double?
    
    // Baseline assessment fields
    var baselineStatus: BaselineStatus = .unknown
    var baselineAssessmentId: UUID?      // Reference to baseline assessment
    var trainingPaces: TrainingPaces?    // Cached training paces from assessment
    var estimatedVDOT: Double?           // Cached VDOT value
    
    enum GoalType: String, Codable {
        case race           // Standard race distance with time goal
        case customTime     // Custom distance with time goal
        case completion     // Distance goal without time constraint
        
        var requiresTargetTime: Bool {
            switch self {
            case .race, .customTime:
                return true
            case .completion:
                return false
            }
        }
        
        var displayName: String {
            switch self {
            case .race:
                return "Race Goal"
            case .customTime:
                return "Custom Time Goal"
            case .completion:
                return "Completion Goal"
            }
        }
    }
    
    enum BaselineStatus: String, Codable {
        case unknown        // Not yet assessed
        case sufficient     // Ready to train
        case required       // Assessment needed
    }
    
    enum RaceDistance: String, Codable, CaseIterable {
        case fiveK = "5K"
        case tenK = "10K"
        case halfMarathon = "Half Marathon"
        case marathon = "Marathon"
        case custom = "Custom"
        
        var kilometers: Double? {
            switch self {
            case .fiveK: return 5.0
            case .tenK: return 10.0
            case .halfMarathon: return 21.0975
            case .marathon: return 42.195
            case .custom: return nil
            }
        }
    }
    
    // MARK: - Initializer
    
    init(
        id: UUID = UUID(),
        type: GoalType,
        targetTime: TimeInterval? = nil,
        eventDate: Date,
        createdAt: Date = Date(),
        isActive: Bool = true,
        title: String? = nil,
        notes: String? = nil,
        raceDistance: RaceDistance? = nil,
        customDistanceKm: Double? = nil,
        baselineStatus: BaselineStatus = .unknown,
        baselineAssessmentId: UUID? = nil,
        trainingPaces: TrainingPaces? = nil,
        estimatedVDOT: Double? = nil
    ) {
        self.id = id
        self.type = type
        self.targetTime = targetTime
        self.eventDate = eventDate
        self.createdAt = createdAt
        self.isActive = isActive
        self.title = title
        self.notes = notes
        self.raceDistance = raceDistance
        self.customDistanceKm = customDistanceKm
        self.baselineStatus = baselineStatus
        self.baselineAssessmentId = baselineAssessmentId
        self.trainingPaces = trainingPaces
        self.estimatedVDOT = estimatedVDOT
    }
    
    // MARK: - Computed Properties
    
    /// Days remaining until event (calendar-safe)
    var daysRemaining: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: eventDate)
        return max(0, components.day ?? 0)
    }
    
    /// Weeks remaining until event (calendar-safe)
    var weeksRemaining: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.weekOfYear], from: Date(), to: eventDate)
        return max(0, components.weekOfYear ?? 0)
    }
    
    /// Recommended training duration range based on race distance
    var recommendedTrainingRange: ClosedRange<Int> {
        // Range depends on race distance
        guard let distance = distanceKm else { return 8...12 }
        
        if distance <= 5 {
            return 8...12
        } else if distance <= 10 {
            return 10...14
        } else if distance <= 21.1 {
            return 12...16
        } else {
            return 16...20  // Marathon and beyond
        }
    }
    
    /// Default training weeks (middle of recommended range)
    var defaultTrainingWeeks: Int {
        let range = recommendedTrainingRange
        return (range.lowerBound + range.upperBound) / 2
    }
    
    /// Distance in kilometers (computed from raceDistance or customDistanceKm)
    var distanceKm: Double? {
        if let raceDistance = raceDistance, raceDistance != .custom {
            return raceDistance.kilometers
        }
        return customDistanceKm
    }
    
    /// Display name for the goal (title if set, otherwise distance)
    var displayName: String {
        if let title = title, !title.isEmpty {
            return title
        }
        
        if let distance = raceDistance, distance != .custom {
            return distance.rawValue
        } else if let km = customDistanceKm {
            return String(format: "%.1f km", km)
        }
        
        return "Goal"
    }
    
    /// Formatted target time as HH:MM:SS or MM:SS (nil for completion goals)
    var formattedTargetTime: String? {
        guard let targetTime = targetTime else {
            return nil
        }
        
        let totalSeconds = Int(targetTime)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    // MARK: - Validation
    
    /// Validates the goal and returns error message if invalid
    func validate() -> String? {
        // Event date must be in the future (at least tomorrow)
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        if eventDate < tomorrow {
            return "Event date must be at least tomorrow"
        }
        
        // Target time validation - only required for time-based goals
        if type.requiresTargetTime {
            if targetTime == nil || targetTime! <= 0 {
                return "Target time must be greater than zero"
            }
        }
        
        // Distance validation based on goal type
        switch type {
        case .race:
            if raceDistance == nil {
                return "Race goal requires a distance selection"
            }
            if raceDistance == .custom && (customDistanceKm == nil || customDistanceKm! < 1 || customDistanceKm! > 1000) {
                return "Custom distance must be between 1 and 1000 km"
            }
        case .customTime:
            if customDistanceKm == nil || customDistanceKm! < 1 || customDistanceKm! > 1000 {
                return "Custom distance must be between 1 and 1000 km"
            }
        case .completion:
            // Completion goals require either a standard distance or custom distance
            if raceDistance == nil && customDistanceKm == nil {
                return "Completion goal requires a distance selection"
            }
            if raceDistance == .custom && (customDistanceKm == nil || customDistanceKm! < 1 || customDistanceKm! > 1000) {
                return "Custom distance must be between 1 and 1000 km"
            }
            if let customKm = customDistanceKm, (customKm < 1 || customKm > 1000) {
                return "Custom distance must be between 1 and 1000 km"
            }
        }
        
        return nil
    }
    
    /// Whether this goal is valid
    var isValid: Bool {
        return validate() == nil
    }
    
    // MARK: - Baseline Assessment
    
    /// Whether this goal needs a baseline assessment
    var needsBaselineAssessment: Bool {
        return baselineStatus == .required && baselineAssessmentId == nil
    }
    
    /// Whether this goal has a complete baseline assessment
    var hasBaselineAssessment: Bool {
        return baselineAssessmentId != nil && trainingPaces != nil && estimatedVDOT != nil
    }
}
