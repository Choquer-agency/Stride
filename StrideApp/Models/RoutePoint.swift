import Foundation

/// A single GPS coordinate along a run route, stored as JSON in RunLog.routeJSON.
struct RoutePoint: Codable {
    let latitude: Double
    let longitude: Double
    let altitude: Double       // meters above sea level
    let timestamp: TimeInterval // seconds since run start
    let speed: Double          // m/s at this point
}
