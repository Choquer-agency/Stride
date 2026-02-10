import SwiftUI
import Charts

struct TrainingCompositionView: View {
    let week: Week
    let viewModel: StatsViewModel
    
    @State private var selectedWeek: Week?
    
    private var breakdown: [IntensityBucket: Double] {
        viewModel.intensityBreakdown(for: week)
    }
    
    private var totalDistance: Double {
        breakdown.values.reduce(0, +)
    }
    
    private var chartData: [(bucket: IntensityBucket, distance: Double, percentage: Double)] {
        breakdown.map { (bucket, distance) in
            let percentage = totalDistance > 0 ? (distance / totalDistance) * 100 : 0
            return (bucket: bucket, distance: distance, percentage: percentage)
        }
        .sorted { $0.bucket.rawValue < $1.bucket.rawValue }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("Training Composition")
                .font(.inter(size: 18, weight: .semibold))
            
            if totalDistance > 0 {
                // Summary text
                HStack(spacing: 0) {
                    Text("Week \(week.weekNumber): \(Int(totalDistance)) km total")
                        .font(.inter(size: 14, weight: .medium))
                }
                .foregroundStyle(.secondary)
                
                // Stacked horizontal bar
                VStack(spacing: 8) {
                    ForEach(chartData, id: \.bucket) { data in
                        HStack(spacing: 12) {
                            // Color indicator
                            Circle()
                                .fill(data.bucket.color)
                                .frame(width: 12, height: 12)
                            
                            // Label
                            Text(data.bucket.displayName)
                                .font(.inter(size: 13, weight: .medium))
                                .frame(width: 70, alignment: .leading)
                            
                            // Bar
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(.systemGray5))
                                        .frame(height: 20)
                                    
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(data.bucket.color)
                                        .frame(width: geometry.size.width * CGFloat(data.percentage / 100), height: 20)
                                }
                            }
                            .frame(height: 20)
                            
                            // Percentage
                            Text("\(Int(data.percentage))%")
                                .font(.barlowCondensed(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }
            } else {
                Text("No training data for this week")
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
    let week = Week(weekNumber: 1)
    let viewModel = StatsViewModel(plan: plan)
    
    return TrainingCompositionView(week: week, viewModel: viewModel)
        .padding()
}
