import Foundation
import SwiftData
import SwiftUI

@Model
final class Workout {
    // MARK: - Planned Properties
    var id: UUID
    var date: Date
    var workoutTypeRaw: String
    var title: String
    var details: String?
    var distanceKm: Double?
    var durationMinutes: Int?
    var paceDescription: String?
    var isCompleted: Bool
    var completedAt: Date?
    var notes: String?
    
    // MARK: - Actual Run Data (populated after a real run)
    var actualDistanceKm: Double?
    var actualDurationSeconds: Double?
    var actualAvgPaceSecPerKm: Double?
    var completionScore: Int?
    var kmSplitsJSON: String?
    var feedbackRating: Int?  // 0-5 subjective "how did it feel?" scale
    
    // MARK: - Relationships
    var week: Week?
    
    // MARK: - Computed Properties
    var workoutType: WorkoutType {
        get { WorkoutType(rawValue: workoutTypeRaw) ?? .easyRun }
        set { workoutTypeRaw = newValue.rawValue }
    }
    
    var dayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }
    
    var shortDayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
    
    var distanceDisplay: String? {
        guard let km = distanceKm else { return nil }
        if km == floor(km) {
            return "\(Int(km)) km"
        } else {
            return String(format: "%.1f km", km)
        }
    }
    
    var durationDisplay: String? {
        guard let minutes = durationMinutes else { return nil }
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 {
                return "\(hours)h"
            }
            return "\(hours)h \(mins)m"
        }
        return "\(minutes) min"
    }
    
    var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
    
    var isPast: Bool {
        date < Calendar.current.startOfDay(for: Date())
    }
    
    var isFuture: Bool {
        date > Calendar.current.startOfDay(for: Date().addingTimeInterval(86400))
    }
    
    /// Returns the best available distance: actual treadmill data if completed, otherwise planned.
    var effectiveDistanceKm: Double? {
        if isCompleted, let actual = actualDistanceKm {
            return actual
        }
        return distanceKm
    }
    
    /// Returns the best available duration in minutes.
    var effectiveDurationMinutes: Int? {
        if isCompleted, let actualSec = actualDurationSeconds {
            return Int(actualSec / 60.0)
        }
        return durationMinutes
    }
    
    /// Formatted actual pace string (M:SS /km)
    var actualPaceDisplay: String? {
        guard let pace = actualAvgPaceSecPerKm, pace > 0, pace < 3600 else { return nil }
        let minutes = Int(pace) / 60
        let seconds = Int(pace) % 60
        return "\(minutes):\(String(format: "%02d", seconds)) /km"
    }
    
    /// Decoded km splits from JSON
    var decodedKmSplits: [CodableKilometerSplit] {
        guard let json = kmSplitsJSON,
              let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([CodableKilometerSplit].self, from: data)) ?? []
    }
    
    var typeColor: Color {
        switch workoutType {
        case .easyRun: return .workoutEasy
        case .longRun: return .workoutLong
        case .tempoRun: return .workoutTempo
        case .intervals, .hillRepeats: return .workoutInterval
        case .recovery: return .workoutRecovery
        case .rest: return .workoutRest
        case .crossTraining, .gym: return .workoutGym
        case .race: return .workoutRace
        }
    }
    
    // MARK: - Initializer
    init(
        date: Date,
        workoutType: WorkoutType,
        title: String,
        details: String? = nil,
        distanceKm: Double? = nil,
        durationMinutes: Int? = nil,
        paceDescription: String? = nil
    ) {
        self.id = UUID()
        self.date = date
        self.workoutTypeRaw = workoutType.rawValue
        self.title = title
        self.details = details
        self.distanceKm = distanceKm
        self.durationMinutes = durationMinutes
        self.paceDescription = paceDescription
        self.isCompleted = false
    }
    
    // MARK: - Methods
    func toggleCompletion() {
        isCompleted.toggle()
        completedAt = isCompleted ? Date() : nil
    }
}

// MARK: - Codable Kilometer Split (for JSON persistence)
struct CodableKilometerSplit: Codable, Identifiable {
    var id: Int { kilometer }
    let kilometer: Int
    let pace: String
    let time: String
    let isFastest: Bool
}
