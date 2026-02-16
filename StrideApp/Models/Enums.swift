import Foundation

// MARK: - Race Type
enum RaceType: String, Codable, CaseIterable, Identifiable {
    case fiveK = "5K"
    case tenK = "10K"
    case halfMarathon = "Half Marathon"
    case marathon = "Marathon"
    case custom = "Custom"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var shortName: String {
        switch self {
        case .fiveK: return "5K"
        case .tenK: return "10K"
        case .halfMarathon: return "Half"
        case .marathon: return "Full"
        case .custom: return "Custom"
        }
    }

    /// Distance in km for standard types, nil for custom (distance lives in OnboardingData/TrainingPlan)
    var distanceKm: Double? {
        switch self {
        case .fiveK: return 5.0
        case .tenK: return 10.0
        case .halfMarathon: return 21.1
        case .marathon: return 42.195
        case .custom: return nil
        }
    }
}

// MARK: - Terrain Type
enum TerrainType: String, Codable, CaseIterable, Identifiable {
    case road = "road"
    case trail = "trail"
    case mountain = "mountain"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .road: return "Road"
        case .trail: return "Trail"
        case .mountain: return "Mountain"
        }
    }
}

// MARK: - Fitness Level
enum FitnessLevel: String, Codable, CaseIterable, Identifiable {
    case beginner = "beginner"
    case intermediate = "intermediate"
    case advanced = "advanced"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        }
    }
    
    var description: String {
        switch self {
        case .beginner: return "New to structured training"
        case .intermediate: return "Consistent runner, some race experience"
        case .advanced: return "Experienced racer, high weekly volume"
        }
    }
}

// MARK: - Day of Week
enum DayOfWeek: String, Codable, CaseIterable, Identifiable {
    case monday = "Monday"
    case tuesday = "Tuesday"
    case wednesday = "Wednesday"
    case thursday = "Thursday"
    case friday = "Friday"
    case saturday = "Saturday"
    case sunday = "Sunday"
    
    var id: String { rawValue }
    
    var shortName: String {
        switch self {
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        case .sunday: return "Sun"
        }
    }
    
    var initial: String {
        String(shortName.prefix(1))
    }
}

// MARK: - Plan Mode
enum PlanMode: String, Codable {
    case aggressive = "aggressive"
    case recommended = "recommended"
}

// MARK: - Workout Type
enum WorkoutType: String, Codable, CaseIterable, Identifiable {
    case easyRun = "easy_run"
    case longRun = "long_run"
    case tempoRun = "tempo_run"
    case intervals = "intervals"
    case hillRepeats = "hill_repeats"
    case recovery = "recovery"
    case rest = "rest"
    case crossTraining = "cross_training"
    case gym = "gym"
    case race = "race"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .easyRun: return "Easy Run"
        case .longRun: return "Long Run"
        case .tempoRun: return "Tempo Run"
        case .intervals: return "Intervals"
        case .hillRepeats: return "Hill Repeats"
        case .recovery: return "Recovery"
        case .rest: return "Rest Day"
        case .crossTraining: return "Cross Training"
        case .gym: return "Strength Training"
        case .race: return "Race Day"
        }
    }
    
    var icon: String {
        switch self {
        case .easyRun: return "figure.run"
        case .longRun: return "figure.run.circle"
        case .tempoRun: return "gauge.with.dots.needle.67percent"
        case .intervals: return "timer"
        case .hillRepeats: return "mountain.2"
        case .recovery: return "heart.circle"
        case .rest: return "bed.double"
        case .crossTraining: return "figure.mixed.cardio"
        case .gym: return "dumbbell"
        case .race: return "flag.checkered"
        }
    }
    
    var color: String {
        switch self {
        case .easyRun: return "workoutEasy"
        case .longRun: return "workoutLong"
        case .tempoRun: return "workoutTempo"
        case .intervals, .hillRepeats: return "workoutInterval"
        case .recovery: return "workoutRecovery"
        case .rest: return "workoutRest"
        case .crossTraining, .gym: return "workoutGym"
        case .race: return "workoutRace"
        }
    }
}

// MARK: - Archive Reason
enum ArchiveReason: String, Codable {
    case completed = "completed"
    case replaced = "replaced"
    case abandoned = "abandoned"

    var displayName: String {
        switch self {
        case .completed: return "Completed"
        case .replaced: return "Replaced"
        case .abandoned: return "Abandoned"
        }
    }
}

// MARK: - Conflict Type
enum ConflictType: String, Codable {
    case goalVsFitness = "goal_vs_fitness"
    case injuryRisk = "injury_risk"
    case timelinePressure = "timeline_pressure"
    case volumeInsufficient = "volume_insufficient"
    case benchmarksUnreachable = "benchmarks_unreachable"
}

// MARK: - Risk Level
enum RiskLevel: String, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    
    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
    
    var icon: String {
        switch self {
        case .low: return "checkmark.circle.fill"
        case .medium: return "exclamationmark.triangle.fill"
        case .high: return "xmark.circle.fill"
        }
    }
}
