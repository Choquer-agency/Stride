import Foundation
import CoreLocation

// MARK: - Unified Run Sample (data-source agnostic)

struct RunSample {
    let timestamp: Date
    let speedMps: Double?                    // meters per second
    let totalDistanceMeters: Double?         // cumulative distance
    let elapsedTime: TimeInterval?           // seconds since run start
    let heartRate: Int?                      // bpm (optional)
    let coordinate: CLLocationCoordinate2D?  // nil for treadmill
    let altitudeMeters: Double?              // nil for treadmill
}

// MARK: - Run Data Provider Protocol

protocol RunDataProvider: AnyObject {
    /// Callback fired on each new data sample.
    var onRunSample: ((RunSample) -> Void)? { get set }

    /// Identifies the data source: "bluetooth_ftms", "gps", "manual"
    var dataSourceType: String { get }

    /// Human-readable device name (e.g. treadmill brand). Nil for GPS.
    var deviceName: String? { get }

    /// Start emitting data samples.
    func start()

    /// Stop emitting data samples and clean up.
    func stop()

    /// Pause data collection (timer, distance accumulation).
    func pause()

    /// Resume data collection after a pause.
    func resume()
}
