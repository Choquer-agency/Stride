import Foundation

/// Represents a planned workout in a training plan
struct PlannedWorkout: Codable, Identifiable {
    let id: UUID
    let date: Date
    let type: WorkoutType
    let title: String
    let description: String?
    var completed: Bool
    var actualWorkoutId: UUID?  // Reference to completed WorkoutSession
    
    // Workout details
    let targetDistanceKm: Double?
    let targetDurationSeconds: Double?
    let targetPaceSecondsPerKm: Double?
    let intervals: [Interval]?  // For structured workouts
    
    // Exercise program (for gym workouts)
    let exerciseProgram: [ExerciseAssignment]?
    
    // Warm-up and cooldown blocks (for all workouts)
    let warmupBlock: MovementBlock?
    let cooldownBlock: MovementBlock?
    
    enum WorkoutType: String, Codable, CaseIterable {
        case easyRun = "easy_run"
        case longRun = "long_run"
        case tempoRun = "tempo_run"
        case intervalWorkout = "interval_workout"
        case recoveryRun = "recovery_run"
        case raceSimulation = "race_simulation"
        case gym = "gym"
        case rest = "rest"
        case crossTraining = "cross_training"
        
        var displayName: String {
            switch self {
            case .easyRun: return "Easy Run"
            case .longRun: return "Long Run"
            case .tempoRun: return "Tempo Run"
            case .intervalWorkout: return "Interval Workout"
            case .recoveryRun: return "Recovery Run"
            case .raceSimulation: return "Race Simulation"
            case .gym: return "Gym/Strength"
            case .rest: return "Rest Day"
            case .crossTraining: return "Cross Training"
            }
        }
        
        var icon: String {
            switch self {
            case .easyRun, .recoveryRun: return "figure.walk"
            case .longRun: return "figure.run"
            case .tempoRun: return "speedometer"
            case .intervalWorkout: return "bolt.fill"
            case .raceSimulation: return "flag.checkered"
            case .gym: return "dumbbell.fill"
            case .rest: return "bed.double.fill"
            case .crossTraining: return "sportscourt.fill"
            }
        }
        
        var color: String {
            switch self {
            case .easyRun, .recoveryRun: return "green"
            case .longRun: return "blue"
            case .tempoRun: return "orange"
            case .intervalWorkout: return "red"
            case .raceSimulation: return "purple"
            case .gym: return "brown"
            case .rest: return "gray"
            case .crossTraining: return "cyan"
            }
        }
    }
    
    struct Interval: Codable, Identifiable {
        let id: UUID
        let order: Int
        let type: IntervalType
        let distanceKm: Double?
        let durationSeconds: Double?
        let targetPaceSecondsPerKm: Double?
        let description: String
        
        enum IntervalType: String, Codable {
            case warmup
            case work
            case recovery
            case cooldown
            
            var displayName: String {
                switch self {
                case .warmup: return "Warmup"
                case .work: return "Work"
                case .recovery: return "Recovery"
                case .cooldown: return "Cooldown"
                }
            }
        }
        
        init(
            id: UUID = UUID(),
            order: Int,
            type: IntervalType,
            distanceKm: Double? = nil,
            durationSeconds: Double? = nil,
            targetPaceSecondsPerKm: Double? = nil,
            description: String
        ) {
            self.id = id
            self.order = order
            self.type = type
            self.distanceKm = distanceKm
            self.durationSeconds = durationSeconds
            self.targetPaceSecondsPerKm = targetPaceSecondsPerKm
            self.description = description
        }
    }
    
    // MARK: - Initializer
    
