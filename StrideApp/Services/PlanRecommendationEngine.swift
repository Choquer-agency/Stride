import Foundation

// MARK: - Plan Recommendation Engine
/// Client-side rule engine behind the beginner flow's inline coaching nudges.
/// Pure functions, instant — no LLM call. First blocking rule wins, then the
/// first caution, then the first info, else a success summary.
struct PlanRecommendation: Equatable {
    enum Severity: Equatable {
        case success   // balanced setup — green
        case info      // helpful suggestion — neutral
        case caution   // works, but the coach would push back — orange
        case blocking  // configuration can't work — red, disables Continue
    }

    let severity: Severity
    let message: String
}

enum PlanRecommendationEngine {

    /// Evaluate the current onboarding data and return the single most
    /// important recommendation to show.
    static func evaluate(_ data: OnboardingData) -> PlanRecommendation {
        let runs = data.runningDaysPerWeek
        let rides = data.crossTrainDaysPerWeek
        let strength = data.gymDaysPerWeek
        let availableDays = 7 - data.restDays.count
        let totalSessions = runs + rides + strength
        let isBeginner = data.fitnessLevel == .beginner
        let hasRace = data.goalType != .habit
        let hasPeloton = data.crossTrainModality != nil

        // Blocking: more sessions than days
        if totalSessions > availableDays && !data.doubleDaysAllowed {
            return PlanRecommendation(
                severity: .blocking,
                message: "That's \(totalSessions) sessions in \(availableDays) available days. Drop a session or free up a rest day."
            )
        }

        // Cautions, most important first
        if hasRace && isBeginner && (data.raceType == .halfMarathon || data.raceType == .marathon) {
            return PlanRecommendation(
                severity: .caution,
                message: "A \(data.raceType.displayName.lowercased()) is a big first goal. Most new runners thrive starting with a 5K — or a habit block first."
            )
        }
        if hasRace && runs == 1 {
            return PlanRecommendation(
                severity: .caution,
                message: "Training for a race on 1 run a week is tough. 3 run days is the sweet spot; 2 is the workable minimum."
            )
        }
        if hasRace && isBeginner {
            let weeks = Calendar.current.dateComponents([.day], from: data.startDate, to: data.raceDate).day.map { $0 / 7 } ?? 0
            let minWeeks = data.raceType == .fiveK ? 8 : 12
            if weeks < minWeeks {
                return PlanRecommendation(
                    severity: .caution,
                    message: "\(weeks) weeks is a short runway for a first \(data.raceType.displayName.lowercased()). A later race — or a habit block first — sets you up better."
                )
            }
        }
        if !hasRace && isBeginner && runs >= 4 {
            return PlanRecommendation(
                severity: .caution,
                message: "4+ run days is a lot for a brand-new runner. 2–3 runs with rides in between builds the same fitness with less injury risk."
            )
        }
        if isBeginner && runs + rides >= 6 {
            return PlanRecommendation(
                severity: .caution,
                message: "That's a lot of cardio to start. 2 runs + 2 rides is plenty for the first block — you can always add more later."
            )
        }

        // Info nudges
        if runs <= 2 && rides == 0 && hasPeloton {
            return PlanRecommendation(
                severity: .info,
                message: "With \(runs) run day\(runs == 1 ? "" : "s"), adding 1–2 Peloton rides builds your aerobic base with zero impact."
            )
        }
        if strength == 0 {
            return PlanRecommendation(
                severity: .info,
                message: "One 20-minute strength day makes a real dent in injury risk — worth it even with light weights."
            )
        }

        // Balanced
        var parts = ["\(runs) run\(runs == 1 ? "" : "s")"]
        if rides > 0 { parts.append("\(rides) ride\(rides == 1 ? "" : "s")") }
        if strength > 0 { parts.append("\(strength) strength") }
        return PlanRecommendation(
            severity: .success,
            message: "Balanced week: \(parts.joined(separator: " + ")). Nice."
        )
    }
}
