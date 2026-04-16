import SwiftUI
import MapboxMaps

/// Static, non-interactive route map for the post-run summary screen.
/// Shows the entire route in brand red with start/finish markers.
/// Uses Mapbox with custom 3D style at 45° pitch.
struct RouteMapView: View {
    let routeJSON: String
    let paceData: [CodableKilometerSplit]?
    var showPaceColors: Bool = false

    private var routePoints: [RoutePoint] {
        guard let data = routeJSON.data(using: .utf8),
              let points = try? JSONDecoder().decode([RoutePoint].self, from: data) else {
            return []
        }
        return points
    }

    private var coordinates: [CLLocationCoordinate2D] {
        routePoints.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private static let styleURI = StyleURI(rawValue: "mapbox://styles/choquer/cmnrp6hea002p01suci3bhyid")!

    private var routeCenter: CLLocationCoordinate2D {
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        return CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
    }

    private var routeZoom: Double {
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        let latSpan = lats.max()! - lats.min()!
        let lonSpan = lons.max()! - lons.min()!
        let maxSpan = max(latSpan, lonSpan)
        if maxSpan < 0.003 { return 18 }
        if maxSpan < 0.006 { return 17 }
        if maxSpan < 0.012 { return 16 }
        if maxSpan < 0.025 { return 15 }
        if maxSpan < 0.05 { return 14 }
        if maxSpan < 0.1 { return 13 }
        return 12
    }

    var body: some View {
        if coordinates.count >= 2 {
            Map(initialViewport: .camera(
                center: routeCenter,
                zoom: routeZoom,
                bearing: 0,
                pitch: 45
            )) {
                // Route line(s)
                if showPaceColors, !routePoints.isEmpty {
                    PolylineAnnotationGroup(speedColoredSegments()) { segment in
                        PolylineAnnotation(lineCoordinates: segment.coords)
                            .lineColor(StyleColor(segment.uiColor))
                            .lineWidth(4)
                    }
                    .lineCap(.round)
                    .lineJoin(.round)
                } else {
                    PolylineAnnotationGroup {
                        PolylineAnnotation(lineCoordinates: coordinates)
                            .lineColor(StyleColor(UIColor(Color.stridePrimary)))
                            .lineWidth(4)
                    }
                    .lineCap(.round)
                    .lineJoin(.round)
                }

                // Start marker
                if let start = coordinates.first {
                    MapViewAnnotation(coordinate: start) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    }
                    .allowOverlap(true)
                }

                // Finish marker
                if let finish = coordinates.last, coordinates.count > 1 {
                    MapViewAnnotation(coordinate: finish) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color.stridePrimary)
                            .padding(4)
                            .background(Color.white)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    }
                    .allowOverlap(true)
                }
            }
            .mapStyle(MapStyle(uri: Self.styleURI))
            .ornamentOptions(OrnamentOptions(
                scaleBar: ScaleBarViewOptions(visibility: .hidden),
                compass: CompassViewOptions(visibility: .hidden),
                logo: LogoViewOptions(margins: CGPoint(x: -10000, y: -10000)),
                attributionButton: AttributionButtonOptions(margins: CGPoint(x: -10000, y: -10000))
            ))
            .gestureOptions(GestureOptions(
                panEnabled: false,
                pinchEnabled: false,
                rotateEnabled: false,
                pitchEnabled: false,
                doubleTapToZoomInEnabled: false,
                doubleTouchToZoomOutEnabled: false,
                quickZoomEnabled: false
            ))
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.strideBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Speed-Colored Segments

    /// Nike-style coloring: slow = cool (blue/green), fast = warm (red).
    /// Uses each RoutePoint's instantaneous speed, bucketed into percentile bands
    /// so one outlier sprint doesn't wash out the whole map.
    struct SpeedSegment: Identifiable {
        let index: Int
        let coords: [CLLocationCoordinate2D]
        let uiColor: UIColor
        var id: Int { index }
    }

    /// Bucket width in meters for smoothing speed before coloring.
    private let smoothingWindowMeters: Double = 100.0

