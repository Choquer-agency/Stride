import SwiftUI
import Charts

/// Heart-rate profile chart for the post-run summary — BPM over elapsed run
/// time, with avg/max in the header. Rendered whenever the run recorded HR
/// samples (BLE watch broadcast or FTMS console), for both outdoor and
/// treadmill runs. Modeled on ElevationProfileView.
struct HeartRateGraphView: View {
    @AppStorage(RunLobbyAppearance.storageKey) private var appearanceRaw = RunLobbyAppearance.black.rawValue
    private var style: StridePageStyle { .init(appearance: RunLobbyAppearance(rawValue: appearanceRaw) ?? .black) }
    let hrSamplesJSON: String
    let avgHeartRate: Int?
    let maxHeartRate: Int?
    var duration: TimeInterval? = nil
    var targetRange: ClosedRange<Int>? = nil

    private let plotData: [CGPoint]
    private let hrDomain: ClosedRange<Double>

    init(hrSamplesJSON: String, avgHeartRate: Int?, maxHeartRate: Int?,
         duration: TimeInterval? = nil, targetRange: ClosedRange<Int>? = nil) {
        self.hrSamplesJSON = hrSamplesJSON
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.duration = duration
        self.targetRange = targetRange
        let prepared = RunTimelineData.heartRate(json: hrSamplesJSON, target: targetRange)
        self.plotData = prepared.points
        self.hrDomain = prepared.domain
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("HEART RATE")
                    .font(.barlowCondensed(size: 23))
                    .foregroundStyle(style.ink)

                Spacer()

                if let avg = avgHeartRate {
                    HStack(spacing: 2) {
                        Text("AVG")
                            .font(.runEyebrow(10))
                            .foregroundStyle(style.muted)
                        Text("\(avg)")
                            .font(.barlowCondensed(size: 14, weight: .medium))
                            .foregroundStyle(style.ink)
                    }
                }

                if let maxHR = maxHeartRate {
                    HStack(spacing: 2) {
                        Text("MAX")
                            .font(.runEyebrow(10))
                            .foregroundStyle(style.muted)
                        Text("\(maxHR)")
                            .font(.barlowCondensed(size: 14, weight: .medium))
                            .foregroundColor(Color.heartRatePink)
                    }
                }
            }

