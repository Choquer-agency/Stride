import Foundation

// MARK: - Double Extensions

extension Double {
    /// Convert seconds to time string (mm:ss or h:mm:ss)
    func toTimeString() -> String {
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    /// Convert seconds to full time string always showing hours (00:00:00)
    func toFullTimeString() -> String {
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    /// Convert seconds per km to pace string (mm:ss /km)
    func toPaceString() -> String {
        if self <= 0 || self.isInfinite || self.isNaN {
            return "--:-- /km"
        }
        
        let totalSeconds = Int(self)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        
        return String(format: "%d:%02d /km", minutes, seconds)
    }
    
    /// Convert meters to distance string
    func toDistanceString() -> String {
        if self < 1000 {
            return String(format: "%.0f m", self)
        } else {
            let km = self / 1000.0
            return String(format: "%.2f km", km)
        }
    }
    
    /// Convert m/s to km/h string
    func toSpeedString() -> String {
        let kmh = self * 3.6
        return String(format: "%.1f km/h", kmh)
    }
}

// MARK: - Date Extensions

extension Date {
    /// Format date for workout display
    func toWorkoutDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
    
    /// Format date for workout list (short version)
    func toShortDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: self)
    }
    
    /// Format time only
    func toTimeOnlyString() -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
    
    /// Format date only (e.g., "June 1, 2026")
    func toDateOnlyString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: self)
    }
    
    /// Get day name (e.g., "Saturday", "Monday")
    func toDayName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: self)
    }
    
    /// Get time period (morning/afternoon/evening)
    func toTimePeriod() -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: self)
        
        if hour < 12 {
            return "morning"
        } else if hour < 17 {
            return "afternoon"
        } else {
            return "evening"
        }
    }
    
    /// Generate default workout title (e.g., "Saturday morning run")
    func toDefaultWorkoutTitle() -> String {
        let dayName = self.toDayName()
        let period = self.toTimePeriod()
        return "\(dayName) \(period) run"
    }
}

