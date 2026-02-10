import SwiftUI

struct PaceGraphView: View {
    // Normalized 0-1 data points where 0 is slowest, 1 is fastest
    // Accepts dynamic data from RunViewModel; falls back to default mock data
    var dataPoints: [Double]
    
    private static let defaultDataPoints: [Double] = [
        0.25, 0.30, 0.28, 0.35, 0.32, 0.40, 0.38, 0.45, 0.42, 0.48,
        0.50, 0.52, 0.55, 0.58, 0.60, 0.65, 0.68, 0.72, 0.75, 0.78,
        0.80, 0.82, 0.85, 0.88, 0.90, 0.92, 0.94, 0.96, 0.97, 0.98
    ]
    
    init(dataPoints: [Double] = PaceGraphView.defaultDataPoints) {
        self.dataPoints = dataPoints.isEmpty ? PaceGraphView.defaultDataPoints : dataPoints
    }
    
    private let barCount: Int = 60
    private let graphHeight: CGFloat = 80
    
    // Helper function to interpolate y value at any x position
    private func interpolateY(at normalizedX: CGFloat, height: CGFloat) -> CGFloat {
        let exactIndex = normalizedX * CGFloat(dataPoints.count - 1)
        let lowerIndex = Int(exactIndex)
        let upperIndex = min(lowerIndex + 1, dataPoints.count - 1)
        let fraction = exactIndex - CGFloat(lowerIndex)
        
        let lowerValue = dataPoints[lowerIndex]
        let upperValue = dataPoints[upperIndex]
        let interpolatedValue = lowerValue + (upperValue - lowerValue) * Double(fraction)
        
        return height - (CGFloat(interpolatedValue) * graphHeight)
    }
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            
            // Fixed bar width: 3pt bars with 2pt gap
            let barWidth: CGFloat = 3
            let minGap: CGFloat = 2
            let minSpacing = barWidth + minGap // 5pt minimum between bar centers
            
            // Calculate how many bars we can fit - aim for 20% more than before
            let maxBars = Int(width / minSpacing)
            let baseBarCount = dataPoints.count / 2 // Approximate previous count
            let targetBarCount = Int(Double(baseBarCount) * 3) // 20% more
            let visibleBarCount = min(targetBarCount, maxBars)
            
            ZStack {
                // Vertical bars evenly spaced across width, following the line
                // Bars follow the line from start to end, spanning full width
                // Vertical gradient: red at top, white at bottom
                ForEach(0..<visibleBarCount, id: \.self) { barIndex in
                    // Calculate evenly spaced x position
                    let normalizedX = CGFloat(barIndex) / CGFloat(visibleBarCount - 1)
                    let lineX = normalizedX * width
                    
                    // Interpolate y value from line data points
                    let lineY = interpolateY(at: normalizedX, height: height)
                    let barHeight = height - lineY // Full height from baseline to line
                    
                    // Vertical gradient: red at top, white at bottom
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.stridePrimary,
                                    Color.white
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: barWidth, height: max(barHeight, 0))
                        .position(x: lineX, y: height - barHeight / 2) // Center bar vertically, align x with line
                }
                
                // Smooth curved line connecting bar tops
                Path { path in
                    // Create smooth curve through data points using Catmull-Rom style interpolation
                    let pointCount = dataPoints.count
                    
                    for index in 0..<pointCount {
                        let normalizedX = CGFloat(index) / CGFloat(pointCount - 1)
                        let x = normalizedX * width
                        let y = height - (CGFloat(dataPoints[index]) * graphHeight)
                        
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            // Use smooth curves for natural transitions
                            let prevX = CGFloat(index - 1) / CGFloat(pointCount - 1) * width
                            let prevY = height - (CGFloat(dataPoints[index - 1]) * graphHeight)
                            
                            // Control point for smooth curve
                            let controlX = (prevX + x) / 2
                            let controlY = (prevY + y) / 2
                            
                            path.addQuadCurve(
                                to: CGPoint(x: x, y: y),
                                control: CGPoint(x: controlX, y: controlY)
                            )
                        }
                    }
                }
                .stroke(Color.stridePrimary, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                
                // Current position indicator (circle at rightmost point)
                if let lastValue = dataPoints.last {
                    let lastIndex = dataPoints.count - 1
                    let normalizedX = CGFloat(lastIndex) / CGFloat(dataPoints.count - 1)
                    let x = normalizedX * width
                    let y = height - (CGFloat(lastValue) * graphHeight)
                    
                    // Outer ring (lighter/transparent)
                    Circle()
                        .stroke(Color.stridePrimary.opacity(0.3), lineWidth: 2)
                        .frame(width: 12, height: 12)
                        .position(x: x, y: y)
                    
                    // Inner solid circle
                    Circle()
                        .fill(Color.stridePrimary)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 1.5)
                        )
                        .position(x: x, y: y)
                }
            }
        }
        .frame(height: graphHeight)
    }
}

#Preview {
    VStack {
        PaceGraphView()
            .padding()
    }
    .background(Color.white)
}
