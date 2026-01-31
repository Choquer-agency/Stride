import Foundation

/// Goal feasibility assessment from AI training plan generation
struct GoalFeasibility: Codable {
    let rating: Rating
    let isRealistic: Bool
    let recommendedTargetTime: TimeInterval?
    let reasoning: String
    let confidence: Confidence
    
    enum Rating: String, Codable {
        case realistic
        case ambitious
        case aggressive
        case unrealistic
        
        var displayName: String {
            switch self {
            case .realistic: return "Realistic"
            case .ambitious: return "Ambitious"
            case .aggressive: return "Very Aggressive"
            case .unrealistic: return "Unrealistic"
            }
        }
    }
    
    enum Confidence: String, Codable {
        case high
        case medium
        case low
    }
}
