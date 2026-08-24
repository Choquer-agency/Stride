import SwiftUI
import Charts

/// Heart-rate profile chart for the post-run summary — BPM over elapsed run
/// time, with avg/max in the header. Rendered whenever the run recorded HR
/// samples (BLE watch broadcast or FTMS console), for both outdoor and
/// treadmill runs. Modeled on ElevationProfileView.
struct HeartRateGraphView: View {
    let hrSamplesJSON: String
    let avgHeartRate: Int?
    let maxHeartRate: Int?

    private var samples: [CodableHRSample] {
        guard let data = hrSamplesJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([CodableHRSample].self, from: data) else {
            return []
        }
        // Downsample for chart performance (max 240 points)
        if decoded.count > 240 {
            let step = decoded.count / 240
            return stride(from: 0, to: decoded.count, by: step).map { decoded[$0] }
        }
        return decoded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("Heart Rate")
                    .font(.inter(size: 14, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                if let avg = avgHeartRate {
                    HStack(spacing: 2) {
                        Text("AVG")
                            .font(.inter(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text("\(avg)")
                            .font(.barlowCondensed(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                    }
                }

                if let maxHR = maxHeartRate {
                    HStack(spacing: 2) {
                        Text("MAX")
                            .font(.inter(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text("\(maxHR)")
                            .font(.barlowCondensed(size: 14, weight: .medium))
                            .foregroundColor(Color.stridePrimary)
                    }
                }
            }

            // Chart
            let data = samples
            if data.count >= 2 {
                Chart {
                    ForEach(Array(data.enumerated()), id: \.offset) { _, sample in
                        AreaMark(
                            x: .value("Time", sample.t / 60.0),
                            y: .value("BPM", sample.bpm)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.stridePrimary.opacity(0.3), Color.stridePrimary.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Time", sample.t / 60.0),
                            y: .value("BPM", sample.bpm)
                        )
                        .foregroundStyle(Color.stridePrimary)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }

                    if let avg = avgHeartRate {
                        RuleMark(y: .value("Avg", avg))
                            .foregroundStyle(Color.secondary.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisValueLabel {
                            if let mins = value.as(Double.self) {
                                Text("\(Int(mins))m")
                                    .font(.barlowCondensed(size: 11, weight: .medium))
                            }
                        }
                        AxisGridLine()
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { value in
                        AxisValueLabel {
                            if let bpm = value.as(Int.self) {
                                Text("\(bpm)")
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
}
