import SwiftUI
import MapboxMaps

/// Generates a shareable route card image from run results.
/// Uses Mapbox Snapshotter for map rendering (Metal-based Map view can't be captured by ImageRenderer).
struct RouteShareService {
    private static let styleURI = StyleURI(rawValue: "mapbox://styles/choquer/cmnrp6hea002p01suci3bhyid")!

    /// Generate a shareable image combining the route map snapshot with run stats.
    @MainActor
    static func generateShareImage(result: RunResult) async -> UIImage? {
        var mapSnapshot: UIImage? = nil

        if let routeJSON = result.routeJSON {
            mapSnapshot = await generateMapSnapshot(routeJSON: routeJSON)
        }

        let view = ShareCardView(result: result, mapSnapshot: mapSnapshot)
        let renderer = ImageRenderer(content: view)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }

    /// Generate a static map image using Mapbox Snapshotter
    private static func generateMapSnapshot(routeJSON: String) async -> UIImage? {
        guard let data = routeJSON.data(using: .utf8),
              let points = try? JSONDecoder().decode([RoutePoint].self, from: data) else {
            return nil
        }

        let coordinates = points.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        guard coordinates.count >= 2 else { return nil }

        let options = MapSnapshotOptions(
            size: CGSize(width: 360, height: 200),
            pixelRatio: UIScreen.main.scale
        )

        let snapshotter = Snapshotter(options: options)
        snapshotter.style.uri = styleURI

        // Compute camera to fit the route with padding and 45° pitch
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return nil }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        // Estimate zoom level from coordinate span
        let latSpan = maxLat - minLat
        let lonSpan = maxLon - minLon
        let maxSpan = max(latSpan, lonSpan)
        let zoom: Double
        if maxSpan < 0.005 { zoom = 16 }
        else if maxSpan < 0.01 { zoom = 15 }
        else if maxSpan < 0.02 { zoom = 14 }
        else if maxSpan < 0.05 { zoom = 13 }
        else if maxSpan < 0.1 { zoom = 12 }
        else { zoom = 11 }

        let camera = CameraOptions(
            center: center,
            padding: UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30),
            zoom: zoom,
            bearing: 0,
            pitch: 45
        )
        snapshotter.setCamera(to: camera)

        return await withCheckedContinuation { continuation in
            snapshotter.start(overlayHandler: { overlayContext in
                // Draw route line on the snapshot overlay
                let context = overlayContext.context
                context.setStrokeColor(UIColor(Color.stridePrimary).cgColor)
                context.setLineWidth(3)
                context.setLineCap(.round)
                context.setLineJoin(.round)

                let points = coordinates.compactMap { coord in
                    overlayContext.pointForCoordinate(coord)
                }

                guard points.count >= 2 else { return }
                context.move(to: points[0])
                for point in points.dropFirst() {
                    context.addLine(to: point)
                }
                context.strokePath()

                // Draw start marker (green circle)
                if let startPoint = points.first {
                    context.setFillColor(UIColor.systemGreen.cgColor)
                    context.fillEllipse(in: CGRect(
                        x: startPoint.x - 5,
                        y: startPoint.y - 5,
                        width: 10,
                        height: 10
                    ))
                    context.setStrokeColor(UIColor.white.cgColor)
                    context.setLineWidth(2)
                    context.strokeEllipse(in: CGRect(
                        x: startPoint.x - 5,
                        y: startPoint.y - 5,
                        width: 10,
                        height: 10
                    ))
                }

                // Draw finish marker (red circle)
                if let endPoint = points.last, points.count > 1 {
                    context.setFillColor(UIColor(Color.stridePrimary).cgColor)
                    context.fillEllipse(in: CGRect(
                        x: endPoint.x - 5,
                        y: endPoint.y - 5,
                        width: 10,
                        height: 10
                    ))
                    context.setStrokeColor(UIColor.white.cgColor)
                    context.setLineWidth(2)
                    context.strokeEllipse(in: CGRect(
                        x: endPoint.x - 5,
                        y: endPoint.y - 5,
                        width: 10,
                        height: 10
                    ))
                }
            }) { result in
                switch result {
                case .success(let image):
                    continuation.resume(returning: image)
                case .failure:
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - Share Card View (rendered to image)

private struct ShareCardView: View {
    let result: RunResult
    let mapSnapshot: UIImage?

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("STRIDE")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color.stridePrimary)
                        .tracking(2)
                    Text(formattedDate)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if result.isOutdoorRun {
                    Image(systemName: "location.fill")
                        .foregroundColor(Color.stridePrimary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            // Route map snapshot
            if let mapSnapshot = mapSnapshot {
                Image(uiImage: mapSnapshot)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
            }

            // Stats row
            HStack(spacing: 0) {
                statColumn(value: result.distanceDisplay, unit: "km")
                statColumn(value: result.avgPaceDisplay, unit: "/km")
                statColumn(value: result.durationDisplay, unit: "time")
            }
            .padding(.horizontal, 20)

            // Elevation (if available)
            if let gain = result.elevationGainMeters, let loss = result.elevationLossMeters {
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                        Text("\(Int(gain))m")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color.stridePrimary)
                        Text("\(Int(loss))m")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
            }

            Spacer().frame(height: 8)
        }
        .frame(width: 360)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
    }

    private func statColumn(value: String, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .default))
                .foregroundColor(.primary)
            Text(unit)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d yyyy"
        return formatter.string(from: Date())
    }
}
