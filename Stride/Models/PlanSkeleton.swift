import Foundation

/// Transient DTO for fast plan summary display.
/// NOT persisted - used only to show PlanSummaryView quickly before daily schedule loads.
/// TrainingPlan remains the canonical persistent object.
struct PlanSkeleton {
    let phases: [TrainingPhase]
    let goalFeasibility: GoalFeasibility?
    let paceContext: SkeletonPaceContext
    let weeklyTargets: [WeeklyTarget]
    let coachMessage: String
    
    /// Weekly volume target (fixed size, does not scale with days)
    struct WeeklyTarget {
        let week: Int
        let totalKm: Double
        let runDays: Int
        let gymDays: Int
    }
    
    /// Minimal pace context (numbers only, no prose)
    struct SkeletonPaceContext {
        let easyPace: Double        // sec/km
        let tempoPace: Double       // sec/km
        let intervalPace: Double    // sec/km
        let goalPace: Double?       // sec/km (nil for completion goals)
    }
}

// MARK: - JSON Parsing

extension PlanSkeleton {
    /// Parse skeleton from AI JSON response
    static func parse(from json: [String: Any]) throws -> PlanSkeleton {
        // Parse phases
        guard let phasesArray = json["phases"] as? [[String: Any]] else {
            throw SkeletonParseError.missingField("phases")
        }
        
        let phases = phasesArray.compactMap { phaseData -> TrainingPhase? in
            guard let name = phaseData["name"] as? String,
                  let weeks = phaseData["weeks"] as? [Int],
                  weeks.count == 2 else {
                return nil
            }
            
            let range = weeks[0]...weeks[1]
            
            if name.lowercased().contains("base") {
                return .baseBuilding(weeks: range)
            } else if name.lowercased().contains("build") {
                return .buildUp(weeks: range)
            } else if name.lowercased().contains("peak") {
                return .peakTraining(weeks: range)
            } else if name.lowercased().contains("taper") {
                return .taper(weeks: range)
            } else {
                return .baseBuilding(weeks: range)
            }
        }
        
        // Parse goal feasibility
        var goalFeasibility: GoalFeasibility? = nil
        if let feasibilityData = json["goal_feasibility"] as? [String: Any],
           let ratingString = feasibilityData["rating"] as? String,
           let rating = GoalFeasibility.Rating(rawValue: ratingString),
           let isRealistic = feasibilityData["is_realistic"] as? Bool,
           let reasoning = feasibilityData["reasoning"] as? String {
            
            goalFeasibility = GoalFeasibility(
                rating: rating,
                isRealistic: isRealistic,
                recommendedTargetTime: feasibilityData["recommended_time"] as? Double,
                reasoning: reasoning,
                confidence: .medium
            )
        }
        
        // Parse pace context
        guard let paceData = json["pace_context"] as? [String: Any],
              let easyPace = paceData["easy"] as? Double,
              let tempoPace = paceData["tempo"] as? Double,
              let intervalPace = paceData["interval"] as? Double else {
            throw SkeletonParseError.missingField("pace_context")
        }
        
        let paceContext = SkeletonPaceContext(
            easyPace: easyPace,
            tempoPace: tempoPace,
            intervalPace: intervalPace,
            goalPace: paceData["goal"] as? Double
        )
        
        // Parse weekly targets
        guard let targetsArray = json["weekly_targets"] as? [[String: Any]] else {
            throw SkeletonParseError.missingField("weekly_targets")
        }
        
        let weeklyTargets = targetsArray.compactMap { targetData -> WeeklyTarget? in
            guard let week = targetData["week"] as? Int,
                  let km = targetData["km"] as? Double,
                  let runs = targetData["runs"] as? Int,
                  let gym = targetData["gym"] as? Int else {
                return nil
            }
            return WeeklyTarget(week: week, totalKm: km, runDays: runs, gymDays: gym)
        }
        
        // Parse coach message
        let coachMessage = json["coach_message"] as? String ?? "Your personalized training plan is ready."
        
        return PlanSkeleton(
            phases: phases,
            goalFeasibility: goalFeasibility,
            paceContext: paceContext,
            weeklyTargets: weeklyTargets,
            coachMessage: coachMessage
        )
    }
    
    enum SkeletonParseError: LocalizedError {
        case missingField(String)
        
        var errorDescription: String? {
            switch self {
            case .missingField(let field):
                return "Missing required field: \(field)"
            }
        }
    }
}
