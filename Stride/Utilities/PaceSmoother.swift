import Foundation

/// Smooths pace data to prevent wild fluctuations from noisy treadmill data
/// Uses exponential moving average (EMA) for responsive yet stable pace readings
class PaceSmoother {
    private var smoothedPaceSecPerKm: Double?
    private var smoothedSpeedMps: Double?
    
    // Smoothing factor (alpha): 0.0 = no change, 1.0 = instant change
    // 0.2 means new value has 20% weight, history has 80% weight
    private let alpha: Double = 0.2
    
    // Minimum speed threshold to prevent division by zero and filter out noise
    private let minSpeedThreshold: Double = 0.1 // 0.1 m/s (~0.36 km/h)
    
    /// Add a new speed sample and return smoothed pace
    /// - Parameter speedMps: Raw speed in meters per second from treadmill
    /// - Returns: Smoothed pace in seconds per kilometer
    func addSample(speedMps: Double) -> (smoothedPace: Double, smoothedSpeed: Double) {
        // Filter out invalid or very low speeds
        guard speedMps >= minSpeedThreshold else {
            // If speed is too low, return previous smooth value or 0
            let result = (smoothedPaceSecPerKm ?? 0, smoothedSpeedMps ?? 0)
            #if DEBUG
            if speedMps > 0 {
                print("⚠️ PaceSmoother: Filtered low speed \(speedMps) m/s, maintaining pace: \(result.0) sec/km")
            }
            #endif
            return result
        }
        
        // Apply exponential moving average to speed
        if let previousSpeed = smoothedSpeedMps {
            // EMA formula: smoothed = alpha * newValue + (1 - alpha) * previousSmoothed
            smoothedSpeedMps = alpha * speedMps + (1 - alpha) * previousSpeed
            
            #if DEBUG
            let rawPace = 1000.0 / speedMps
            let smoothedPace = 1000.0 / smoothedSpeedMps!
            let paceChange = abs(smoothedPace - (1000.0 / previousSpeed))
            if paceChange > 30 { // Log significant changes (>30 seconds)
                print("📊 PaceSmoother: Raw: \(String(format: "%.1f", rawPace)) sec/km → Smoothed: \(String(format: "%.1f", smoothedPace)) sec/km")
            }
            #endif
        } else {
            // First sample - no smoothing needed
            smoothedSpeedMps = speedMps
            #if DEBUG
            print("🏁 PaceSmoother: First sample - Speed: \(speedMps) m/s, Pace: \(1000.0/speedMps) sec/km")
            #endif
        }
        
        // Calculate pace from smoothed speed
        if let smoothedSpeed = smoothedSpeedMps, smoothedSpeed > minSpeedThreshold {
            smoothedPaceSecPerKm = 1000.0 / smoothedSpeed
        }
        
        return (smoothedPaceSecPerKm ?? 0, smoothedSpeedMps ?? 0)
    }
    
    /// Reset the smoother (e.g., when starting a new workout)
    func reset() {
        smoothedPaceSecPerKm = nil
        smoothedSpeedMps = nil
    }
    
    /// Get current smoothed values without adding a new sample
    func getCurrentSmoothed() -> (smoothedPace: Double, smoothedSpeed: Double) {
        return (smoothedPaceSecPerKm ?? 0, smoothedSpeedMps ?? 0)
    }
}

