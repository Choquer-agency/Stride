import Foundation
import CoreLocation
import os.log

private let gpsLog = Logger(subsystem: "com.stride.app", category: "GPSRunDataProvider")

/// Provides RunSample data from GPS/CoreLocation for outdoor runs.
/// Manages its own elapsed time (with pause/resume) and accumulates distance from CLLocation updates.
final class GPSRunDataProvider: RunDataProvider {
    var onRunSample: ((RunSample) -> Void)?
    /// Raw speed signal that fires on every GPS update — *including while paused* —
    /// so AutoPauseService can detect resume. Regular `onRunSample` is gated by pause.
    var onSpeedTick: ((Double) -> Void)?
    let dataSourceType: String = "gps"
    let deviceName: String? = nil

    // MARK: - Route Data (accessible after run for saving)

    /// All valid route points collected during the run.
    private(set) var routePoints: [RoutePoint] = []

    /// Total elevation gained (meters), computed from altitude deltas.
    private(set) var elevationGain: Double = 0

    /// Total elevation lost (meters), computed from altitude deltas.
    private(set) var elevationLoss: Double = 0

    // MARK: - Private State

    private let locationManager: LocationManager
    private var totalDistanceMeters: Double = 0
    private var lastLocation: CLLocation?
    private var lastAltitude: Double?
    private var filteredAltitude: Double?

    // Timer management
    private var runStartTime: Date?
    private var totalPausedDuration: TimeInterval = 0
    private var pauseStartTime: Date?
    private var isPaused: Bool = false

    // MARK: - Init

    init(locationManager: LocationManager) {
        self.locationManager = locationManager
    }

    // MARK: - RunDataProvider

    func start() {
        gpsLog.info("GPS run started")
        runStartTime = Date()
        totalPausedDuration = 0
        pauseStartTime = nil
        isPaused = false
        totalDistanceMeters = 0
        lastLocation = nil
        lastAltitude = nil
        filteredAltitude = nil
        routePoints = []
        elevationGain = 0
        elevationLoss = 0

        locationManager.onLocationUpdate = { [weak self] location in
            self?.handleLocation(location)
        }
        locationManager.startTracking()
    }

    func stop() {
        gpsLog.info("GPS run stopped. Distance: \(self.totalDistanceMeters)m, Elevation +\(self.elevationGain)m / -\(self.elevationLoss)m")
        locationManager.onLocationUpdate = nil
        locationManager.stopTracking()
    }

    func pause() {
        guard !isPaused else { return }
        isPaused = true
        pauseStartTime = Date()
        gpsLog.info("GPS run paused")
    }

    func resume() {
        guard isPaused, let pauseStart = pauseStartTime else { return }
        totalPausedDuration += Date().timeIntervalSince(pauseStart)
        pauseStartTime = nil
        isPaused = false
        // Clear lastLocation so we don't accumulate distance during the pause gap
        lastLocation = nil
        gpsLog.info("GPS run resumed. Total paused: \(self.totalPausedDuration)s")
    }

    // MARK: - Location Handling

    private func handleLocation(_ location: CLLocation) {
        // Emit raw speed before the pause gate so auto-resume detection still fires
        // while paused. Invalid GPS speeds (< 0) report as 0 → runner still "stopped".
        let rawSpeed = location.speed >= 0 ? location.speed : 0
        onSpeedTick?(rawSpeed)

        // Don't accumulate distance or emit samples while paused
        guard !isPaused else { return }

        guard let startTime = runStartTime else { return }

        // Use the sensor timestamp so delayed/batched Core Location callbacks do not
        // inflate elapsed time or make distance and pace disagree.
        let elapsedTime = max(0, location.timestamp.timeIntervalSince(startTime) - totalPausedDuration)

        let previousLocation = lastLocation
        let segmentDistance = previousLocation.map { location.distance(from: $0) } ?? 0
        let segmentDuration = previousLocation.map { location.timestamp.timeIntervalSince($0.timestamp) } ?? 0

        // Accumulate distance from previous valid location
        if let last = previousLocation, segmentDuration > 0 {
            // Accuracy-aware jitter floor plus a speed-based teleport ceiling.
            let jitterFloor = max(1.5, min(5, (location.horizontalAccuracy + last.horizontalAccuracy) * 0.12))
            let maximumPlausibleDistance = max(25, segmentDuration * 8 + location.horizontalAccuracy)
            if segmentDistance >= jitterFloor && segmentDistance <= maximumPlausibleDistance {
                totalDistanceMeters += segmentDistance
            } else {
                gpsLog.debug("Rejected GPS segment: \(segmentDistance)m over \(segmentDuration)s")
            }
        }
        lastLocation = location

        // Low-pass altitude before accumulating gain/loss or feeding route coaching.
        // Poor vertical fixes get less influence than good fixes.
        let verticalAccuracy = location.verticalAccuracy
        let alpha = verticalAccuracy >= 0 && verticalAccuracy <= 8 ? 0.25 : 0.10
        let altitude = filteredAltitude.map { $0 + alpha * (location.altitude - $0) } ?? location.altitude
        filteredAltitude = altitude
        if let lastAlt = lastAltitude {
            let altDelta = altitude - lastAlt
            if abs(altDelta) >= 2.5 {
                if altDelta > 0 {
                    elevationGain += altDelta
                } else {
                    elevationLoss += abs(altDelta)
                }
                lastAltitude = altitude
            }
        } else {
            lastAltitude = altitude
        }

        // Compute speed: prefer CLLocation.speed if valid, otherwise derive from distance/time
        let speedMps: Double
        if location.speed >= 0 {
            speedMps = location.speed
        } else if previousLocation != nil, segmentDuration > 0 {
            speedMps = segmentDistance / segmentDuration
        } else {
            speedMps = 0
        }

        // Store route point
        let routePoint = RoutePoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: altitude,
            timestamp: elapsedTime,
            speed: speedMps
        )
        routePoints.append(routePoint)

        // Emit unified sample
        let sample = RunSample(
            timestamp: location.timestamp,
            speedMps: speedMps,
            totalDistanceMeters: totalDistanceMeters,
            elapsedTime: elapsedTime,
            heartRate: nil,
            coordinate: location.coordinate,
            altitudeMeters: altitude
        )
        onRunSample?(sample)
    }

    // MARK: - Route Data Export

    /// Encode route points to JSON string for storage in RunLog.routeJSON
    func encodeRouteJSON() -> String? {
        guard !routePoints.isEmpty else { return nil }
        guard let data = try? JSONEncoder().encode(routePoints) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
