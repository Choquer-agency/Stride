import Foundation

// MARK: - Supporting Enums

/// Category of exercise
enum ExerciseCategory: String, Codable, CaseIterable {
    case strength
    case stability
    case mobility
    case plyometrics
    case prehab
    
    var displayName: String {
        switch self {
        case .strength: return "Strength"
        case .stability: return "Stability"
        case .mobility: return "Mobility"
        case .plyometrics: return "Plyometrics"
        case .prehab: return "Prehab"
        }
    }
}

/// Major muscle groups for runners
enum MuscleGroup: String, Codable, CaseIterable {
    case glutes
    case hamstrings
    case quads
    case calves
    case core
    case hips
    case shin
    
    var displayName: String {
        switch self {
        case .glutes: return "Glutes"
        case .hamstrings: return "Hamstrings"
        case .quads: return "Quadriceps"
        case .calves: return "Calves"
        case .core: return "Core"
        case .hips: return "Hips"
        case .shin: return "Shins"
        }
    }
}

/// How this exercise benefits runners
enum RunnerBenefit: String, Codable {
    case injuryPrevention
    case powerDevelopment
    case mobility
    case stability
    
    var displayName: String {
        switch self {
        case .injuryPrevention: return "Injury Prevention"
        case .powerDevelopment: return "Power Development"
        case .mobility: return "Mobility"
        case .stability: return "Stability"
        }
    }
}

/// Goal types that benefit from this exercise
enum ExerciseGoalType: String, Codable {
    case fiveK = "5K"
    case tenK = "10K"
    case halfMarathon = "Half Marathon"
    case marathon = "Marathon"
    case general = "General"
    
    var displayName: String {
        return self.rawValue
    }
}

/// Injury areas this exercise helps prevent
enum InjuryArea: String, Codable, CaseIterable {
    case knee
    case achilles
    case hamstring
    case hip
    case calf
    case shin
    case ankle
    case groin
    case foot
    case arch
    case quadriceps
    case lowerBack
    case other
    
    var displayName: String {
        switch self {
        case .knee: return "Knee"
        case .achilles: return "Achilles"
        case .hamstring: return "Hamstring"
        case .hip: return "Hip"
        case .calf: return "Calf"
        case .shin: return "Shin"
        case .ankle: return "Ankle"
        case .groin: return "Groin"
        case .foot: return "Foot"
        case .arch: return "Arch"
        case .quadriceps: return "Quadriceps"
        case .lowerBack: return "Lower Back"
        case .other: return "Other"
        }
    }
}

/// How load/weight should be specified
enum LoadType: String, Codable {
    case bodyweight
    case percentageBodyweight
    case rpe
    case fixedRecommendation
    
    var displayName: String {
        switch self {
        case .bodyweight: return "Bodyweight"
        case .percentageBodyweight: return "% Bodyweight"
        case .rpe: return "RPE-Based"
        case .fixedRecommendation: return "Fixed Weight"
        }
    }
}

/// Equipment required for exercise
enum GymEquipment: String, Codable, CaseIterable {
    case barbell
    case dumbbells
    case kettlebell
    case resistanceBands
    case squatRack
    case bench
    case cableMachine
    case medicineBall
    case none
    
    // Bars & Racks
    case pullUpBar
    case dipStation
    case smithMachine
    case weightPlates
    
    // Functional Training
    case trxBands
    case stabilityBall
    case foamRoller
    case yogaMat
    case wallBall
    
    // Cardio/Conditioning
    case plyoBox
    case agilityCone
    case jumpRope
    case sled
    
    // Advanced Machines
    case legPressMachine
    case hamstringCurlMachine
    case legExtensionMachine
    case rowingMachine
    
    // Specialized
    case ghdMachine
    case landmineAttachment
    case suspensionTrainer
    
