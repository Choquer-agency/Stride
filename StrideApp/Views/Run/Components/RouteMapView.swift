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
                logo: LogoViewOptions(visibility: .hidden),
                attributionButton: AttributionButtonOptions(visibility: .hidden)
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

    private func speedColoredSegments() -> [SpeedSegment] {
        let points = routePoints.filter { $0.speed > 0.3 }  // drop stationary noise
        guard points.count >= 2 else { return [] }

        // Bucket by speed percentile (p10..p90) so extremes don't skew the gradient.
        let sortedSpeeds = points.map(\.speed).sorted()
        let lo = sortedSpeeds[sortedSpeeds.count / 10]
        let hi = sortedSpeeds[min(sortedSpeeds.count - 1, sortedSpeeds.count * 9 / 10)]
        let range = max(hi - lo, 0.01)

        // Color for each point, then coalesce consecutive same-color points into one polyline.
        let colors: [UIColor] = points.map { point in
            let t = min(max((point.speed - lo) / range, 0), 1)
            return color(forSpeedT: t)
        }

        var segments: [SpeedSegment] = []
        var currentCoords: [CLLocationCoordinate2D] = []
        var currentColor: UIColor = colors[0]

        for (i, point) in points.enumerated() {
            let coord = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
            if colors[i] != currentColor, currentCoords.count >= 2 {
                segments.append(SpeedSegment(index: segments.count, coords: currentCoords, uiColor: currentColor))
                currentCoords = [currentCoords.last!]  // stitch to the next segment
                currentColor = colors[i]
            }
            currentCoords.append(coord)
        }
        if currentCoords.count >= 2 {
            segments.append(SpeedSegment(index: segments.count, coords: currentCoords, uiColor: currentColor))
        }
        return segments
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
