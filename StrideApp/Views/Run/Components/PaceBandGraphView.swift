import SwiftUI

/// Live pace trace drawn through the target-pace corridor. The shaded band is
/// where the coach wants you; the line drifting toward an edge tells you which
/// way you're off, and walking pins the trace to the bottom edge. Faster = up.
struct PaceBandGraphView: View {
    /// Raw pace samples, sec/km, oldest → newest (last ~500 m)
    let paces: [Double]
    /// Target band boundaries in sec/km (min = faster edge)
    let targetMinSec: Double?
    let targetMaxSec: Double?

    private let graphHeight: CGFloat = 150

    var body: some View {
        if let lo = targetMinSec, let hi = targetMaxSec, hi > lo {
            bandGraph(fastEdge: lo, slowEdge: hi)
        } else {
            freeGraph
        }
    }

    // MARK: - Target-band mode

    private func bandGraph(fastEdge: Double, slowEdge: Double) -> some View {
        // Display domain: tight headroom so the band itself dominates the
        // canvas; anything slower than the walk threshold clamps to the floor.
        let domainTop = fastEdge - 22          // fastest pace shown (top)
        let domainBottom = slowEdge + 40       // slowest pace shown (bottom)

        func y(_ pace: Double, _ height: CGFloat) -> CGFloat {
            let clamped = min(max(pace, domainTop), domainBottom)
            return CGFloat((clamped - domainTop) / (domainBottom - domainTop)) * height
        }

        return GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let bandTop = y(fastEdge, height)
            let bandBottom = y(slowEdge, height)

            ZStack(alignment: .topLeading) {
                // Target corridor
                Rectangle()
                    .fill(Color.green.opacity(0.10))
                    .frame(height: bandBottom - bandTop)
                    .offset(y: bandTop)

                // Corridor edges (dashed) with pace labels
                ForEach([(bandTop, fastEdge), (bandBottom, slowEdge)], id: \.0) { edgeY, pace in
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: edgeY))
                        p.addLine(to: CGPoint(x: width, y: edgeY))
                    }
                    .stroke(Color.green.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }

                Text(Self.formatPace(fastEdge))
                    .font(.barlowCondensed(size: 15, weight: .medium))
                    .foregroundStyle(Color.green)
                    .position(x: width - 20, y: max(bandTop - 11, 8))
                Text(Self.formatPace(slowEdge))
                    .font(.barlowCondensed(size: 15, weight: .medium))
                    .foregroundStyle(Color.green)
                    .position(x: width - 20, y: min(bandBottom + 11, height - 8))

                // Orientation captions
                Text("TOO FAST")
                    .font(.inter(size: 9, weight: .bold))
                    .kerning(1.2)
                    .foregroundStyle(.tertiary)
                    .position(x: 34, y: 10)
                Text("TOO SLOW")
                    .font(.inter(size: 9, weight: .bold))
                    .kerning(1.2)
                    .foregroundStyle(.tertiary)
                    .position(x: 36, y: height - 10)

                // The pace trace
                if paces.count > 1 {
                    Path { path in
                        for (index, pace) in paces.enumerated() {
                            let x = CGFloat(index) / CGFloat(paces.count - 1) * width
                            let point = CGPoint(x: x, y: y(pace, height))
                            if index == 0 {
                                path.move(to: point)
                            } else {
                                let prevX = CGFloat(index - 1) / CGFloat(paces.count - 1) * width
                                let prev = CGPoint(x: prevX, y: y(paces[index - 1], height))
                                path.addQuadCurve(
                                    to: point,
                                    control: CGPoint(x: (prev.x + point.x) / 2, y: (prev.y + point.y) / 2))
                            }
                        }
                    }
                    .stroke(Color.stridePrimary,
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                }

                // Current position dot
                if let last = paces.last {
                    let pos = CGPoint(x: width, y: y(last, height))
                    Circle()
                        .stroke(Color.stridePrimary.opacity(0.3), lineWidth: 3)
                        .frame(width: 16, height: 16)
                        .position(pos)
                    Circle()
                        .fill(Color.stridePrimary)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        .position(pos)
                }
            }
        }
        .frame(height: graphHeight)
        .clipped()
    }

    // MARK: - Free-run mode (no target: adaptive trace, no band)

    private var freeGraph: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let lo = (paces.min() ?? 0) - 10
            let hi = (paces.max() ?? 1) + 10
            if paces.count > 1, hi > lo {
                Path { path in
                    for (index, pace) in paces.enumerated() {
                        let x = CGFloat(index) / CGFloat(paces.count - 1) * width
                        let yPos = CGFloat((pace - lo) / (hi - lo)) * height
                        index == 0 ? path.move(to: CGPoint(x: x, y: yPos))
                                   : path.addLine(to: CGPoint(x: x, y: yPos))
                    }
                }
                .stroke(Color.stridePrimary,
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: graphHeight)
    }

    private static func formatPace(_ secPerKm: Double) -> String {
        "\(Int(secPerKm) / 60):\(String(format: "%02d", Int(secPerKm) % 60))"
    }
}

#Preview {
    PaceBandGraphView(
        paces: [385, 383, 386, 384, 382, 385, 388, 500, 540, 545, 542, 400, 386, 384],
        targetMinSec: 360,
        targetMaxSec: 390
    )
    .padding()
}
