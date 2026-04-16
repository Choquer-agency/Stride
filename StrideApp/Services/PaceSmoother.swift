import Foundation

class PaceSmoother {
    private struct SpeedSample {
        let speedMps: Double
        let timestamp: TimeInterval   // elapsed run time
    }

    /// How far back (in seconds) to look when computing the rolling average.
    private let windowDuration: TimeInterval = 30.0

    private var samples: [SpeedSample] = []
    private let minSpeedThreshold: Double = 0.3  // m/s (~55 min/km)

    /// Feed a raw speed sample. Returns a 30-second rolling-average speed
    /// (m/s) and pace (sec/km). GPS jitter is absorbed into the window.
    func addSample(speedMps: Double, elapsedTime: TimeInterval = CACurrentMediaTime()) -> (smoothedSpeed: Double, smoothedPace: Double) {
        guard speedMps >= minSpeedThreshold else {
            // Standing still — return current average unchanged.
            return currentSmoothed()
        }

        samples.append(SpeedSample(speedMps: speedMps, timestamp: elapsedTime))
        evict(before: elapsedTime - windowDuration)

        return currentSmoothed()
    }

    func reset() {
        samples.removeAll()
    }

    // MARK: - Private

    private func evict(before cutoff: TimeInterval) {
        samples.removeAll { $0.timestamp < cutoff }
    }

    private func currentSmoothed() -> (smoothedSpeed: Double, smoothedPace: Double) {
        guard !samples.isEmpty else { return (0, 0) }
        let avgSpeed = samples.reduce(0.0) { $0 + $1.speedMps } / Double(samples.count)
        let pace = avgSpeed > 0 ? 1000.0 / avgSpeed : 0
        return (avgSpeed, pace)
    }
}
