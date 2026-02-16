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
    /// ±3% tolerance band around target = 1.0. Penalized symmetrically for under or over.
    private static func calculateDistanceScore(actual: Double, planned: Double?) -> Double? {
        guard let planned = planned, planned > 0 else { return nil }
        guard actual > 0 else { return 0 }

        let ratio = actual / planned
        let tolerance = 0.03 // ±3%

        if ratio >= (1.0 - tolerance) && ratio <= (1.0 + tolerance) {
            return 1.0
        }

        // Deviation beyond the tolerance band
        let deviation = ratio < 1.0
            ? (1.0 - tolerance) - ratio
            : ratio - (1.0 + tolerance)

        return max(1.0 - deviation * 1.5, 0.0)
    }
    
    // MARK: - Pace Score

    /// Returns 0.0 - 1.0 representing how well the runner matched the target pace.
    /// ±5 sec/km tolerance around target = 1.0. Penalized symmetrically for faster or slower.
    private static func calculatePaceScore(actualAvgPaceSecPerKm: Double, targetPaceDescription: String?) -> Double? {
        guard let targetPace = parsePaceToSeconds(targetPaceDescription),
              targetPace > 0,
              actualAvgPaceSecPerKm > 0 else {
            return nil
        }

        let deviation = abs(actualAvgPaceSecPerKm - targetPace)
        let tolerance: Double = 5.0 // ±5 sec/km

        if deviation <= tolerance {
            return 1.0
        }

        // How far beyond tolerance as a ratio of target pace
        let excessDeviation = (deviation - tolerance) / targetPace

        return max(1.0 - excessDeviation * 1.5, 0.25)
    }
    
    // MARK: - Pace Parsing

    /// Parse a single "M:SS" string into seconds.
    private static func parseSinglePace(_ text: String) -> Double? {
        let parts = text.split(separator: ":")
        guard parts.count == 2,
              let minutes = Double(parts[0]),
              let seconds = Double(parts[1]) else {
            return nil
        }
        return minutes * 60.0 + seconds
    }

    /// Parse a pace description string like "5:30/km" or "5:30-6:00/km" into seconds per km.
    /// For ranges, returns the average of the two paces.
    static func parsePaceToSeconds(_ description: String?) -> Double? {
        guard let description = description else { return nil }

        let cleaned = description
            .replacingOccurrences(of: "/km", with: "")
            .replacingOccurrences(of: "per km", with: "")
            .trimmingCharacters(in: .whitespaces)

        // Check for range: "5:30-6:00" or "5:30–6:00"
        for separator in ["-", "–", "—"] {
            let rangeParts = cleaned.split(separator: Character(separator))
            if rangeParts.count == 2,
               let min = parseSinglePace(rangeParts[0].trimmingCharacters(in: .whitespaces)),
               let max = parseSinglePace(rangeParts[1].trimmingCharacters(in: .whitespaces)) {
                return (min + max) / 2.0
            }
        }

        return parseSinglePace(cleaned)
    }

    /// Parse a pace description into a (min, max) range in seconds/km.
    /// "5:30-6:00/km" → (330, 360). "5:30/km" → (330, 330). "Easy Pace" → nil.
    static func parsePaceRange(_ description: String?) -> (min: Double, max: Double)? {
        guard let description = description else { return nil }

        let cleaned = description
            .replacingOccurrences(of: "/km", with: "")
            .replacingOccurrences(of: "per km", with: "")
            .trimmingCharacters(in: .whitespaces)

        // Check for range: "5:30-6:00"
        for separator in ["-", "–", "—"] {
            let rangeParts = cleaned.split(separator: Character(separator))
            if rangeParts.count == 2,
               let minPace = parseSinglePace(rangeParts[0].trimmingCharacters(in: .whitespaces)),
               let maxPace = parseSinglePace(rangeParts[1].trimmingCharacters(in: .whitespaces)) {
                // min = faster pace (lower sec/km), max = slower pace (higher sec/km)
                return (min: Swift.min(minPace, maxPace), max: Swift.max(minPace, maxPace))
            }
        }

        // Single pace value
        if let pace = parseSinglePace(cleaned) {
            return (min: pace, max: pace)
        }

        return nil
    }
}
