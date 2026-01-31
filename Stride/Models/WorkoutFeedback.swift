import Foundation

/// Status of overall workout completion
enum WorkoutCompletionStatus: String, Codable {
    case completedAsPlanned
    case completedModified
    case skipped
    case stoppedEarly
    
    var displayName: String {
        switch self {
        case .completedAsPlanned: return "Completed as Planned"
        case .completedModified: return "Completed (Modified)"
        case .skipped: return "Skipped"
        case .stoppedEarly: return "Stopped Early"
        }
    }
}

/// Pace adherence for run workouts
enum PaceAdherence: String, Codable {
    case onTarget      // Within ±5 sec/km
    case slightlyOff   // ±5-15 sec/km
    case offTarget     // > ±15 sec/km
    
    var displayName: String {
        switch self {
        case .onTarget: return "On Target"
        case .slightlyOff: return "Slightly Off"
        case .offTarget: return "Off Target"
        }
    }
    
    var color: String {
        switch self {
        case .onTarget: return "green"
        case .slightlyOff: return "yellow"
        case .offTarget: return "red"
        }
    }
}

/// How weights felt during gym workout
enum WeightFeel: String, Codable {
    case tooLight
    case justRight
    case tooHeavy
    
    var displayName: String {
        switch self {
        case .tooLight: return "Too Light"
        case .justRight: return "Just Right"
        case .tooHeavy: return "Too Heavy"
        }
    }
}

/// Comprehensive workout feedback model
struct WorkoutFeedback: Codable, Identifiable {
    let id: UUID
    let workoutSessionId: UUID
    let plannedWorkoutId: UUID?
    let date: Date
    
    // Performance
    let completionStatus: WorkoutCompletionStatus
    let paceAdherence: PaceAdherence? // Runs only (nil for gym)
    
    // Subjective inputs (1-10 scale for effort, 1-5 for fatigue, 0-10 for pain)
    let perceivedEffort: Int  // 1-10 (default: 5)
    let fatigueLevel: Int     // 1-5 (default: 3)
    let painLevel: Int        // 0-10 (default: 0)
    
    // Optional context
    let painAreas: [InjuryArea]? // Only required if pain >= 4
    
    // Gym-only (nil for runs)
    let weightFeel: WeightFeel?
    let formBreakdown: Bool?
    
    let notes: String? // Single notes field (labeled "Coach Notes" in UI)
    
    init(
        id: UUID = UUID(),
        workoutSessionId: UUID,
        plannedWorkoutId: UUID?,
        date: Date,
        completionStatus: WorkoutCompletionStatus,
        paceAdherence: PaceAdherence? = nil,
        perceivedEffort: Int = 5,
        fatigueLevel: Int = 3,
        painLevel: Int = 0,
        painAreas: [InjuryArea]? = nil,
        weightFeel: WeightFeel? = nil,
        formBreakdown: Bool? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.workoutSessionId = workoutSessionId
        self.plannedWorkoutId = plannedWorkoutId
        self.date = date
        self.completionStatus = completionStatus
        self.paceAdherence = paceAdherence
        self.perceivedEffort = perceivedEffort
        self.fatigueLevel = fatigueLevel
        self.painLevel = painLevel
        self.painAreas = painAreas
        self.weightFeel = weightFeel
        self.formBreakdown = formBreakdown
        self.notes = notes
    }
}

// MARK: - Helper Extensions

extension WorkoutFeedback {
    /// Pain level severity
    var painSeverity: PainSeverity {
        if painLevel == 0 { return .none }
        if painLevel <= 3 { return .mild }
        if painLevel <= 6 { return .manageable }
        return .concerning
    }
    
    enum PainSeverity {
        case none
        case mild
        case manageable
        case concerning
        
        var color: String {
            switch self {
            case .none: return "gray"
            case .mild: return "yellow"
            case .manageable: return "orange"
            case .concerning: return "red"
            }
        }
        
        var displayName: String {
            switch self {
            case .none: return "No pain"
            case .mild: return "Mild discomfort"
            case .manageable: return "Manageable pain"
            case .concerning: return "Concerning pain"
            }
        }
    }
}
