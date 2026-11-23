import SwiftUI

/// One live plot: pace is red, heart rate is pink, with one shared target band.
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
    var fixedGuides = false
    var statusText: String = ""

    private var hasPaceTarget: Bool {
        guard let lo = targetMinSec, let hi = targetMaxSec else { return false }
        return lo.isFinite && hi.isFinite && hi >= lo
    }

    private var paceDomain: ClosedRange<Double> {
        RunGraphScale.paceDomain(paces: paces, fast: targetMinSec, slow: targetMaxSec)
    }

    var body: some View {
        if fixedGuides {
            fixedGuideGraph
        } else {
            adaptiveGraph
        }
    }

    private var fixedGuideGraph: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(paceColor).frame(width: 8, height: 8)
                Text("PACE")
                Circle().fill(Color.heartRatePink).frame(width: 8, height: 8)
                    .padding(.leading, 8)
                Text("HR")
                Spacer()
                Text("LAST 500M").font(.runEyebrow(8))
            }
            .font(.runEyebrow(14))
            .foregroundStyle(labelColor)
            .padding(.bottom, 18)

            Rectangle().fill(.white.opacity(0.85)).frame(height: 0.6)
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let top = height * 0.18
                let bottom = height * 0.82
                let readings = heartRates.compactMap { $0 }
                let points = paces.enumerated().map { index, pace in
                    CGPoint(x: xPosition(index, width: width),
                            y: RunGraphScale.fixedPaceY(pace: pace, paces: paces,
                                fast: targetMinSec, slow: targetMaxSec,
                                top: top, bottom: bottom, height: height))
                }
                ZStack(alignment: .topLeading) {
                    ForEach(0..<2, id: \.self) { index in
                        horizontalRule(y: index == 0 ? top : bottom, width: width)
                            .stroke(Color(red: 0, green: 0.765, blue: 1),
                                style: StrokeStyle(lineWidth: 1.2, dash: [8, 8]))
                    }
                    if points.count > 1 {
                        RunGraphPath.area(points, bottom: height)
                            .fill(LinearGradient(colors: [paceColor.opacity(0.25), paceColor.opacity(0)],
                                                 startPoint: .top, endPoint: .bottom))
                    }
                    RunGraphPath.rounded(points)
                        .stroke(paceColor, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                    if let latest = points.last {
                        Circle().fill(paceColor).frame(width: 6, height: 6).position(latest)
                    }
                    Path { path in
                        var segment: [CGPoint] = []
                        for (index, bpm) in heartRates.enumerated() {
                            if let bpm {
                                segment.append(CGPoint(x: xPosition(index, width: width),
                                    y: RunGraphScale.fixedHeartRateY(bpm: bpm, readings: readings,
                                        target: targetHeartRateRange, top: top,
                                        bottom: bottom, height: height)))
                            } else {
                                path.addPath(RunGraphPath.rounded(segment))
                                segment = []
                            }
                        }
                        path.addPath(RunGraphPath.rounded(segment))
                    }
                    .stroke(Color.heartRatePink,
                        style: StrokeStyle(lineWidth: 0.95, lineCap: .round, lineJoin: .round))
                    if !statusText.isEmpty {
                        Text(statusText.uppercased())
                            .font(.runEyebrow(12))
                            .foregroundStyle(Color(red: 0.35, green: 0.72, blue: 1))
                            .frame(maxWidth: .infinity, maxHeight: .infinity,
                                   alignment: .bottomTrailing)
                            .padding(.trailing, 2)
                            .padding(.bottom, 2)
                    }
                }
            }
            .frame(height: graphHeight)
            .clipped()
            Rectangle().fill(.white.opacity(0.85)).frame(height: 0.6)
        }
    }

    private var adaptiveGraph: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Circle().fill(paceColor).frame(width: 10, height: 10)
                Text("Pace").foregroundStyle(labelColor)
                if heartRates.contains(where: { $0 != nil }) {
                    Circle().fill(Color.heartRatePink).frame(width: 10, height: 10)
                    Text("HR").foregroundStyle(labelColor)
                }
                Spacer()
                Text("Last 500 m").foregroundStyle(labelColor)
            }
            .font(.inter(size: 20, weight: .semibold))

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
                        Rectangle().fill(Color.white.opacity(0.07))
                            .frame(height: max(bottom - top, 2)).offset(y: top)
                        ForEach(Array(Set([fast, slow])).sorted(), id: \.self) { edge in
                            horizontalRule(y: paceY(edge, height: height), width: width)
                                .stroke(Color.white.opacity(0.42), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        }
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
                                    y: heartRateY(bpm, low: hrLow, high: hrHigh, height: height)))
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

        }
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

    private func heartRateY(_ bpm: Int, low: Int, high: Int, height: CGFloat) -> CGFloat {
        if hasPaceTarget, let fast = targetMinSec, let slow = targetMaxSec,
           let range = targetHeartRateRange, range.upperBound > range.lowerBound {
            return RunGraphScale.heartRateY(bpm: bpm, target: range,
                fastY: paceY(fast, height: height), slowY: paceY(slow, height: height), height: height)
        }
        return hrY(bpm, low: low, high: high, height: height)
    }

    private func xPosition(_ index: Int, width: CGFloat) -> CGFloat {
        if distances.count == paces.count, index < distances.count,
           let first = distances.first, let last = distances.last, last > first {
            return CGFloat((distances[index] - first) / (last - first)) * width
        }
        return CGFloat(index) / CGFloat(max(paces.count - 1, 1)) * width
    }

}