    private func speedColoredSegments() -> [SpeedSegment] {
        let points = routePoints.filter { $0.speed > 0.3 }
        guard points.count >= 2 else { return [] }

        // Compute cumulative distance for each point (cheap Haversine between
        // consecutive points). This lets us group into fixed-distance buckets
        // instead of coloring per-point.
        var cumulativeDistance: [Double] = [0]
        for i in 1..<points.count {
            let prev = points[i - 1]
            let curr = points[i]
            let d = Self.haversineDist(
                lat1: prev.latitude, lon1: prev.longitude,
                lat2: curr.latitude, lon2: curr.longitude
            )
            cumulativeDistance.append(cumulativeDistance.last! + d)
        }

        // Group points into 100m windows and average speed within each window.
        struct WindowBucket {
            var speedSum: Double = 0
            var count: Int = 0
            var avgSpeed: Double { count > 0 ? speedSum / Double(count) : 0 }
        }
        let totalDist = cumulativeDistance.last!
        let bucketCount = max(1, Int(ceil(totalDist / smoothingWindowMeters)))
        var buckets: [WindowBucket] = Array(repeating: WindowBucket(), count: bucketCount)

        for (i, pt) in points.enumerated() {
            let bucketIdx = min(Int(cumulativeDistance[i] / smoothingWindowMeters), bucketCount - 1)
            buckets[bucketIdx].speedSum += pt.speed
            buckets[bucketIdx].count += 1
        }

        // Determine color range from bucket-averaged speeds (p10..p90).
        let avgSpeeds = buckets.filter { $0.count > 0 }.map(\.avgSpeed).sorted()
        guard !avgSpeeds.isEmpty else { return [] }
        let lo = avgSpeeds[avgSpeeds.count / 10]
        let hi = avgSpeeds[min(avgSpeeds.count - 1, avgSpeeds.count * 9 / 10)]
        let range = max(hi - lo, 0.01)

        // Color each point based on its bucket's averaged speed.
        let colors: [UIColor] = points.enumerated().map { i, _ in
            let bucketIdx = min(Int(cumulativeDistance[i] / smoothingWindowMeters), bucketCount - 1)
            let avgSpd = buckets[bucketIdx].avgSpeed
            let t = min(max((avgSpd - lo) / range, 0), 1)
            return color(forSpeedT: t)
        }

        // Coalesce consecutive same-color points into polyline segments.
        var segments: [SpeedSegment] = []
        var currentCoords: [CLLocationCoordinate2D] = []
        var currentColor: UIColor = colors[0]

        for (i, point) in points.enumerated() {
            let coord = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
            if colors[i] != currentColor, currentCoords.count >= 2 {
                segments.append(SpeedSegment(index: segments.count, coords: currentCoords, uiColor: currentColor))
                currentCoords = [currentCoords.last!]
                currentColor = colors[i]
            }
            currentCoords.append(coord)
        }
        if currentCoords.count >= 2 {
            segments.append(SpeedSegment(index: segments.count, coords: currentCoords, uiColor: currentColor))
        }
        return segments
    }

    private static func haversineDist(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
            cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
            sin(dLon / 2) * sin(dLon / 2)
        return R * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Interpolate blue → green → yellow → red as t goes 0 → 1.
    private func color(forSpeedT t: Double) -> UIColor {
        // 5-stop gradient: blue, green, yellow, orange, red.
        let stops: [(Double, UIColor)] = [
            (0.00, UIColor.systemBlue),
            (0.25, UIColor.systemGreen),
            (0.55, UIColor.systemYellow),
            (0.80, UIColor.systemOrange),
            (1.00, UIColor.systemRed),
        ]
        for i in 0..<(stops.count - 1) {
            let (t0, c0) = stops[i]
            let (t1, c1) = stops[i + 1]
            if t <= t1 {
                let local = (t - t0) / (t1 - t0)
                return lerp(c0, c1, local)
            }
        }
        return stops.last!.1
    }

    private func lerp(_ a: UIColor, _ b: UIColor, _ t: Double) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let tt = CGFloat(t)
        return UIColor(
            red: ar + (br - ar) * tt,
            green: ag + (bg - ag) * tt,
            blue: ab + (bb - ab) * tt,
            alpha: aa + (ba - aa) * tt
        )
    }
}
