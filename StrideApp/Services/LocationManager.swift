import Foundation
import CoreLocation
import os.log

private let locationLog = Logger(subsystem: "com.stride.app", category: "LocationManager")

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    // MARK: - Published State
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?
    @Published var isTracking: Bool = false

    /// Callback fired for each valid filtered location during tracking.
    var onLocationUpdate: ((CLLocation) -> Void)?

    // MARK: - Private
    private let manager = CLLocationManager()
    private var lastValidLocation: CLLocation?

    /// Maximum acceptable horizontal accuracy (meters). Reject noisy GPS fixes.
    private let maxAccuracy: CLLocationAccuracy = 20.0

    /// Minimum distance between updates (meters). Reduces noise + saves battery.
    private let distanceFilter: CLLocationDistance = 5.0

    // MARK: - Init

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = distanceFilter
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        authorizationStatus = manager.authorizationStatus
    }

    // MARK: - Public API

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func requestAlwaysPermission() {
        manager.requestAlwaysAuthorization()
    }

    func startTracking() {
        guard !isTracking else { return }
        locationLog.info("Starting location tracking")
        lastValidLocation = nil
        isTracking = true
        manager.startUpdatingLocation()
    }

    func stopTracking() {
        guard isTracking else { return }
        locationLog.info("Stopping location tracking")
        isTracking = false
        manager.stopUpdatingLocation()
        lastValidLocation = nil
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            // Filter: reject inaccurate fixes
            guard location.horizontalAccuracy >= 0,
                  location.horizontalAccuracy <= maxAccuracy else {
                locationLog.debug("Rejected location: accuracy \(location.horizontalAccuracy)m")
                continue
            }

            // Filter: reject stale locations (older than 10 seconds)
            guard abs(location.timestamp.timeIntervalSinceNow) < 10 else {
                locationLog.debug("Rejected stale location: \(location.timestamp)")
                continue
            }

            // Filter: reject negative speed (GPS noise indicator)
            if location.speed < 0 {
                // CLLocation.speed = -1 means invalid; still accept the coordinate for route drawing
                // but don't trust the speed value
            }

            DispatchQueue.main.async {
                self.currentLocation = location
                self.lastValidLocation = location
                self.onLocationUpdate?(location)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationLog.error("Location error: \(error.localizedDescription)")
    }
}
