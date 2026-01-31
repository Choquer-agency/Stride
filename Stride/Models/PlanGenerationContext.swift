import Foundation

/// Context about how a training plan was generated - for explainability and trust
struct PlanGenerationContext: Codable {
    let generationMethod: GenerationMethod
    let baselineSource: BaselineSource
    let baselineVDOT: Double?
    let baselineDate: Date?
    let goalInfluence: GoalInfluence
    let confidenceLevel: ConfidenceLevel
    let constraintsApplied: [String]
    let llmStatus: LLMStatus
    let generatedAt: Date
    var lastAdaptedAt: Date?
    var adaptationTrigger: String?
    
    // MARK: - Enums
    
    enum GenerationMethod: String, Codable {
        case ruleBased = "rule_based"
        case aiEnhanced = "ai_enhanced"
        case hybrid = "hybrid"
        
        var displayName: String {
            switch self {
            case .ruleBased:
                return "Structured Coaching Rules"
            case .aiEnhanced:
                return "AI-Enhanced Planning"
            case .hybrid:
                return "Structured Rules + AI Refinement"
            }
        }
        
        var description: String {
            switch self {
            case .ruleBased:
                return "This plan was generated using structured coaching rules based on Jack Daniels' methodology."
            case .aiEnhanced:
                return "This plan was created with AI-powered planning and personalization."
            case .hybrid:
                return "This plan was generated using structured coaching rules and refined with AI for enhanced descriptions and personalization."
            }
        }
    }
    
    enum BaselineSource: String, Codable {
        case recentRace = "recent_race"
        case guidedTest = "guided_test"
        case manualInput = "manual_input"
        case estimated = "estimated"
        case none = "none"
        
        var displayName: String {
            switch self {
            case .recentRace:
                return "Recent Race Result"
            case .guidedTest:
                return "Guided Baseline Test"
            case .manualInput:
                return "Manual Time Entry"
            case .estimated:
                return "Estimated Fitness"
            case .none:
                return "No Baseline"
            }
        }
        
        func description(vdot: Double?, date: Date?) -> String {
            switch self {
            case .recentRace:
                if let vdot = vdot, let date = date {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    return "Paces are based on your recent race result (VDOT \(String(format: "%.1f", vdot)), \(formatter.string(from: date)))."
                }
                return "Paces are based on your recent race result."
            case .guidedTest:
                if let vdot = vdot {
                    return "Paces are based on your guided baseline test (VDOT \(String(format: "%.1f", vdot)))."
                }
                return "Paces are based on your guided baseline test."
            case .manualInput:
                if let vdot = vdot {
                    return "Paces are based on your time trial entry (VDOT \(String(format: "%.1f", vdot)))."
                }
                return "Paces are based on your time trial entry."
            case .estimated:
                return "Paces are estimated based on conservative training guidelines."
            case .none:
                return "Paces use conservative default values suitable for building fitness safely."
            }
        }
    }
    
    enum GoalInfluence: String, Codable {
        case pacesAligned = "paces_aligned"
        case pacesConstrained = "paces_constrained"
        case noTimeGoal = "no_time_goal"
        
        func description(goalName: String) -> String {
            switch self {
            case .pacesAligned:
                return "Training paces are aligned with your \(goalName) goal time."
            case .pacesConstrained:
                return "Goal time for \(goalName) noted, but training paces are constrained by current fitness for safety. We'll progress toward goal pace as fitness confirms readiness."
            case .noTimeGoal:
                return "Focus is on building endurance and finishing strong for \(goalName)."
            }
        }
    }
    
    enum ConfidenceLevel: String, Codable {
        case high = "high"
        case medium = "medium"
        case low = "low"
        
        var displayName: String {
            switch self {
            case .high:
                return "High Confidence"
            case .medium:
                return "Medium Confidence"
            case .low:
                return "Conservative Approach"
            }
        }
        
        var icon: String {
            switch self {
            case .high:
                return "checkmark.seal.fill"
            case .medium:
                return "info.circle.fill"
            case .low:
                return "exclamationmark.triangle.fill"
            }
        }
        
        var color: String {
            switch self {
            case .high:
                return "green"
            case .medium:
                return "blue"
            case .low:
                return "orange"
            }
        }
        
        var description: String {
            switch self {
            case .high:
                return "Paces are based on recent performance data and will adapt as you log workouts."
            case .medium:
                return "Paces are based on available fitness data. We'll refine them as you complete workouts."
            case .low:
                return "Paces are conservative because no recent race or test was provided. You can recalibrate your baseline at any time to get more personalized pacing."
            }
        }
    }
    
    enum LLMStatus: String, Codable {
        case off = "off"
        case enabled = "enabled"
        case failed = "failed"
        
        var displayName: String {
            switch self {
            case .off:
                return "Off"
            case .enabled:
                return "Enabled"
            case .failed:
                return "Unavailable"
            }
        }
        
        func description(reason: String?) -> String {
            switch self {
            case .off:
                if let reason = reason {
                    return "AI refinement: Off (\(reason))"
                }
                return "AI refinement: Off (no API key configured)"
            case .enabled:
                return "AI refinement: On (used for workout descriptions and personalization)"
            case .failed:
                if let reason = reason {
                    return "AI refinement: Failed (\(reason)). Using rule-based plan."
                }
                return "AI refinement: Failed. Using rule-based plan."
            }
        }
    }
    
    // MARK: - Initializer
    
    init(
        generationMethod: GenerationMethod,
        baselineSource: BaselineSource,
        baselineVDOT: Double? = nil,
        baselineDate: Date? = nil,
        goalInfluence: GoalInfluence,
        confidenceLevel: ConfidenceLevel,
        constraintsApplied: [String] = [],
        llmStatus: LLMStatus,
        generatedAt: Date = Date(),
        lastAdaptedAt: Date? = nil,
        adaptationTrigger: String? = nil
    ) {
        self.generationMethod = generationMethod
        self.baselineSource = baselineSource
        self.baselineVDOT = baselineVDOT
        self.baselineDate = baselineDate
        self.goalInfluence = goalInfluence
        self.confidenceLevel = confidenceLevel
        self.constraintsApplied = constraintsApplied
        self.llmStatus = llmStatus
        self.generatedAt = generatedAt
        self.lastAdaptedAt = lastAdaptedAt
        self.adaptationTrigger = adaptationTrigger
    }
    
    // MARK: - Computed Properties
    
    /// Whether this plan has been adapted since initial generation
    var hasBeenAdapted: Bool {
        return lastAdaptedAt != nil
    }
    
    /// Age of baseline in days (nil if no baseline)
    var baselineAgeInDays: Int? {
        guard let baselineDate = baselineDate else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: baselineDate, to: Date())
        return components.day
    }
    
    /// Whether baseline is recent (within 90 days)
    var isBaselineRecent: Bool {
        guard let age = baselineAgeInDays else { return false }
        return age <= 90
    }
}
