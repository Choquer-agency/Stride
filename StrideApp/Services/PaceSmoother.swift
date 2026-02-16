import Foundation

class PaceSmoother {
    private var lastPace: Double = 0
    private let minSpeedThreshold: Double = 0.1  // m/s

    /// Feed a raw speed sample. Returns speed (m/s) and pace (sec/km) — no smoothing.
    func addSample(speedMps: Double) -> (smoothedSpeed: Double, smoothedPace: Double) {
        guard speedMps >= minSpeedThreshold else {
            let speed = lastPace > 0 ? 1000.0 / lastPace : 0
            return (speed, lastPace)
        }

        let pace = 1000.0 / speedMps
        lastPace = pace
        return (speedMps, pace)
    }

    /// Reset when starting a new workout.
    func reset() {
        lastPace = 0
    }
}
