import Foundation

class PaceSmoother {
    private var smoothedSpeed: Double?

    // Alpha = 0.2 means: 20% weight on new sample, 80% on history.
    // Lower alpha = smoother but slower to respond.
    // Higher alpha = more responsive but jittery.
    private let alpha: Double = 0.2
    private let minSpeedThreshold: Double = 0.1  // m/s (~0.36 km/h)

    /// Feed a raw speed sample, get back smoothed speed and pace.
    func addSample(speedMps: Double) -> (smoothedSpeed: Double, smoothedPace: Double) {
        guard speedMps >= minSpeedThreshold else {
            return (smoothedSpeed ?? 0, smoothedSpeed.map { 1000.0 / $0 } ?? 0)
        }

        if let prev = smoothedSpeed {
            smoothedSpeed = alpha * speedMps + (1 - alpha) * prev
        } else {
            smoothedSpeed = speedMps
        }

        let pace = smoothedSpeed.map { $0 > minSpeedThreshold ? 1000.0 / $0 : 0 } ?? 0
        return (smoothedSpeed ?? 0, pace)
    }

    /// Reset when starting a new workout.
    func reset() {
        smoothedSpeed = nil
    }
}
