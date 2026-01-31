import SwiftUI

/// Helper for accessing Stride brand assets and colors
enum BrandAssets {
    // MARK: - Asset Names
    
    static let logo = "StrideLogo"
    static let wordmark = "StrideWordmark"
    static let strengthIcon = "StrengthTrainingIcon"
    static let restDayIcon = "RestDayIcon"
    
    // MARK: - Brand Colors
    
    /// Primary brand color - neon green from logo
    static let brandPrimary = Color.stridePrimary
    
    /// Workout type colors based on provided SVGs
    struct WorkoutColors {
        static let easyRun = Color(hex: "8BEB4B")       // Bright green
        static let longRun = Color.strideOrange         // Golden yellow
        static let tempo = Color.strideRed              // Orange-red
        static let interval = Color.strideRed           // Orange-red (same as tempo)
        static let recovery = Color(hex: "8BEB4B")      // Same as easy run
        static let raceSimulation = Color.strideRed     // Orange-red
        static let strength = Color(hex: "C6D031")      // Yellow-green
        static let rest = Color(hex: "D6D6D6")          // Light gray
        static let crossTraining = Color(hex: "00CED1") // Cyan
    }
    
    // MARK: - Helper Functions
    
    /// Get the appropriate icon for a workout type
    /// - Parameter workoutType: The workout type
    /// - Returns: Image view with appropriate icon and tinting
    static func workoutIcon(for workoutType: PlannedWorkout.WorkoutType) -> Image {
        switch workoutType {
        case .gym:
            return Image(strengthIcon)
        case .rest:
            return Image(restDayIcon)
        default:
            // Use Stride logo for all running workouts
            return Image(logo)
        }
    }
    
    /// Get the appropriate color for a workout type
    /// - Parameter workoutType: The workout type
    /// - Returns: Color for the workout type
    static func workoutColor(for workoutType: PlannedWorkout.WorkoutType) -> Color {
        switch workoutType {
        case .easyRun:
            return WorkoutColors.easyRun
        case .recoveryRun:
            return WorkoutColors.recovery
        case .longRun:
            return WorkoutColors.longRun
        case .tempoRun:
            return WorkoutColors.tempo
        case .intervalWorkout:
            return WorkoutColors.interval
        case .raceSimulation:
            return WorkoutColors.raceSimulation
        case .gym:
            return WorkoutColors.strength
        case .rest:
            return WorkoutColors.rest
        case .crossTraining:
            return WorkoutColors.crossTraining
        }
    }
    
    /// Get a colored workout icon
    /// - Parameter workoutType: The workout type
    /// - Returns: Image view with icon and color applied
    static func coloredWorkoutIcon(for workoutType: PlannedWorkout.WorkoutType) -> some View {
        workoutIcon(for: workoutType)
            .renderingMode(.template)
            .foregroundColor(workoutColor(for: workoutType))
    }
}

// MARK: - Extensions for easy access

extension PlannedWorkout.WorkoutType {
    /// Get the brand asset icon for this workout type
    var brandIcon: Image {
        BrandAssets.workoutIcon(for: self)
    }
    
    /// Get the brand color for this workout type
    var brandColor: Color {
        BrandAssets.workoutColor(for: self)
    }
}
