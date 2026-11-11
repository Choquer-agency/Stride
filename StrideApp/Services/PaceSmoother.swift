import Foundation

/// Distance-based fallback for GPS and consoles without instantaneous speed.
/// Treadmill live pace uses LiveSpeedSmoother below; splits still use distance.
final class PaceSmoother {
    private struct DistanceSample {
        let meters: Double
        let timestamp: TimeInterval   // elapsed run time
    }

    /// Rolling window — long enough to average out a 10 m odometer step, short
    /// enough to follow a real pace change.
    private let windowDuration: TimeInterval = 30.0

    /// Report nothing until the window holds this much history, so the opening
    /// seconds of a run don't flash a wild number.
    private let minimumWindow: TimeInterval = 10.0

    /// Below this we call it stopped rather than reporting a huge pace. Walking
    /// (~1.4 m/s) still reads, so a walk break shows an honest walking pace.
    private let minimumSpeed: Double = 0.5  // m/s (~33 min/km)

    private var samples: [DistanceSample] = []

    /// Feed the cumulative odometer in metres. Returns smoothed speed (m/s) and
    /// pace (sec/km); both are 0 when there isn't enough history yet or the
    /// runner has stopped — callers render that as "--:--".
    func addSample(distanceMeters: Double, elapsedTime: TimeInterval) -> (smoothedSpeed: Double, smoothedPace: Double) {
        // A console that zeroes its odometer mid-session — the AssaultRunner
        // does exactly this at session end — would otherwise fit a hugely
        // negative slope. Drop the window and start again.
        if let last = samples.last, distanceMeters < last.meters {
            samples.removeAll()
        }

        samples.append(DistanceSample(meters: distanceMeters, timestamp: elapsedTime))
        samples.removeAll { $0.timestamp < elapsedTime - windowDuration }

        return currentSmoothed()
    }

    func reset() {
        samples.removeAll()
    }

    // MARK: - Private

    private func currentSmoothed() -> (smoothedSpeed: Double, smoothedPace: Double) {
        guard let first = samples.first, let last = samples.last,
              last.timestamp - first.timestamp >= minimumWindow else { return (0, 0) }

        // Least-squares slope of distance against time is the speed.
        let n = Double(samples.count)
        let meanTime = samples.reduce(0.0) { $0 + $1.timestamp } / n
        let meanDistance = samples.reduce(0.0) { $0 + $1.meters } / n

        var numerator = 0.0
        var denominator = 0.0
        for sample in samples {
            let dt = sample.timestamp - meanTime
            numerator += dt * (sample.meters - meanDistance)
            denominator += dt * dt
        }
        guard denominator > 0 else { return (0, 0) }

        let speed = numerator / denominator
        guard speed >= minimumSpeed else { return (0, 0) }

        return (speed, 1000.0 / speed)
    }
}


// Light, time-based filtering of console speed. No calibration multiplier.
// Seed immediately on startup/restart; zero speed clears the previous run speed.
final class LiveSpeedSmoother {
    private var speed: Double?
    private var timestamp: Date?

    func addSample(speedMps: Double, timestamp: Date) -> Double {
        guard speedMps.isFinite, speedMps >= 0 else { return 0 }
        if speedMps < 0.5 {
            reset()
            return 0
        }
        if let previous = speed, let last = self.timestamp {
            let dt = timestamp.timeIntervalSince(last)
            guard dt > 0 else { return 1000 / previous }
            // Forget old readings after a connection gap.
            let alpha = dt > 5 ? 1 : 1 - exp(-dt / 1.5)
            speed = previous + alpha * (speedMps - previous)
        } else {
            speed = speedMps
        }
        self.timestamp = timestamp
        return 1000 / speed!
    }

    func reset() {
        speed = nil
        timestamp = nil
    }
}