    var displayName: String {
        switch self {
        case .barbell: return "Barbell"
        case .dumbbells: return "Dumbbells"
        case .kettlebell: return "Kettlebell"
        case .resistanceBands: return "Resistance Bands"
        case .squatRack: return "Squat Rack"
        case .bench: return "Bench"
        case .cableMachine: return "Cable Machine"
        case .medicineBall: return "Medicine Ball"
        case .none: return "No Equipment"
        case .pullUpBar: return "Pull-up Bar"
        case .dipStation: return "Dip Station"
        case .smithMachine: return "Smith Machine"
        case .weightPlates: return "Weight Plates"
        case .trxBands: return "TRX Bands"
        case .stabilityBall: return "Stability Ball"
        case .foamRoller: return "Foam Roller"
        case .yogaMat: return "Yoga Mat"
        case .wallBall: return "Wall Ball"
        case .plyoBox: return "Plyometric Box"
        case .agilityCone: return "Agility Cones"
        case .jumpRope: return "Jump Rope"
        case .sled: return "Sled"
        case .legPressMachine: return "Leg Press Machine"
        case .hamstringCurlMachine: return "Hamstring Curl Machine"
        case .legExtensionMachine: return "Leg Extension Machine"
        case .rowingMachine: return "Rowing Machine"
        case .ghdMachine: return "GHD Machine"
        case .landmineAttachment: return "Landmine Attachment"
        case .suspensionTrainer: return "Suspension Trainer"
        }
    }
    
    var icon: String {
        switch self {
        case .barbell: return "figure.strengthtraining.traditional"
        case .dumbbells: return "dumbbell.fill"
        case .kettlebell: return "figure.cooldown"
        case .resistanceBands: return "line.3.horizontal.decrease.circle"
        case .squatRack: return "square.stack.3d.up"
        case .bench: return "bed.double.fill"
        case .cableMachine: return "cable.connector"
        case .medicineBall: return "soccerball"
        case .none: return "person.fill"
        case .pullUpBar: return "figure.pull"
        case .dipStation: return "figure.strengthtraining.functional"
        case .smithMachine: return "square.stack.3d.up.fill"
        case .weightPlates: return "circle.fill"
        case .trxBands: return "figure.flexibility"
        case .stabilityBall: return "circle.circle.fill"
        case .foamRoller: return "cylinder.fill"
        case .yogaMat: return "rectangle.fill"
        case .wallBall: return "soccerball.fill"
        case .plyoBox: return "square.fill"
        case .agilityCone: return "triangle.fill"
        case .jumpRope: return "figure.jumprope"
        case .sled: return "figure.run"
        case .legPressMachine: return "figure.strengthtraining.traditional"
        case .hamstringCurlMachine: return "figure.strengthtraining.traditional"
        case .legExtensionMachine: return "figure.strengthtraining.traditional"
        case .rowingMachine: return "figure.rowing"
        case .ghdMachine: return "figure.strengthtraining.traditional"
        case .landmineAttachment: return "figure.strengthtraining.traditional"
        case .suspensionTrainer: return "figure.flexibility"
        }
    }
}

/// Movement pattern for intelligent alternative selection
enum MovementPattern: String, Codable {
    case squat
    case hinge
    case lunge
    case calf
    case core
    case plyo
    case mobility
    case prehab
    case stability
    
    var displayName: String {
        switch self {
        case .squat: return "Squat"
        case .hinge: return "Hinge"
        case .lunge: return "Lunge"
        case .calf: return "Calf"
        case .core: return "Core"
        case .plyo: return "Plyometric"
        case .mobility: return "Mobility"
        case .prehab: return "Prehab"
        case .stability: return "Stability"
        }
    }
}

// MARK: - Exercise Model

/// A single exercise in the runner-focused library
struct Exercise: Codable, Identifiable {
    let id: UUID
    let slug: String  // Stable identifier like "bulgarian_split_squat"
    let name: String
    let category: ExerciseCategory
    let primaryMuscles: [MuscleGroup]
    let secondaryMuscles: [MuscleGroup]
    
    // Runner relevance
    let runnerBenefit: RunnerBenefit
    let supportsGoals: [ExerciseGoalType]
    let injuryPreventionTags: [InjuryArea]
    
