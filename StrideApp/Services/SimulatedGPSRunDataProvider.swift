import Foundation
import CoreLocation
import os.log

private let simLog = Logger(subsystem: "com.stride.app", category: "SimulatedGPS")

/// Simulated GPS provider for testing outdoor run UI without going outside.
/// Generates a random walking/running route at configurable pace, emitting RunSamples
/// that feed the full pipeline: live map, splits, voice coaching, timer.
final class SimulatedGPSRunDataProvider: RunDataProvider {
    var onRunSample: ((RunSample) -> Void)?
    let dataSourceType: String = "gps"
    let deviceName: String? = nil

    // MARK: - Route Data (matches GPSRunDataProvider interface)
    private(set) var routePoints: [RoutePoint] = []
    private(set) var elevationGain: Double = 0
    private(set) var elevationLoss: Double = 0

    // MARK: - Simulation Config

    /// Target pace in seconds per km (20 = 0:20/km for fast testing)
    private let targetPaceSecPerKm: Double = 20.0

    /// How often to emit a sample (seconds)
    private let updateInterval: TimeInterval = 0.5

    /// Speed in m/s derived from target pace
    private var speedMps: Double { 1000.0 / targetPaceSecPerKm }

    // MARK: - State
    private var timer: Timer?
    private var totalDistanceMeters: Double = 0
    private var elapsedTime: TimeInterval = 0
    private var currentCoordinate: CLLocationCoordinate2D
    private var currentHeading: Double  // degrees, 0 = north
    private var currentAltitude: Double = 45.0  // meters
    private var isPaused: Bool = false
    private var pauseStartTime: Date?
    private var totalPausedDuration: TimeInterval = 0
    private var runStartTime: Date?

    // Route variation
    private var stepsSinceLastTurn: Int = 0
    private var turnInterval: Int = 40  // steps between potential turns

    // MARK: - Init

    /// Start from a specific coordinate, or default to a Montreal location.
    init(startCoordinate: CLLocationCoordinate2D? = nil) {
        // Default: downtown Montreal (Ste-Catherine & Peel area)
        self.currentCoordinate = startCoordinate ?? CLLocationCoordinate2D(
            latitude: 45.5017,
            longitude: -73.5673
        )
        // Random initial heading
        self.currentHeading = Double.random(in: 0..<360)
    }

    // MARK: - RunDataProvider

    func start() {
        simLog.info("Simulated GPS run started at (\(self.currentCoordinate.latitude), \(self.currentCoordinate.longitude))")
        runStartTime = Date()
        totalPausedDuration = 0
        elapsedTime = 0
        totalDistanceMeters = 0
        routePoints = []
        elevationGain = 0
        elevationLoss = 0
        isPaused = false
        stepsSinceLastTurn = 0

        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        simLog.info("Simulated GPS run stopped. Distance: \(self.totalDistanceMeters)m")
        timer?.invalidate()
        timer = nil
    }

    func pause() {
        guard !isPaused else { return }
        isPaused = true
        pauseStartTime = Date()
    }

    func resume() {
        guard isPaused, let pauseStart = pauseStartTime else { return }
        totalPausedDuration += Date().timeIntervalSince(pauseStart)
        pauseStartTime = nil
        isPaused = false
    }

    // MARK: - Simulation Tick

    private func tick() {
        guard !isPaused, let startTime = runStartTime else { return }

        elapsedTime = Date().timeIntervalSince(startTime) - totalPausedDuration

        // Distance moved this tick
        let distanceDelta = speedMps * updateInterval
        totalDistanceMeters += distanceDelta

        // Move coordinate forward along current heading
        let newCoord = moveCoordinate(
            from: currentCoordinate,
            distanceMeters: distanceDelta,
            bearingDegrees: currentHeading
        )
        currentCoordinate = newCoord

        // Random route: turn at intervals to simulate following roads
        stepsSinceLastTurn += 1
        if stepsSinceLastTurn >= turnInterval {
            stepsSinceLastTurn = 0
            // Turn: mostly gentle (±15-45°), occasionally sharp (±90°)
            let turnAngle: Double
            if Double.random(in: 0...1) < 0.3 {
                // Sharp turn (intersection)
                turnAngle = Double.random(in: 0...1) < 0.5 ? 90 : -90
            } else {
                // Gentle curve (road bend)
                turnAngle = Double.random(in: -30...30)
            }
            currentHeading = (currentHeading + turnAngle).truncatingRemainder(dividingBy: 360)
            if currentHeading < 0 { currentHeading += 360 }

            // Randomize next turn interval (20-60 steps = 10-30 seconds of running)
            turnInterval = Int.random(in: 20...60)
        }

        // Simulate gentle elevation changes
        let altDelta = Double.random(in: -0.3...0.4)
        let prevAltitude = currentAltitude
        currentAltitude += altDelta
        currentAltitude = max(10, min(200, currentAltitude))  // Clamp
        if currentAltitude > prevAltitude + 0.5 {
            elevationGain += currentAltitude - prevAltitude
        } else if currentAltitude < prevAltitude - 0.5 {
            elevationLoss += prevAltitude - currentAltitude
        }

        // Add slight speed variation (±5%) for realism
        let speedVariation = speedMps * Double.random(in: 0.95...1.05)

        // Store route point
        let routePoint = RoutePoint(
            latitude: newCoord.latitude,
            longitude: newCoord.longitude,
            altitude: currentAltitude,
            timestamp: elapsedTime,
            speed: speedVariation
        )
        routePoints.append(routePoint)

        // Emit sample
        let sample = RunSample(
            timestamp: Date(),
            speedMps: speedVariation,
            totalDistanceMeters: totalDistanceMeters,
            elapsedTime: elapsedTime,
            heartRate: Int.random(in: 155...175),  // Simulated HR
            coordinate: newCoord,
            altitudeMeters: currentAltitude
        )
        DispatchQueue.main.async { [weak self] in
            self?.onRunSample?(sample)
        }
    }

    // MARK: - Coordinate Math

    /// Move a coordinate by distance (meters) along a bearing (degrees from north).
    private func moveCoordinate(
        from coord: CLLocationCoordinate2D,
        distanceMeters: Double,
        bearingDegrees: Double
    ) -> CLLocationCoordinate2D {
        let earthRadius: Double = 6_371_000 // meters
        let lat1 = coord.latitude * .pi / 180
        let lon1 = coord.longitude * .pi / 180
        let bearing = bearingDegrees * .pi / 180
        let angularDistance = distanceMeters / earthRadius

        let lat2 = asin(
            sin(lat1) * cos(angularDistance) +
            cos(lat1) * sin(angularDistance) * cos(bearing)
        )
        let lon2 = lon1 + atan2(
            sin(bearing) * sin(angularDistance) * cos(lat1),
            cos(angularDistance) - sin(lat1) * sin(lat2)
        )

        return CLLocationCoordinate2D(
            latitude: lat2 * 180 / .pi,
            longitude: lon2 * 180 / .pi
        )
    }

    // MARK: - Route Data Export

    func encodeRouteJSON() -> String? {
        guard !routePoints.isEmpty else { return nil }
        guard let data = try? JSONEncoder().encode(routePoints) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
