import SwiftUI
import Charts

struct TrainingIntensityView: View {
    let weeks: [Week]
    let viewModel: StatsViewModel
    
    private var intensityOverTime: [(week: Int, easy: Double, moderate: Double, hard: Double)] {
        weeks.map { week in
            let breakdown = viewModel.intensityBreakdown(for: week)
            return (
                week: week.weekNumber,
                easy: breakdown[.easy] ?? 0,
                moderate: breakdown[.moderate] ?? 0,
                hard: breakdown[.hard] ?? 0
            )
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("Training Intensity")
                .font(.inter(size: 18, weight: .semibold))
            
            if !intensityOverTime.isEmpty {
                // Area chart
                Chart {
                    ForEach(intensityOverTime, id: \.week) { data in
                        // Easy (green) - base layer
                        AreaMark(
                            x: .value("Week", data.week),
                            yStart: .value("Easy Start", 0),
                            yEnd: .value("Easy End", data.easy)
                        )
                        .foregroundStyle(Color.workoutEasy.opacity(0.6))
                        
                        // Moderate (yellow/orange) - middle layer
                        AreaMark(
                            x: .value("Week", data.week),
                            yStart: .value("Moderate Start", data.easy),
                            yEnd: .value("Moderate End", data.easy + data.moderate)
                        )
                        .foregroundStyle(Color.workoutTempo.opacity(0.6))
                        
                        // Hard (red) - top layer
                        AreaMark(
                            x: .value("Week", data.week),
                            yStart: .value("Hard Start", data.easy + data.moderate),
                            yEnd: .value("Hard End", data.easy + data.moderate + data.hard)
                        )
                        .foregroundStyle(Color.workoutInterval.opacity(0.6))
                    }
                }
                .frame(height: 150)
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
                                    .font(.barlowCondensed(size: 10, weight: .medium))
                            }
                        }
                    }
                }
                
                // Legend
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.workoutEasy)
                            .frame(width: 10, height: 10)
                        Text("Easy")
                            .font(.inter(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.workoutTempo)
                            .frame(width: 10, height: 10)
                        Text("Moderate")
                            .font(.inter(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.workoutInterval)
                            .frame(width: 10, height: 10)
                        Text("Hard")
                            .font(.inter(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("No intensity data available")
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
    let plan = TrainingPlan(
        raceType: .marathon,
        raceDate: Date(),
        currentWeeklyMileage: 50,
        longestRecentRun: 20,
        fitnessLevel: .intermediate,
        startDate: Date()
    )
    let viewModel = StatsViewModel(plan: plan)
    
    return TrainingIntensityView(weeks: [], viewModel: viewModel)
        .padding()
}
