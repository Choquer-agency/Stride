import Foundation

/// Computes a 0-100 completion score for a planned run by comparing actual vs. planned metrics.
struct RunScoringService {
    
    /// Calculate the overall completion score for a planned run.
    /// Returns nil for free runs (no targets to compare against).
    static func calculateScore(result: RunResult) -> Int? {
        guard result.isPlannedRun else { return nil }
        
        let distanceScore = calculateDistanceScore(
            actual: result.distanceKm,
            planned: result.targetDistanceKm
        )
        
        let paceScore = calculatePaceScore(
            actualAvgPaceSecPerKm: result.avgPaceSecPerKm,
            targetPaceDescription: result.targetPaceDescription
        )
        
        // Weighted combination: distance 60%, pace 40%
        let overallScore: Double
        
        if let ds = distanceScore, let ps = paceScore {
            overallScore = ds * 0.6 + ps * 0.4
        } else if let ds = distanceScore {
            // No pace target — score purely on distance
            overallScore = ds
        } else if let ps = paceScore {
            // No distance target — score purely on pace
            overallScore = ps
        } else {
            // No targets at all — full credit for completing the run
            return 100
        }
        
        return Int(min(max(overallScore * 100, 0), 100))
    }
    
    // MARK: - Distance Score
    
    /// Returns 0.0 - 1.0 representing how well the runner hit the planned distance.
    /// Hitting or exceeding the target = 1.0. Falling short scales linearly.
    private static func calculateDistanceScore(actual: Double, planned: Double?) -> Double? {
        guard let planned = planned, planned > 0 else { return nil }
        guard actual > 0 else { return 0 }
        
        return min(actual / planned, 1.0)
    }
    
    // MARK: - Pace Score
    
    /// Returns 0.0 - 1.0 representing how well the runner matched the target pace.
    /// On-target or faster = 1.0.
    /// Progressively penalized for being slower:
    ///   - 10% slower -> 0.85
    ///   - 20% slower -> 0.70
    ///   - 30% slower -> 0.55
    ///   - 50%+ slower -> 0.25
    private static func calculatePaceScore(actualAvgPaceSecPerKm: Double, targetPaceDescription: String?) -> Double? {
        guard let targetPace = parsePaceToSeconds(targetPaceDescription),
              targetPace > 0,
              actualAvgPaceSecPerKm > 0 else {
            return nil
        }
        
        // If actual pace <= target pace (faster or equal), perfect score
        if actualAvgPaceSecPerKm <= targetPace {
            return 1.0
        }
        
        // How much slower as a ratio (e.g., 1.10 = 10% slower)
        let slowRatio = actualAvgPaceSecPerKm / targetPace
        
        // Penalty: linear decay from 1.0 at ratio 1.0 to 0.25 at ratio 1.5+
        // Formula: score = max(1.0 - (slowRatio - 1.0) * 1.5, 0.25)
        let score = max(1.0 - (slowRatio - 1.0) * 1.5, 0.25)
        
        return score
    }
    
    // MARK: - Pace Parsing
    
    /// Parse a pace description string like "5:30/km" or "5:30 /km" or "5:30" into seconds per km.
    static func parsePaceToSeconds(_ description: String?) -> Double? {
        guard let description = description else { return nil }
        
        // Strip "/km" or " /km" suffix
        let cleaned = description
            .replacingOccurrences(of: "/km", with: "")
            .replacingOccurrences(of: "per km", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        // Parse "M:SS" format
        let parts = cleaned.split(separator: ":")
        guard parts.count == 2,
              let minutes = Double(parts[0]),
              let seconds = Double(parts[1]) else {
            return nil
        }
        
        return minutes * 60.0 + seconds
    }
}
