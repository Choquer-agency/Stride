import Foundation

/// Explicit 3-state model for day availability
enum DayState: String, Codable {
    case available   // Training day (green checkmark in UI)
    case rest        // Hard constraint rest day (moon icon, shown in calendar)
    case unavailable // Truly blank (not shown, not counted, neutral)
}

/// Training availability model - defines which days user can train, must rest, or has unavailable
struct TrainingAvailability: Codable, Equatable {
    // Internal storage as sets for efficient lookups
    var availableDays: Set<Int>  // 0 = Sunday, 6 = Saturday
    var restDays: Set<Int>
    
    // Optional preferences (soft constraints)
    var preferredLongRunDay: Int?
    var allowDoubleDays: Bool
    
    // MARK: - Initializer
    
    init(
        availableDays: Set<Int> = [],
        restDays: Set<Int> = [],
        preferredLongRunDay: Int? = nil,
        allowDoubleDays: Bool = false
    ) {
        self.availableDays = availableDays
        self.restDays = restDays
        self.preferredLongRunDay = preferredLongRunDay
        self.allowDoubleDays = allowDoubleDays
    }
    
    // MARK: - Computed Properties
    
    var totalAvailableDays: Int { availableDays.count }
    var totalRestDays: Int { restDays.count }
    var totalUnavailableDays: Int { 7 - availableDays.count - restDays.count }
    
    /// Whether user has any training days selected
    var hasTrainingDays: Bool { !availableDays.isEmpty }
    
    /// Default availability (all days available except Monday)
    static var `default`: TrainingAvailability {
        return TrainingAvailability(
            availableDays: [0, 2, 3, 4, 5, 6],  // Sun, Tue-Sat
            restDays: [1],  // Monday
            preferredLongRunDay: 0,  // Sunday
            allowDoubleDays: false
        )
    }
    
    // MARK: - UI Helpers
    
    /// Get the state for a specific day (0 = Sunday, 6 = Saturday)
    func stateForDay(_ day: Int) -> DayState {
        if availableDays.contains(day) { return .available }
        if restDays.contains(day) { return .rest }
        return .unavailable
    }
    
    /// Set the state for a specific day
    mutating func setState(_ state: DayState, forDay day: Int) {
        guard day >= 0 && day <= 6 else { return }
        
        // Remove from all sets first
        availableDays.remove(day)
        restDays.remove(day)
        
        // Add to appropriate set
        switch state {
        case .available: 
            availableDays.insert(day)
        case .rest: 
            restDays.insert(day)
        case .unavailable: 
            break // Stays removed from both
        }
    }
    
    /// Cycle to next state (for UI tap gesture)
    func nextState(for currentState: DayState) -> DayState {
        switch currentState {
        case .unavailable: return .available
        case .available: return .rest
        case .rest: return .unavailable
        }
    }
    
    // MARK: - Validation
    
    func validate() -> String? {
        // Sets must not overlap (enforced by setState, but double-check)
        if !availableDays.isDisjoint(with: restDays) {
            return "A day cannot be both available and rest"
        }
        
        // Day values must be 0-6
        for day in availableDays {
            if day < 0 || day > 6 {
                return "Day values must be between 0 (Sunday) and 6 (Saturday)"
            }
        }
        
        for day in restDays {
            if day < 0 || day > 6 {
                return "Day values must be between 0 (Sunday) and 6 (Saturday)"
            }
        }
        
        // Preferred long run day should be in available days (soft warning)
        if let longRunDay = preferredLongRunDay {
            if longRunDay < 0 || longRunDay > 6 {
                return "Long run day must be between 0 (Sunday) and 6 (Saturday)"
            }
            if restDays.contains(longRunDay) {
                return "Long run day cannot be a rest day"
            }
        }
        
        return nil
    }
    
    /// Whether availability is valid
    var isValid: Bool {
        return validate() == nil
    }
    
    // MARK: - Display Helpers
    
    /// Day name for display
    static func dayName(for dayIndex: Int) -> String {
        let formatter = DateFormatter()
        formatter.weekdaySymbols = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        guard dayIndex >= 0 && dayIndex < 7 else { return "Unknown" }
        return formatter.weekdaySymbols[dayIndex]
    }
    
    /// Short day name for display (S M T W T F S)
    static func shortDayName(for dayIndex: Int) -> String {
        let names = ["S", "M", "T", "W", "T", "F", "S"]
        guard dayIndex >= 0 && dayIndex < 7 else { return "?" }
        return names[dayIndex]
    }
    
    /// Very short day name for display (Su Mo Tu We Th Fr Sa)
    static func veryShortDayName(for dayIndex: Int) -> String {
        let names = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
        guard dayIndex >= 0 && dayIndex < 7 else { return "?" }
        return names[dayIndex]
    }
    
    /// Summary description
    var summary: String {
        var parts: [String] = []
        
        if totalAvailableDays > 0 {
            parts.append("\(totalAvailableDays) training day\(totalAvailableDays == 1 ? "" : "s")")
        } else {
            parts.append("No training days")
        }
        
        if totalRestDays > 0 {
            parts.append("\(totalRestDays) rest day\(totalRestDays == 1 ? "" : "s")")
        }
        
        if totalUnavailableDays > 0 {
            parts.append("\(totalUnavailableDays) unavailable")
        }
        
        return parts.joined(separator: " • ")
    }
}
