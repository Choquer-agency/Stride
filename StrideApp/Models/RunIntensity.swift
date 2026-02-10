import Foundation
import SwiftUI

// MARK: - Run Intensity (Canonical Taxonomy)
enum RunIntensity: String, Codable, CaseIterable {
    case recovery
    case easy
    case steady
    case marathonPace
    case threshold
    case interval
    case repetition
    
    /// Maps to display buckets for charts
    var displayBucket: IntensityBucket {
        switch self {
        case .recovery, .easy:
            return .easy
        case .steady, .marathonPace:
            return .moderate
        case .threshold, .interval, .repetition:
            return .hard
        }
    }
}

// MARK: - Intensity Bucket (Display Categories)
enum IntensityBucket: String, CaseIterable {
    case easy      // Green
    case moderate  // Yellow/Orange
    case hard      // Red
    
    var color: Color {
        switch self {
        case .easy: return .workoutEasy
        case .moderate: return .workoutTempo
        case .hard: return .workoutInterval
        }
    }
    
    var displayName: String {
        switch self {
        case .easy: return "Easy"
        case .moderate: return "Moderate"
        case .hard: return "Hard"
        }
    }
}

// MARK: - Workout Type to Run Intensity Mapping
extension WorkoutType {
    /// Maps WorkoutType to RunIntensity for stats calculations
    var runIntensity: RunIntensity? {
        switch self {
        case .recovery:
            return .recovery
        case .easyRun:
            return .easy
        case .longRun:
            return .steady  // Long runs are typically steady pace
        case .tempoRun:
            return .threshold  // Tempo runs are threshold effort
        case .race:
            return .marathonPace  // Race pace
        case .intervals, .hillRepeats:
            return .interval
        case .rest, .gym, .crossTraining:
            return nil // Not a running intensity
        }
    }
}
