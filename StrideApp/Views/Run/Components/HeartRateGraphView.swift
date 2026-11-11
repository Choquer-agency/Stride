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
