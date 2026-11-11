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

    /// Below this Doppler speed (m/s) the runner is treated as stationary and no
    /// distance is banked. 0.5 m/s is ~1.8 km/h — well under any walk.
    private let stationarySpeedThreshold: Double = 0.5

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

            if location.speed >= 0 && location.speed < stationarySpeedThreshold {
                // Doppler says we aren't moving. Holding the anchor below lets
                // position noise random-walk past the jitter floor and bank
                // phantom metres while standing at a light, so re-anchor on the
                // spot instead. (Advancing the anchor every fix used to make
                // this impossible — it's the cost of the fix below.)
                lastLocation = location
            } else if segmentDistance > maximumPlausibleDistance {
                // Teleport — the chord is nonsense, but time really passed. Credit
                // the Doppler speed over the interval instead of dropping it.
                let dopplerDistance = min(rawSpeed * segmentDuration, maximumPlausibleDistance)
                totalDistanceMeters += dopplerDistance
                gpsLog.debug("Teleport \(segmentDistance)m over \(segmentDuration)s — credited \(dopplerDistance)m from speed")
                lastLocation = location
            } else if segmentDistance >= jitterFloor {
                totalDistanceMeters += segmentDistance
                lastLocation = location
            } else {
                // Below the jitter floor this fix is indistinguishable from noise,
                // so we can't bank it — but the ground it covers is real. HOLD the
                // anchor so the next fix measures displacement accumulated since
                // the last banked point and clears the floor on its own.
                //
                // This previously advanced the anchor anyway, which silently
                // deleted those metres for good. With a 5 m distanceFilter that
                // was several metres lost every time accuracy sagged — the bulk
                // of the ~9% shortfall against Fitbit.
                gpsLog.debug("Sub-jitter segment \(segmentDistance)m — holding anchor")
            }
        } else {
            lastLocation = location
        }

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
