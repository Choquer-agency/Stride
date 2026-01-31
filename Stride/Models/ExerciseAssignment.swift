import Foundation

/// Links an exercise to a planned workout with specific sets, reps, and load
struct ExerciseAssignment: Codable, Identifiable {
    let id: UUID
    let exerciseSlug: String  // References Exercise by stable slug
    let order: Int
    let sets: Int
    let reps: ClosedRange<Int>?  // e.g., 8...12
    let durationSeconds: Int?    // For time-based exercises
    let restSeconds: Int?        // Rest between sets
    
    // Load specification (coach beside you)
    let loadType: LoadType?      // Override exercise default if needed
    let loadValue: Double?       // Specific weight in kg/lbs
    let rpeTarget: Double?       // e.g., 7.0 out of 10
    
    let notes: String?  // Additional coaching notes
    
    // MARK: - Initializer
    
    init(
        id: UUID = UUID(),
        exerciseSlug: String,
        order: Int,
        sets: Int,
        reps: ClosedRange<Int>? = nil,
        durationSeconds: Int? = nil,
        restSeconds: Int? = nil,
        loadType: LoadType? = nil,
        loadValue: Double? = nil,
        rpeTarget: Double? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.exerciseSlug = exerciseSlug
        self.order = order
        self.sets = sets
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.restSeconds = restSeconds
        self.loadType = loadType
        self.loadValue = loadValue
        self.rpeTarget = rpeTarget
        self.notes = notes
    }
    
    // MARK: - Computed Properties
    
    /// Display string for reps/duration
    var volumeDisplayString: String {
        if let duration = durationSeconds {
            return "\(duration)s"
        } else if let reps = reps {
            return "\(reps.lowerBound)-\(reps.upperBound) reps"
        } else {
            return "As prescribed"
        }
    }
    
    /// Full description for display
    var fullDescription: String {
        var parts: [String] = []
        parts.append("\(sets) sets × \(volumeDisplayString)")
        
        if let rest = restSeconds {
            parts.append("Rest \(rest)s")
        }
        
        if let rpe = rpeTarget {
            parts.append("RPE \(String(format: "%.1f", rpe))")
        }
        
        return parts.joined(separator: " • ")
    }
    
    /// Load description for display
    var loadDisplayString: String? {
        if let value = loadValue {
            return String(format: "%.1f kg", value)
        } else if let rpe = rpeTarget {
            return "RPE \(String(format: "%.1f", rpe))/10"
        }
        return nil
    }
}

// MARK: - Codable for ClosedRange

extension ExerciseAssignment {
    enum CodingKeys: String, CodingKey {
        case id, exerciseSlug, order, sets, durationSeconds, restSeconds
        case loadType, loadValue, rpeTarget, notes
        case repsLowerBound, repsUpperBound
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        exerciseSlug = try container.decode(String.self, forKey: .exerciseSlug)
        order = try container.decode(Int.self, forKey: .order)
        sets = try container.decode(Int.self, forKey: .sets)
        durationSeconds = try container.decodeIfPresent(Int.self, forKey: .durationSeconds)
        restSeconds = try container.decodeIfPresent(Int.self, forKey: .restSeconds)
        loadType = try container.decodeIfPresent(LoadType.self, forKey: .loadType)
        loadValue = try container.decodeIfPresent(Double.self, forKey: .loadValue)
        rpeTarget = try container.decodeIfPresent(Double.self, forKey: .rpeTarget)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        
        // Decode reps range
        if let lower = try container.decodeIfPresent(Int.self, forKey: .repsLowerBound),
           let upper = try container.decodeIfPresent(Int.self, forKey: .repsUpperBound) {
            reps = lower...upper
        } else {
            reps = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(exerciseSlug, forKey: .exerciseSlug)
        try container.encode(order, forKey: .order)
        try container.encode(sets, forKey: .sets)
        try container.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
        try container.encodeIfPresent(restSeconds, forKey: .restSeconds)
        try container.encodeIfPresent(loadType, forKey: .loadType)
        try container.encodeIfPresent(loadValue, forKey: .loadValue)
        try container.encodeIfPresent(rpeTarget, forKey: .rpeTarget)
        try container.encodeIfPresent(notes, forKey: .notes)
        
        // Encode reps range
        if let reps = reps {
            try container.encode(reps.lowerBound, forKey: .repsLowerBound)
            try container.encode(reps.upperBound, forKey: .repsUpperBound)
        }
    }
}
