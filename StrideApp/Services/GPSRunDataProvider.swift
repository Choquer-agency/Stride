import Foundation
import CoreLocation
import os.log

private let gpsLog = Logger(subsystem: "com.stride.app", category: "GPSRunDataProvider")

/// Provides RunSample data from GPS/CoreLocation for outdoor runs.
/// Manages its own elapsed time (with pause/resume) and accumulates distance from CLLocation updates.
final class GPSRunDataProvider: RunDataProvider {
    var onRunSample: ((RunSample) -> Void)?
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
        // Don't accumulate distance or emit samples while paused
        guard !isPaused else { return }

        guard let startTime = runStartTime else { return }

        // Elapsed time excluding paused intervals
        let elapsedTime = Date().timeIntervalSince(startTime) - totalPausedDuration

        // Accumulate distance from previous valid location
        if let last = lastLocation {
            let delta = location.distance(from: last)
            // Sanity check: reject jumps > 100m between updates (GPS teleportation)
            if delta < 100 {
                totalDistanceMeters += delta
            } else {
                gpsLog.warning("Rejected GPS jump: \(delta)m")
            }
        }
        lastLocation = location

        // Elevation tracking (smoothed with 3m threshold to reduce GPS altitude noise)
        let altitude = location.altitude
        if let lastAlt = lastAltitude {
            let altDelta = altitude - lastAlt
            if altDelta > 3.0 {
                elevationGain += altDelta
                lastAltitude = altitude
            } else if altDelta < -3.0 {
                elevationLoss += abs(altDelta)
                lastAltitude = altitude
            }
            // Within ±3m threshold: don't update lastAltitude (dead zone filter)
        } else {
            lastAltitude = altitude
        }

        // Compute speed: prefer CLLocation.speed if valid, otherwise derive from distance/time
        let speedMps: Double
        if location.speed >= 0 {
            speedMps = location.speed
        } else if let last = lastLocation, elapsedTime > 0 {
            let timeDelta = location.timestamp.timeIntervalSince(last.timestamp)
            let distDelta = location.distance(from: last)
            speedMps = timeDelta > 0 ? distDelta / timeDelta : 0
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
