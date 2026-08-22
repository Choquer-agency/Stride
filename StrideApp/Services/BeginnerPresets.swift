import Foundation

// MARK: - Beginner Presets
/// Pre-seeded onboarding data for the "Create Plan – M" beginner flow.
enum MichellePreset {

    static let equipmentDescription =
        "Light dumbbells 5–10 lb, kettlebells, bodyweight only. " +
        "Do NOT prescribe: barbell, squat rack, SkiErg, machines, plyometrics."

    static let notesDescription =
        "Has a Peloton bike and usually does a short Peloton app class " +
        "(abs/core or Pilates) right after rides — suggest it as an optional " +
        "add-on after ride days, don't program its content."

    /// Michelle's starting point: brand-new runner, habit block, 2 runs /
    /// 2 Peloton rides / 2 light strength days. Everything is editable in the flow.
    static func seededData() -> OnboardingData {
        var data = OnboardingData()
        data.beginnerMode = true
        data.goalType = .habit
        data.blockWeeks = 10
        data.fitnessLevel = .beginner
        data.raceType = .fiveK
        data.currentWeeklyMileage = 0
        data.longestRecentRun = 0
        data.yearsRunning = 0
        data.runningDaysPerWeek = 2
        data.gymDaysPerWeek = 2
        data.crossTrainDaysPerWeek = 2
        data.crossTrainModality = "Peloton indoor cycling"
        data.strengthEquipment = equipmentDescription
        data.trainingNotes = notesDescription
        return data
    }
}