enum RunGraphScale {
    static func fixedPaceY(pace: Double, paces: [Double], fast: Double?, slow: Double?,
                           top: CGFloat, bottom: CGFloat, height: CGFloat) -> CGFloat {
        guard pace.isFinite, pace > 0 else { return height }
        guard let fast, let slow, fast.isFinite, slow.isFinite, slow > fast else {
            let domain = paceDomain(paces: paces, fast: nil, slow: nil)
            return CGFloat((pace - domain.lowerBound) / (domain.upperBound - domain.lowerBound)) * height
        }
        if pace < fast {
            let minPace = paces.filter { $0.isFinite && $0 > 0 }.min() ?? fast
            let overflow = max(fast - minPace, 15)
            return max(0, top * (1 - 0.85 * CGFloat((fast - pace) / overflow)))
        }
        if pace > slow {
            let maxPace = paces.filter { $0.isFinite && $0 > 0 }.max() ?? slow
            let overflow = max(maxPace - slow, 15)
            return min(height, bottom + (height - bottom) * 0.85 * CGFloat((pace - slow) / overflow))
        }
        return top + (bottom - top) * CGFloat((pace - fast) / (slow - fast))
    }

    static func fixedHeartRateY(bpm: Int, readings: [Int], target: ClosedRange<Int>?,
                                top: CGFloat, bottom: CGFloat, height: CGFloat) -> CGFloat {
        guard let target, target.upperBound > target.lowerBound else {
            let low = min(readings.min() ?? 130, 130) - 12
            let high = max(readings.max() ?? 160, 160) + 12
            return height * (1 - CGFloat(bpm - low) / CGFloat(max(high - low, 1)))
        }
        if bpm > target.upperBound {
            let overflow = max((readings.max() ?? bpm) - target.upperBound, 10)
            return max(0, top * (1 - 0.85 * CGFloat(bpm - target.upperBound) / CGFloat(overflow)))
        }
        if bpm < target.lowerBound {
            let overflow = max(target.lowerBound - (readings.min() ?? bpm), 10)
            return min(height, bottom + (height - bottom) * 0.85 * CGFloat(target.lowerBound - bpm) / CGFloat(overflow))
        }
        return top + (bottom - top) * CGFloat(target.upperBound - bpm) /
            CGFloat(target.upperBound - target.lowerBound)
    }

    static func paceDomain(paces: [Double], fast: Double?, slow: Double?) -> ClosedRange<Double> {
        let measured = paces.filter { $0.isFinite && (120...1200).contains($0) }
        let targets = [fast, slow].compactMap { $0 }.filter { $0.isFinite && $0 > 0 }
        let values = measured + targets
        let lower = values.min() ?? 330
        let upper = values.max() ?? 420
        let span = max(upper - lower, 90)
        let center = (lower + upper) / 2
        let padding = max(15, span * 0.12)
        return (center - span / 2 - padding)...(center + span / 2 + padding)
    }

    static func heartRateY(bpm: Int, target: ClosedRange<Int>, fastY: CGFloat,
                           slowY: CGFloat, height: CGFloat) -> CGFloat {
        let ratio = CGFloat(target.upperBound - bpm) /
            CGFloat(max(target.upperBound - target.lowerBound, 1))
        return min(max(fastY + ratio * (slowY - fastY), 0), height)
    }
}

/// Display-only filtering removes repeated-odometer spikes and subpixel noise.
/// All calculations operate on copies; raw samples and run statistics stay intact.
enum RunGraphPath {
    static func displayPoints(_ points: [CGPoint], bucketWidth: CGFloat = 1.5) -> [CGPoint] {
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
            for _ in 0..<1 {
                let source = result
                for index in 1..<source.count - 1 {
                    let filtered = (source[index - 1].y + 2 * source[index].y + source[index + 1].y) / 4
                    let isolatedSurge = index >= 2 && index + 2 < source.count &&
                        abs(source[index - 2].y - source[index - 1].y) < 4 &&
                        abs(source[index + 1].y - source[index + 2].y) < 4 &&
                        abs(source[index].y - filtered) > 10
                    let amount: CGFloat = isolatedSurge ? 0.10 : 0.40
                    result[index].y = source[index].y + amount * (filtered - source[index].y)
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
            // A slightly tighter corner keeps short pace changes visible.
            for index in 1..<smooth.count - 1 {
                let previous = smooth[index - 1]
                let current = smooth[index]
                let next = smooth[index + 1]
                let entry = CGPoint(x: current.x + 0.30 * (previous.x - current.x),
                                    y: current.y + 0.30 * (previous.y - current.y))
                let exit = CGPoint(x: current.x + 0.30 * (next.x - current.x),
                                   y: current.y + 0.30 * (next.y - current.y))
                path.addLine(to: entry)
                path.addQuadCurve(to: exit, control: current)
            }
            path.addLine(to: smooth[smooth.count - 1])
        }
    }

    static func area(_ points: [CGPoint], bottom: CGFloat) -> Path {
        let smooth = displayPoints(points)
        guard let first = smooth.first, let last = smooth.last, smooth.count > 1 else { return Path() }
        var path = rounded(smooth)
        path.addLine(to: CGPoint(x: last.x, y: bottom))
        path.addLine(to: CGPoint(x: first.x, y: bottom))
        path.closeSubpath()
        return path
    }
}
