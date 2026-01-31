import Foundation

/// Record of a weekly adaptation event
struct AdaptationRecord: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let weekStartDate: Date
    let weekEndDate: Date
    
    // Analysis snapshot
    let completionRate: Double
    let avgPaceVariance: Double?
    let avgHRDrift: Double?
    let avgRPE: Double?
    let avgFatigue: Double?
    let injuryCount: Int
    let overallStatus: String // Stored as string for Codable
    
    // Adaptation summary
    let adjustmentCount: Int
    let volumeChangePercent: Double? // Negative = reduction, positive = increase
    let intensityChangePercent: Double?
    
    // Coach message
    let coachTitle: String
    let coachSummary: String
    let coachDetails: [String]
    let messageSeverity: String // Stored as string for Codable
    
    // User interaction
    var viewed: Bool
    var dismissed: Bool
    
    init(id: UUID = UUID(), adaptationPlan: AdaptationPlan) {
        self.id = id
        self.timestamp = adaptationPlan.createdAt
        self.weekStartDate = adaptationPlan.analysisResult.weekStartDate
        self.weekEndDate = adaptationPlan.analysisResult.weekEndDate
        
        // Analysis snapshot
        self.completionRate = adaptationPlan.analysisResult.completionRate
        self.avgPaceVariance = adaptationPlan.analysisResult.avgPaceVariance
        self.avgHRDrift = adaptationPlan.analysisResult.avgHRDrift
        self.avgRPE = adaptationPlan.analysisResult.avgRPE
        self.avgFatigue = adaptationPlan.analysisResult.avgFatigue
        self.injuryCount = adaptationPlan.analysisResult.injuryCount
        self.overallStatus = Self.statusToString(adaptationPlan.analysisResult.overallStatus)
        
        // Calculate adjustment summary
        self.adjustmentCount = adaptationPlan.adjustments.count
        
        var totalVolumeChange: Double = 0
        var volumeAdjustments = 0
        var totalIntensityChange: Double = 0
        var intensityAdjustments = 0
        
        for adjustment in adaptationPlan.adjustments {
            switch adjustment.changeType {
            case .volumeReduction:
                totalVolumeChange -= 10 // Approximate
                volumeAdjustments += 1
            case .volumeIncrease:
                totalVolumeChange += 5 // Approximate
                volumeAdjustments += 1
            case .intensityReduction:
                totalIntensityChange -= 5 // Approximate
                intensityAdjustments += 1
            case .intensityIncrease:
                totalIntensityChange += 3 // Approximate
                intensityAdjustments += 1
            default:
                break
            }
        }
        
        self.volumeChangePercent = volumeAdjustments > 0 ? totalVolumeChange / Double(volumeAdjustments) : nil
        self.intensityChangePercent = intensityAdjustments > 0 ? totalIntensityChange / Double(intensityAdjustments) : nil
        
        // Coach message
        self.coachTitle = adaptationPlan.coachMessage.title
        self.coachSummary = adaptationPlan.coachMessage.summary
        self.coachDetails = adaptationPlan.coachMessage.details
        self.messageSeverity = Self.severityToString(adaptationPlan.coachMessage.severity)
        
        // User interaction
        self.viewed = false
        self.dismissed = false
    }
    
    // Helper methods for enum conversion
    private static func statusToString(_ status: AnalysisResult.OverallStatus) -> String {
        switch status {
        case .excellent: return "excellent"
        case .good: return "good"
        case .needsRecovery: return "needs_recovery"
        case .needsRest: return "needs_rest"
        }
    }
    
    private static func severityToString(_ severity: AdaptationPlan.CoachMessage.Severity) -> String {
        switch severity {
        case .positive: return "positive"
        case .neutral: return "neutral"
        case .caution: return "caution"
        case .warning: return "warning"
        }
    }
    
    // Computed properties for display
    var formattedDateRange: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return "\(formatter.string(from: weekStartDate)) - \(formatter.string(from: weekEndDate))"
    }
    
    var completionRatePercent: Int {
        return Int(completionRate * 100)
    }
    
    var hasVolumeChange: Bool {
        return volumeChangePercent != nil && abs(volumeChangePercent!) > 0.5
    }
    
    var hasIntensityChange: Bool {
        return intensityChangePercent != nil && abs(intensityChangePercent!) > 0.5
    }
}
