import SwiftUI
import Charts

/// Elevation profile chart for post-run summary. Shows altitude over distance with gradient fill.
struct ElevationProfileView: View {
    let routeJSON: String
    let elevationGain: Double?
    let elevationLoss: Double?

    private var profileData: [(distance: Double, altitude: Double)] {
        guard let data = routeJSON.data(using: .utf8),
              let points = try? JSONDecoder().decode([RoutePoint].self, from: data) else {
            return []
        }

        // Build cumulative distance and collect altitudes
        var result: [(distance: Double, altitude: Double)] = []
        var cumulativeDistance: Double = 0

        for i in 0..<points.count {
            if i > 0 {
                let prev = points[i - 1]
                let curr = points[i]
                let dx = curr.latitude - prev.latitude
                let dy = curr.longitude - prev.longitude
                // Rough distance in meters (good enough for chart x-axis)
                let delta = sqrt(dx * dx + dy * dy) * 111_139
                cumulativeDistance += delta
            }

            result.append((distance: cumulativeDistance / 1000.0, altitude: points[i].altitude))
        }

        // Downsample for chart performance (max 200 points)
        if result.count > 200 {
            let step = result.count / 200
            return stride(from: 0, to: result.count, by: step).map { result[$0] }
        }

        // 5-point moving average to smooth GPS altitude noise
        return smoothAltitudes(result, windowSize: 5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("Elevation")
                    .font(.inter(size: 14, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                if let gain = elevationGain {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                        Text("\(Int(gain))m")
                            .font(.barlowCondensed(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                    }
                }

                if let loss = elevationLoss {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color.stridePrimary)
                        Text("\(Int(loss))m")
                            .font(.barlowCondensed(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                    }
                }
            }

            // Chart
            let data = profileData
            if data.count >= 2 {
                Chart {
                    ForEach(Array(data.enumerated()), id: \.offset) { _, point in
                        AreaMark(
                            x: .value("Distance", point.distance),
                            y: .value("Altitude", point.altitude)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.stridePrimary.opacity(0.3), Color.stridePrimary.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Distance", point.distance),
                            y: .value("Altitude", point.altitude)
                        )
                        .foregroundStyle(Color.stridePrimary)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisValueLabel {
                            if let km = value.as(Double.self) {
                                Text(String(format: "%.1f", km))
                                    .font(.barlowCondensed(size: 11, weight: .medium))
                            }
                        }
                        AxisGridLine()
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { value in
                        AxisValueLabel {
                            if let alt = value.as(Double.self) {
                                Text("\(Int(alt))m")
                                    .font(.barlowCondensed(size: 11, weight: .medium))
                            }
                        }
                        AxisGridLine()
                    }
                }
                .frame(height: 120)
            }
        }
        .padding(16)
        .background(Color.strideCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.strideBorder, lineWidth: 1)
        )
    }

    // MARK: - Smoothing

    private func smoothAltitudes(_ data: [(distance: Double, altitude: Double)], windowSize: Int) -> [(distance: Double, altitude: Double)] {
        guard data.count > windowSize else { return data }
        let half = windowSize / 2
        return data.enumerated().map { i, point in
            let start = max(0, i - half)
            let end = min(data.count - 1, i + half)
            let windowAltitudes = data[start...end].map(\.altitude)
            let avg = windowAltitudes.reduce(0, +) / Double(windowAltitudes.count)
            return (distance: point.distance, altitude: avg)
        }
    }
}