    // Execution defaults
    let defaultSets: Int
    let defaultReps: ClosedRange<Int>?  // e.g., 8...12
    let defaultDurationSeconds: Int?    // For time-based exercises
    let defaultRestSeconds: Int
    let loadType: LoadType
    let loadGuidance: String
    
    // Content
    let imageName: String  // Future: SF Symbol or asset name
    let whyItHelpsRunners: String
    let commonMistakes: [String]  // Can be empty
    let coachingCues: [String]    // Can be empty
    
    // Equipment
    let requiredEquipment: [GymEquipment]
    let alternativeExercises: [String]  // Slugs of alternative exercises
    
    // Safety and alternatives
    let movementPattern: MovementPattern
    let avoidIf: [InjuryArea]  // Contraindications
    
    // MARK: - Initializer
    
    init(
        slug: String,
        name: String,
        category: ExerciseCategory,
        primaryMuscles: [MuscleGroup],
        secondaryMuscles: [MuscleGroup] = [],
        runnerBenefit: RunnerBenefit,
        supportsGoals: [ExerciseGoalType],
        injuryPreventionTags: [InjuryArea] = [],
        defaultSets: Int,
        defaultReps: ClosedRange<Int>? = nil,
        defaultDurationSeconds: Int? = nil,
        defaultRestSeconds: Int,
        loadType: LoadType,
        loadGuidance: String,
        imageName: String = "figure.strengthtraining.traditional",
        whyItHelpsRunners: String,
        commonMistakes: [String] = [],
        coachingCues: [String] = [],
        requiredEquipment: [GymEquipment],
        alternativeExercises: [String] = [],
        movementPattern: MovementPattern,
        avoidIf: [InjuryArea] = []
    ) {
        self.id = UUID(uuidString: slug.toStableUUID())!
        self.slug = slug
        self.name = name
        self.category = category
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.runnerBenefit = runnerBenefit
        self.supportsGoals = supportsGoals
        self.injuryPreventionTags = injuryPreventionTags
        self.defaultSets = defaultSets
        self.defaultReps = defaultReps
        self.defaultDurationSeconds = defaultDurationSeconds
        self.defaultRestSeconds = defaultRestSeconds
        self.loadType = loadType
        self.loadGuidance = loadGuidance
        self.imageName = imageName
        self.whyItHelpsRunners = whyItHelpsRunners
        self.commonMistakes = commonMistakes
        self.coachingCues = coachingCues
        self.requiredEquipment = requiredEquipment
        self.alternativeExercises = alternativeExercises
        self.movementPattern = movementPattern
        self.avoidIf = avoidIf
    }
    
    // MARK: - Computed Properties
    
    /// Display string for reps (e.g., "8-12 reps" or "30 seconds")
    var repsDisplayString: String {
        if let duration = defaultDurationSeconds {
            return "\(duration)s"
        } else if let reps = defaultReps {
            return "\(reps.lowerBound)-\(reps.upperBound) reps"
        } else {
            return "As prescribed"
        }
    }
    
    /// Full description for display
    var fullDescription: String {
        return "\(defaultSets) sets × \(repsDisplayString) • Rest \(defaultRestSeconds)s"
    }
}

// MARK: - String Extension for Stable UUIDs

extension String {
    /// Generate a deterministic UUID from a string slug
    func toStableUUID() -> String {
        // Use a deterministic hash to create a UUID namespace
        let namespace = "f47ac10b-58cc-4372-a567-0e02b2c3d479" // Fixed namespace UUID
        let combined = namespace + self
        
        // Create a simple hash-based UUID (for demo purposes)
        // In production, you might use a proper UUID v5 implementation
        var hash = combined.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) }
        hash = abs(hash)
        
        // Format as UUID string
        let hexString = String(format: "%016x", hash)
        let paddedHex = String(repeating: "0", count: max(0, 32 - hexString.count)) + hexString
        let truncated = String(paddedHex.prefix(32))
        
        return "\(truncated.prefix(8))-\(truncated.dropFirst(8).prefix(4))-\(truncated.dropFirst(12).prefix(4))-\(truncated.dropFirst(16).prefix(4))-\(truncated.dropFirst(20).prefix(12))"
    }
}
