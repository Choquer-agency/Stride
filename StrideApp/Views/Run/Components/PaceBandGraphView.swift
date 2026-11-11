import SwiftUI

/// One live plot: pace is red, heart rate is pink, each with its own target band.
/// Only the rendered traces are smoothed; recorded measurements are untouched.
struct PaceBandGraphView: View {
    let paces: [Double]
    let targetMinSec: Double?
    let targetMaxSec: Double?
    var heartRates: [Int?] = []
    var distances: [Double] = []
    var targetHeartRateRange: ClosedRange<Int>? = nil
    var graphHeight: CGFloat = 140
    var paceColor: Color = .stridePrimary
    var labelColor: Color = .secondary

    private var hasPaceTarget: Bool {
        guard let lo = targetMinSec, let hi = targetMaxSec else { return false }
        return lo.isFinite && hi.isFinite && hi >= lo
    }

    private var paceDomain: ClosedRange<Double> {
        if hasPaceTarget, let lo = targetMinSec, let hi = targetMaxSec {
            return (lo - 22)...(hi + 40)
        }
        return ((paces.min() ?? 350) - 15)...((paces.max() ?? 390) + 15)
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text("PACE /km").foregroundStyle(paceColor)
                if heartRates.contains(where: { $0 != nil }) {
                    Text("• HR").foregroundStyle(Color.heartRatePink)
                }
                Spacer()
                Text("LAST 500 m").foregroundStyle(labelColor)
            }
            .font(.runEyebrow(10))

            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let readings = heartRates.compactMap { $0 }
                let hrLow = min(readings.min() ?? 130, targetHeartRateRange?.lowerBound ?? 130) - 12
                let hrHigh = max(readings.max() ?? 160, targetHeartRateRange?.upperBound ?? 160) + 12
                let points = paces.enumerated().map { index, pace in
                    CGPoint(x: xPosition(index, width: width), y: paceY(pace, height: height))
                }
                ZStack(alignment: .topLeading) {
                    if hasPaceTarget, let fast = targetMinSec, let slow = targetMaxSec {
                        let top = paceY(fast, height: height)
                        let bottom = paceY(slow, height: height)
                        Rectangle().fill(Color.blue.opacity(0.08))
                            .frame(height: max(bottom - top, 2)).offset(y: top)
                        ForEach(Array(Set([fast, slow])).sorted(), id: \.self) { edge in
                            horizontalRule(y: paceY(edge, height: height), width: width)
                                .stroke(Color.blue.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        }
                    }
                    // No separate placeholder or empty HR chart: overlay only real readings.
                    if !readings.isEmpty, let target = targetHeartRateRange {
                        let top = hrY(target.upperBound, low: hrLow, high: hrHigh, height: height)
                        let bottom = hrY(target.lowerBound, low: hrLow, high: hrHigh, height: height)
                        Rectangle().fill(Color.heartRatePink.opacity(0.05))
                            .frame(height: bottom - top).offset(y: top)
                        horizontalRule(y: top, width: width)
                            .stroke(Color.heartRatePink.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
                        horizontalRule(y: bottom, width: width)
                            .stroke(Color.heartRatePink.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
                    }
                    RunGraphPath.rounded(points)
                        .stroke(paceColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    if let latest = points.last {
                        Circle().fill(paceColor).frame(width: 7, height: 7).position(latest)
                    }
                    // Preserve missing-reading gaps instead of inventing a continuous HR trace.
                    Path { path in
                        var segment: [CGPoint] = []
                        for (index, bpm) in heartRates.enumerated() {
                            if let bpm {
                                segment.append(CGPoint(x: xPosition(index, width: width),
                                    y: hrY(bpm, low: hrLow, high: hrHigh, height: height)))
                            } else {
                                path.addPath(RunGraphPath.rounded(segment))
                                segment = []
                            }
                        }
                        path.addPath(RunGraphPath.rounded(segment))
                    }
                    .stroke(Color.heartRatePink, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round, dash: [2, 5]))
                }
            }
            .frame(height: graphHeight)
            .clipped()

            ViewThatFits(in: .horizontal) {
                targetLabels(horizontal: true)
                targetLabels(horizontal: false)
            }
        }
    }

