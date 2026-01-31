import Foundation

/// Calculate kilometer splits from workout samples
struct SplitsCalculator {
    
    /// Calculate splits from workout samples
    /// Returns an array of splits, one for each complete kilometer
    static func calculateSplits(from samples: [WorkoutSample]) -> [Split] {
        guard !samples.isEmpty else { return [] }
        
        var splits: [Split] = []
        var currentKm = 1
        var lastKmTimestamp: Date = samples.first!.timestamp
        
        for sample in samples {
            let distanceKm = sample.totalDistanceMeters / 1000.0
            
            // Check if we've crossed the next km boundary
            if distanceKm >= Double(currentKm) {
                let splitTime = sample.timestamp.timeIntervalSince(lastKmTimestamp)
                let split = Split(kmIndex: currentKm, splitTimeSeconds: splitTime)
                splits.append(split)
                
                // Move to next km
                currentKm += 1
                lastKmTimestamp = sample.timestamp
            }
        }
        
        return splits
    }
    
    /// Calculate average pace for a set of samples
    static func calculateAveragePace(from samples: [WorkoutSample]) -> Double {
        guard !samples.isEmpty else { return 0 }
        
        let totalDistance = samples.last?.totalDistanceMeters ?? 0
        let startTime = samples.first?.timestamp ?? Date()
        let endTime = samples.last?.timestamp ?? Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        guard duration > 0, totalDistance > 0 else { return 0 }
        
        let avgSpeedMps = totalDistance / duration
        return 1000.0 / avgSpeedMps // seconds per km
    }
}