            // Chart
            let data = plotData
            if data.count >= 2 {
                Chart {
                    ForEach(Array(data.enumerated()), id: \.offset) { _, sample in
                        AreaMark(
                            x: .value("Time", Double(sample.x)),
                            yStart: .value("Baseline", hrDomain.lowerBound),
                            yEnd: .value("BPM", Double(sample.y))
                        )
                        .interpolationMethod(.catmullRom(alpha: 0.5))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.heartRatePink.opacity(0.3), Color.heartRatePink.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Time", Double(sample.x)),
                            y: .value("BPM", Double(sample.y))
                        )
                        .interpolationMethod(.catmullRom(alpha: 0.5))
                        .foregroundStyle(Color.heartRatePink)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }

                    if let targetRange {
                        RuleMark(y: .value("Target low", targetRange.lowerBound))
                            .foregroundStyle(Color.heartRatePink.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        RuleMark(y: .value("Target high", targetRange.upperBound))
                            .foregroundStyle(Color.heartRatePink.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    if let avg = avgHeartRate {
                        RuleMark(y: .value("Avg", avg))
                            .foregroundStyle(Color.secondary.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .chartXScale(domain: 0...max((duration ?? (data.last.map { Double($0.x) * 60 }) ?? 0) / 60, 0.01))
                .chartYScale(domain: hrDomain)
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
        .stridePageCard(style, radius: 20)
    }
}


extension Color {
    static let heartRatePink = Color(red: 0.94, green: 0.48, blue: 0.64)
}

struct LiveHeartRateLabel: View {
    let bpm: Int?
    var tint: Color = .heartRatePink

    var body: some View {
        Label(bpm.map { "\($0) bpm" } ?? "— bpm", systemImage: "heart.fill")
            .font(.inter(size: 14, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .accessibilityLabel(bpm.map { "Current heart rate \($0) beats per minute" } ?? "Heart rate unavailable")
    }
}

/// Complete speed history, including stops, rather than the live 500 m window.
struct RunSpeedGraphView: View {
    @AppStorage(RunLobbyAppearance.storageKey) private var appearanceRaw = RunLobbyAppearance.black.rawValue
    private var style: StridePageStyle { .init(appearance: RunLobbyAppearance(rawValue: appearanceRaw) ?? .black) }
    let samples: [RunSpeedSample]
    let duration: TimeInterval
    var targetSpeedRange: ClosedRange<Double>? = nil

    private let plotData: [CGPoint]
    private let speedDomain: ClosedRange<Double>
    private let endMinute: Double

    init(samples: [RunSpeedSample], duration: TimeInterval, targetSpeedRange: ClosedRange<Double>? = nil) {
        self.samples = samples
        self.duration = duration
        self.targetSpeedRange = targetSpeedRange
        let prepared = RunTimelineData.speed(samples: samples, target: targetSpeedRange)
        self.plotData = prepared.points
        self.speedDomain = prepared.domain
        self.endMinute = max(duration.isFinite ? duration / 60 : 0, prepared.points.last.map { Double($0.x) } ?? 0, 0.01)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SPEED")
                    .font(.barlowCondensed(size: 23))
                    .foregroundStyle(style.ink)
                Spacer()
                Text("km/h")
                    .font(.runEyebrow(10))
                    .foregroundStyle(style.muted)
            }
            Chart {
                if let targetSpeedRange {
                    RuleMark(y: .value("Target low", targetSpeedRange.lowerBound))
                        .foregroundStyle(Color.blue.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    RuleMark(y: .value("Target high", targetSpeedRange.upperBound))
                        .foregroundStyle(Color.blue.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                ForEach(Array(plotData.enumerated()), id: \.offset) { _, sample in
                    AreaMark(x: .value("Time", Double(sample.x)),
                             yStart: .value("Baseline", speedDomain.lowerBound), yEnd: .value("Speed", Double(sample.y)))
                        .interpolationMethod(.catmullRom(alpha: 0.5))
                        .foregroundStyle(LinearGradient(
                            colors: [Color.stridePrimary.opacity(0.3), Color.stridePrimary.opacity(0.05)],
                            startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Time", Double(sample.x)), y: .value("Speed", Double(sample.y)))
                        .interpolationMethod(.catmullRom(alpha: 0.5))
                        .foregroundStyle(Color.stridePrimary)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
            .chartXScale(domain: 0...endMinute)
            .chartYScale(domain: speedDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let minutes = value.as(Double.self) {
                            Text("\(Int(minutes))m").font(.barlowCondensed(size: 11, weight: .medium))
                        }
                    }
                    AxisGridLine()
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisValueLabel().font(.barlowCondensed(size: 11, weight: .medium))
                    AxisGridLine()
                }
            }
            .frame(height: 120)
        }
        .padding(16)
        .stridePageCard(style, radius: 20)
    }
}


/// Prepare a bounded timeline once per chart, rather than parsing/sorting once per mark.
enum RunTimelineData {
    struct Prepared {
        let points: [CGPoint]
        let domain: ClosedRange<Double>
    }

    private static func reduced(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 240 else { return points }
        let step = Int(ceil(Double(points.count) / 239))
        var result = stride(from: 0, to: points.count - 1, by: step).map { points[$0] }
        result.append(points[points.count - 1])
        return result
    }

    static func heartRate(json: String, target: ClosedRange<Int>?) -> Prepared {
        let decoded = json.data(using: .utf8).flatMap { try? JSONDecoder().decode([CodableHRSample].self, from: $0) } ?? []
        let samples = decoded.filter { $0.t.isFinite && $0.t >= 0 && $0.bpm > 0 }.sorted { $0.t < $1.t }
        let low = min(samples.map(\.bpm).min() ?? 130, target?.lowerBound ?? Int.max)
        let high = max(samples.map(\.bpm).max() ?? 160, target?.upperBound ?? 0)
        let points = reduced(samples.map { CGPoint(x: $0.t / 60, y: Double($0.bpm)) })
        return Prepared(points: RunGraphPath.displayPoints(points, bucketWidth: 0.001),
            domain: max(0, Double(low) - 8)...max(Double(high) + 8, Double(low) + 1))
    }

    static func speed(samples: [RunSpeedSample], target: ClosedRange<Double>?) -> Prepared {
        let valid = samples.filter { $0.t.isFinite && $0.t >= 0 && $0.kmh.isFinite && $0.kmh >= 0 }.sorted { $0.t < $1.t }
        let low = min(valid.map(\.kmh).min() ?? 0, target?.lowerBound ?? .infinity)
        let high = max(valid.map(\.kmh).max() ?? 1, target?.upperBound ?? 0)
        let points = reduced(valid.map { CGPoint(x: $0.t / 60, y: $0.kmh) })
        return Prepared(points: RunGraphPath.displayPoints(points, bucketWidth: 0.001),
            domain: max(0, low - 0.5)...max(high + 0.5, low + 1))
    }
}

/// Historical run charts share elapsed minutes so the same horizontal position
/// means the same moment in each chart, even when a sensor has gaps.
struct RunReviewCharts: View {
    let run: RunLog
    let splits: [CodableKilometerSplit]
    @AppStorage(RunLobbyAppearance.storageKey) private var appearanceRaw = RunLobbyAppearance.black.rawValue
    private var style: StridePageStyle { .init(appearance: RunLobbyAppearance(rawValue: appearanceRaw) ?? .black) }

    private struct Point: Identifiable {
        let x: Double
        let y: Double
        var id: Double { x }
    }

    private var route: [RoutePoint] {
        guard let data = run.routeJSON?.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([RoutePoint].self, from: data)) ?? []
    }

    private var speeds: [RunSpeedSample] {
        if run.dataSource == "bluetooth_ftms", let data = run.speedSamplesJSON?.data(using: .utf8) {
            return (try? JSONDecoder().decode([RunSpeedSample].self, from: data)) ?? []
        }
        return route.map { RunSpeedSample(t: $0.timestamp, kmh: $0.speed * 3.6) }
    }

    private var pacePoints: [Point] {
        let valid = speeds.filter { $0.t.isFinite && $0.t >= 0 && $0.kmh.isFinite && $0.kmh >= 4 && $0.kmh <= 40 }
            .sorted { $0.t < $1.t }
        if valid.count >= 2 {
            let paces = valid.map { 60 / $0.kmh }
            return downsample(valid.enumerated().map { index, sample in
                // Five-reading moving average removes single GPS spikes without
                // changing the underlying recorded data.
                let low = max(0, index - 2), high = min(valid.count - 1, index + 2)
                let average = paces[low...high].reduce(0, +) / Double(high - low + 1)
                return Point(x: sample.t / 60, y: -average)
            })
        }
        // Older runs may have only kilometer splits; still show their pace.
        return splits.compactMap { split -> Point? in
            guard let end = RunHistoryMetrics.elapsedSeconds(split.time),
                  let pace = RunHistoryMetrics.elapsedSeconds(split.pace), pace > 0 else { return nil }
            return Point(x: end / 60, y: -pace / 60)
        }
    }

    private var elevationPoints: [Point] {
        downsample(route.filter { $0.timestamp.isFinite && $0.timestamp >= 0 && $0.altitude.isFinite }
            .sorted { $0.timestamp < $1.timestamp }
            .map { Point(x: $0.timestamp / 60, y: $0.altitude) })
    }

    private var inclinePoints: [Point] {
        guard let data = run.inclineSamplesJSON?.data(using: .utf8),
              let samples = try? JSONDecoder().decode([RunInclineSample].self, from: data) else { return [] }
        return downsample(samples.filter { $0.t.isFinite && $0.t >= 0 && $0.percent.isFinite }
            .sorted { $0.t < $1.t }.map { Point(x: $0.t / 60, y: $0.percent) })
    }

    private var heartPoints: [Point] {
        downsample(run.decodedHRSamples.filter { $0.t.isFinite && $0.t >= 0 && $0.bpm > 0 }
            .sorted { $0.t < $1.t }.map { Point(x: $0.t / 60, y: Double($0.bpm)) })
    }

    private var endMinute: Double {
        max(0.01, run.durationSeconds / 60,
            pacePoints.last?.x ?? 0, elevationPoints.last?.x ?? 0,
            inclinePoints.last?.x ?? 0, heartPoints.last?.x ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("RUN TIMELINE").font(.barlowCondensed(size: 25)).foregroundStyle(style.ink)
                Spacer()
                Text("ELAPSED TIME").font(.runEyebrow(10)).foregroundStyle(style.muted)
            }
            chart("PACE", unit: "min/km", points: pacePoints, color: .stridePrimary,
                  reverse: true, empty: "No pace samples recorded")
            let vertical = run.dataSource == "bluetooth_ftms" ? inclinePoints : elevationPoints
            chart(run.dataSource == "bluetooth_ftms" ? "INCLINE" : "ELEVATION",
                  unit: run.dataSource == "bluetooth_ftms" ? "%" : "m",
                  points: vertical, color: .blue, reverse: false,
                  empty: run.dataSource == "bluetooth_ftms" ? "No incline recorded" : "No elevation recorded")
            chart("HEART RATE", unit: "bpm", points: heartPoints, color: .heartRatePink,
                  reverse: false, empty: "No heart rate recorded")
            HStack {
                Text("START")
                Spacer()
                Text("\(Int(endMinute.rounded())) MIN")
            }
            .font(.runEyebrow(10)).foregroundStyle(style.muted)
        }
        .padding(16)
        .stridePageCard(style, radius: 20)
    }

    @ViewBuilder
    private func chart(_ title: String, unit: String, points: [Point], color: Color,
                       reverse: Bool, empty: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.barlowCondensed(size: 20)).foregroundStyle(style.ink)
                Spacer()
                Text(unit).font(.runEyebrow(10)).foregroundStyle(style.muted)
            }
            if points.count >= 2 {
                let values = points.map(\.y)
                let low = values.min() ?? 0, high = values.max() ?? 1
                let padding = max((high - low) * 0.12, 0.1)
                Chart(points) { point in
                    AreaMark(x: .value("Time", point.x),
                             yStart: .value("Base", low - padding),
                             yEnd: .value(unit, point.y))
                        .foregroundStyle(color.opacity(0.12))
                    LineMark(x: .value("Time", point.x), y: .value(unit, point.y))
                        .interpolationMethod(.catmullRom(alpha: 0.5))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 1.7, lineCap: .round))
                }
                .chartXScale(domain: 0...endMinute)
                .chartYScale(domain: (low - padding)...(high + padding))
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 2)) { value in
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(String(format: "%.0f", reverse ? -number : number))
                            }
                        }
                    }
                }
                .frame(height: 100)
                .accessibilityLabel("\(title), from start to \(Int(endMinute.rounded())) minutes")
            } else {
                Text(empty).font(.inter(size: 12)).foregroundStyle(style.muted)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
            }
        }
    }

    private func downsample(_ points: [Point]) -> [Point] {
        guard points.count > 300 else { return points }
        let step = Int(ceil(Double(points.count) / 299))
        return stride(from: 0, to: points.count - 1, by: step).map { points[$0] } + [points[points.count - 1]]
    }
}
