import Foundation

/// User preferences for training plan generation
struct TrainingPreferences: Codable {
    var weeklyRunDays: Int
    var weeklyGymDays: Int
    var preferredRestDays: [Int]  // 0 = Sunday, 1 = Monday, etc.
    var preferredLongRunDay: Int  // 0 = Sunday, 1 = Monday, etc.
    var maxWeeklyKm: Double?      // Optional weekly distance cap
    var includeCrossTraining: Bool
    
    // New availability system (replaces weeklyRunDays/preferredRestDays going forward)
    var availability: TrainingAvailability?
    
    // MARK: - Initializer
    
    init(
        weeklyRunDays: Int = 4,
        weeklyGymDays: Int = 2,
        preferredRestDays: [Int] = [1],  // Monday
        preferredLongRunDay: Int = 0,     // Sunday
        maxWeeklyKm: Double? = nil,
        includeCrossTraining: Bool = false,
        availability: TrainingAvailability? = nil
    ) {
        self.weeklyRunDays = weeklyRunDays
        self.weeklyGymDays = weeklyGymDays
        self.preferredRestDays = preferredRestDays
        self.preferredLongRunDay = preferredLongRunDay
        self.maxWeeklyKm = maxWeeklyKm
        self.includeCrossTraining = includeCrossTraining
        self.availability = availability
    }
    
    // MARK: - Smart Defaults
    
    static var `default`: TrainingPreferences {
        return TrainingPreferences()
    }
    
    // MARK: - Validation
    
    /// Validates the preferences and returns error message if invalid
    func validate() -> String? {
        // Total days should not exceed 7
        let totalActiveDays = weeklyRunDays + weeklyGymDays + preferredRestDays.count
        if totalActiveDays > 7 {
            return "Total training and rest days cannot exceed 7"
        }
        
        // At least 2 run days required for training
        if weeklyRunDays < 2 {
            return "At least 2 run days per week are recommended"
        }
        
        // Max 6 run days (allow one rest day minimum)
        if weeklyRunDays > 6 {
            return "Maximum 6 run days per week recommended"
        }
        
        // Gym days should be reasonable
        if weeklyGymDays < 0 || weeklyGymDays > 4 {
            return "Gym days should be between 0 and 4 per week"
        }
        
        // Day values should be 0-6
        for day in preferredRestDays {
            if day < 0 || day > 6 {
                return "Day values must be between 0 (Sunday) and 6 (Saturday)"
            }
        }
        
        if preferredLongRunDay < 0 || preferredLongRunDay > 6 {
            return "Long run day must be between 0 (Sunday) and 6 (Saturday)"
        }
        
        // Max weekly km should be positive if set
        if let maxKm = maxWeeklyKm, maxKm <= 0 {
            return "Maximum weekly distance must be positive"
        }
        
        return nil
    }
    
    /// Whether preferences are valid
    var isValid: Bool {
        return validate() == nil
    }
    
    // MARK: - Helper Methods
    
    /// Day name for display
    static func dayName(for dayIndex: Int) -> String {
        let formatter = DateFormatter()
        formatter.weekdaySymbols = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        guard dayIndex >= 0 && dayIndex < 7 else { return "Unknown" }
        return formatter.weekdaySymbols[dayIndex]
    }
    
    /// Short day name for display
    static func shortDayName(for dayIndex: Int) -> String {
        let formatter = DateFormatter()
        formatter.shortWeekdaySymbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        guard dayIndex >= 0 && dayIndex < 7 else { return "?" }
        return formatter.shortWeekdaySymbols[dayIndex]
    }
    
    /// Summary description of preferences
    var summary: String {
        // Use new availability system if present
        if let avail = availability {
            var parts: [String] = []
            parts.append(avail.summary)
            
            if weeklyGymDays > 0 {
                parts.append("\(weeklyGymDays) gym days")
            }
            
            if let longRunDay = avail.preferredLongRunDay {
                let longRunDayName = TrainingPreferences.shortDayName(for: longRunDay)
                parts.append("Long run: \(longRunDayName)")
            }
            
            return parts.joined(separator: " • ")
        }
        
        // Fall back to old system for backward compatibility
        var parts: [String] = []
        parts.append("\(weeklyRunDays) run days")
        
        if weeklyGymDays > 0 {
            parts.append("\(weeklyGymDays) gym days")
        }
        
        if !preferredRestDays.isEmpty {
            let dayNames = preferredRestDays.map { TrainingPreferences.shortDayName(for: $0) }
            parts.append("Rest: \(dayNames.joined(separator: ", "))")
        }
        
        let longRunDayName = TrainingPreferences.shortDayName(for: preferredLongRunDay)
        parts.append("Long run: \(longRunDayName)")
        
        return parts.joined(separator: " • ")
    }
    
    /// Get effective availability (new system or derived from old)
    func getEffectiveAvailability() -> TrainingAvailability {
        if let avail = availability {
            return avail
        }
        
        // Derive from old model (ONLY trust preferredRestDays)
        let restDays = Set(preferredRestDays)
        let allDays = Set(0...6)
        let availableDays = allDays.subtracting(restDays)
        
        return TrainingAvailability(
            availableDays: availableDays,
            restDays: restDays,
            preferredLongRunDay: preferredLongRunDay,
            allowDoubleDays: false
        )
    }
}