    @ViewBuilder
    private func targetLabels(horizontal: Bool) -> some View {
        let layout = horizontal ? AnyLayout(HStackLayout()) : AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
        layout {
                if hasPaceTarget, let fast = targetMinSec, let slow = targetMaxSec {
                    Text("Target \(Self.formatPace(fast))–\(Self.formatPace(slow)) /km")
                        .foregroundStyle(labelColor)
                }
                if horizontal { Spacer(minLength: 4) }
                if heartRates.contains(where: { $0 != nil }), let target = targetHeartRateRange {
                    Text("HR \(target.lowerBound)–\(target.upperBound)")
                        .foregroundStyle(Color.heartRatePink)
                }
            }
            .font(.runEyebrow(9))
            .lineLimit(1)
    }

    private func horizontalRule(y: CGFloat, width: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: width, y: y))
        }
    }

    private func paceY(_ pace: Double, height: CGFloat) -> CGFloat {
        let domain = paceDomain
        let clamped = min(max(pace, domain.lowerBound), domain.upperBound)
        return CGFloat((clamped - domain.lowerBound) / (domain.upperBound - domain.lowerBound)) * height
    }

    private func hrY(_ bpm: Int, low: Int, high: Int, height: CGFloat) -> CGFloat {
        height * (1 - CGFloat(bpm - low) / CGFloat(max(high - low, 1)))
    }

    private func xPosition(_ index: Int, width: CGFloat) -> CGFloat {
        if distances.count == paces.count, index < distances.count,
           let first = distances.first, let last = distances.last, last > first {
            return CGFloat((distances[index] - first) / (last - first)) * width
        }
        return CGFloat(index) / CGFloat(max(paces.count - 1, 1)) * width
    }

    private static func formatPace(_ seconds: Double) -> String {
        let value = max(Int(seconds), 0)
        return "\(value / 60):\(String(format: "%02d", value % 60))"
    }
}

/// Display-only filtering removes repeated-odometer spikes and subpixel noise.
/// All calculations operate on copies; raw samples and run statistics stay intact.
enum RunGraphPath {
    static func displayPoints(_ points: [CGPoint], bucketWidth: CGFloat = 4) -> [CGPoint] {
        let finite = points.filter { $0.x.isFinite && $0.y.isFinite }
        guard let first = finite.first, let last = finite.last else { return [] }
        let step = max(bucketWidth, (last.x - first.x) / 100, 0.001)
        var groups: [[CGPoint]] = []
        var bucket: Int?
        for point in finite {
            let key = Int(floor((point.x - first.x) / step))
            if key != bucket { groups.append([]); bucket = key }
            groups[groups.count - 1].append(point)
        }
        var result = groups.map { group in
            CGPoint(x: group.map(\.x).reduce(0, +) / CGFloat(group.count),
                    y: group.map(\.y).reduce(0, +) / CGFloat(group.count))
        }
        guard result.count > 1 else { return result }
        result[0].x = first.x
        // The latest value remains exact so the trace ends at the live reading.
        result[result.count - 1] = last
        if result.count > 2 {
            for _ in 0..<2 {
                let source = result
                for index in 1..<source.count - 1 {
                    let filtered = (source[index - 1].y + 2 * source[index].y + source[index + 1].y) / 4
                    result[index].y = source[index].y + 0.7 * (filtered - source[index].y)
                }
            }
        }
        return result
    }

    static func rounded(_ points: [CGPoint]) -> Path {
        let smooth = displayPoints(points)
        return Path { path in
            guard let first = smooth.first else { return }
            path.move(to: first)
            guard smooth.count > 1 else { return }
            // Round 35% of each adjacent edge (previously 50%): 30% less rounding.
            for index in 1..<smooth.count - 1 {
                let previous = smooth[index - 1]
                let current = smooth[index]
                let next = smooth[index + 1]
                let entry = CGPoint(x: current.x + 0.35 * (previous.x - current.x),
                                    y: current.y + 0.35 * (previous.y - current.y))
                let exit = CGPoint(x: current.x + 0.35 * (next.x - current.x),
                                   y: current.y + 0.35 * (next.y - current.y))
                path.addLine(to: entry)
                path.addQuadCurve(to: exit, control: current)
            }
            path.addLine(to: smooth[smooth.count - 1])
        }
    }
}