    init(
        id: UUID = UUID(),
        date: Date,
        type: WorkoutType,
        title: String,
        description: String? = nil,
        completed: Bool = false,
        actualWorkoutId: UUID? = nil,
        targetDistanceKm: Double? = nil,
        targetDurationSeconds: Double? = nil,
        targetPaceSecondsPerKm: Double? = nil,
        intervals: [Interval]? = nil,
        exerciseProgram: [ExerciseAssignment]? = nil,
        warmupBlock: MovementBlock? = nil,
        cooldownBlock: MovementBlock? = nil
    ) {
        self.id = id
        self.date = date
        self.type = type
        self.title = title
        self.description = description
        self.completed = completed
        self.actualWorkoutId = actualWorkoutId
        self.targetDistanceKm = targetDistanceKm
        self.targetDurationSeconds = targetDurationSeconds
        self.targetPaceSecondsPerKm = targetPaceSecondsPerKm
        self.intervals = intervals
        self.exerciseProgram = exerciseProgram
        self.warmupBlock = warmupBlock
        self.cooldownBlock = cooldownBlock
    }
    
    // MARK: - Computed Properties
    
    /// Estimated duration in seconds
    var estimatedDurationSeconds: Double {
        if let duration = targetDurationSeconds {
            return duration
        }
        
        if let distance = targetDistanceKm, let pace = targetPaceSecondsPerKm {
            return distance * pace
        }
        
        // Calculate from intervals
        if let intervals = intervals {
            var total: Double = 0
            for interval in intervals {
                if let duration = interval.durationSeconds {
                    total += duration
                } else if let distance = interval.distanceKm, let pace = interval.targetPaceSecondsPerKm {
                    total += distance * pace
                }
            }
            return total
        }
        
        return 0
    }
    
    /// Total distance in km
    var totalDistanceKm: Double {
        if let distance = targetDistanceKm {
            return distance
        }
        
        // Calculate from intervals
        if let intervals = intervals {
            return intervals.compactMap { $0.distanceKm }.reduce(0, +)
        }
        
        return 0
    }
    
    /// Whether this workout is runnable (not rest/gym)
    var isRunWorkout: Bool {
        switch type {
        case .rest, .gym, .crossTraining:
            return false
        default:
            return true
        }
    }
    
    /// Short summary for display
    var summary: String {
        if type == .rest {
            return "Rest & Recovery"
        }
        
        if type == .gym {
            return "Strength Training"
        }
        
        if let distance = targetDistanceKm {
            return String(format: "%.1f km", distance)
        }
        
        if let duration = targetDurationSeconds {
            let minutes = Int(duration / 60)
            return "\(minutes) min"
        }
        
        return type.displayName
    }
    
    /// Whether this workout has a structured exercise program
    var hasExerciseProgram: Bool {
        return exerciseProgram != nil && !(exerciseProgram?.isEmpty ?? true)
    }
}

// MARK: - Movement Block Structures

/// A single movement/exercise in a warmup or cooldown block
struct MovementBlockItem: Codable, Identifiable {
    let id: UUID
    let exerciseSlug: String
    let reps: Int?           // e.g., 10 reps per side
    let durationSeconds: Int? // e.g., 30 seconds per side
    
    init(
        id: UUID = UUID(),
        exerciseSlug: String,
        reps: Int? = nil,
        durationSeconds: Int? = nil
    ) {
        self.id = id
        self.exerciseSlug = exerciseSlug
        self.reps = reps
        self.durationSeconds = durationSeconds
    }
    
    var displayString: String {
        if let reps = reps {
            return "\(reps) reps"
        } else if let duration = durationSeconds {
            return "\(duration)s"
        } else {
            return "As prescribed"
        }
    }
}

/// A collection of movements for warmup or cooldown
struct MovementBlock: Codable {
    let items: [MovementBlockItem]
    let context: String // "Pre-workout activation" or "Post-run recovery"
    
    init(items: [MovementBlockItem], context: String) {
        self.items = items
        self.context = context
    }
    
    /// Estimated duration in seconds
    var estimatedDurationSeconds: Int {
        return items.compactMap { $0.durationSeconds }.reduce(0, +) + (items.count * 5) // Add 5s transition per item
    }
}
