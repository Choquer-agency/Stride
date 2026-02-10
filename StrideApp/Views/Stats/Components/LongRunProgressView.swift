import SwiftUI
import Charts

struct LongRunProgressView: View {
    let progression: [(weekNumber: Int, distance: Double)]
    let longestRunEver: Double
    let peakLongRunWeek: Int?
    let raceDistance: Double
    let planName: String
    let totalWeeks: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with plan name
            HStack {
                Text("Long Run Progression")
                    .font(.inter(size: 18, weight: .semibold))
                
                Spacer()
                
                Text(planName)
                    .font(.inter(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            
            if !progression.isEmpty {
                // Chart
                Chart {
                    // Long run progression line
                    ForEach(progression, id: \.weekNumber) { data in
                        LineMark(
                            x: .value("Week", data.weekNumber),
                            y: .value("Distance", data.distance)
                        )
                        .foregroundStyle(Color.stridePrimary)
                        .lineStyle(StrokeStyle(lineWidth: 3))
                        
                        // Point markers
                        PointMark(
                            x: .value("Week", data.weekNumber),
                            y: .value("Distance", data.distance)
                        )
                        .foregroundStyle(Color.stridePrimary)
                        .symbolSize(60)
                    }
                    
                    // Race distance reference line
                    if raceDistance > 0 {
                        RuleMark(y: .value("Race Distance", raceDistance))
                            .foregroundStyle(Color.strideDarkRed.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                            .annotation(position: .leading, alignment: .leading) {
                                Text("Race: \(Int(raceDistance)) km")
                                    .font(.inter(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(4)
                                    .background(Color(.systemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        
                        // Race day dot (green dot at race week)
                        PointMark(
                            x: .value("Week", totalWeeks),
                            y: .value("Distance", raceDistance)
                        )
                        .foregroundStyle(Color.green)
                        .symbolSize(120)
                    }
                    
                    // Peak training run marker
                    if let peakWeek = peakLongRunWeek,
                       let peakData = progression.first(where: { $0.weekNumber == peakWeek }) {
                        PointMark(
                            x: .value("Week", peakData.weekNumber),
                            y: .value("Distance", peakData.distance)
                        )
                        .foregroundStyle(Color.strideDarkRed)
                        .symbolSize(100)
                        .annotation(position: .top, alignment: .center) {
                            Text("Peak: \(Int(peakData.distance)) km")
                                .font(.inter(size: 10, weight: .semibold))
                                .foregroundStyle(Color.strideDarkRed)
                                .padding(4)
                                .background(Color(.systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
                .frame(height: 200)
                .chartXScale(domain: 1...max(totalWeeks, 1))
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let week = value.as(Int.self) {
                                Text("W\(week)")
                                    .font(.inter(size: 10))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let distance = value.as(Double.self) {
                                Text("\(Int(distance))")
                                    .font(.inter(size: 10))
                            }
                        }
                    }
                }
                
                // Stats
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Longest Run")
                            .font(.inter(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 2) {
                            Text("\(Int(longestRunEver))")
                                .font(.barlowCondensed(size: 20, weight: .medium))
                            Text(" km")
                                .font(.barlowCondensed(size: 20, weight: .medium))
                        }
                    }
                    
                    if let peakWeek = peakLongRunWeek {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Peak Week")
                                .font(.inter(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text("Week \(peakWeek)")
                                .font(.barlowCondensed(size: 20, weight: .medium))
                        }
                    }
                }
            } else {
                Text("No long run data available")
                    .font(.inter(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(hex: "F9F9F9"))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    LongRunProgressView(
        progression: [
            (1, 10), (2, 12), (3, 15), (4, 18),
            (5, 20), (6, 22), (7, 25), (8, 28),
            (9, 30), (10, 32), (11, 35), (12, 38)
        ],
        longestRunEver: 38,
        peakLongRunWeek: 12,
        raceDistance: 42.195,
        planName: "Bryce Sub 3",
        totalWeeks: 12
    )
    .padding()
}
