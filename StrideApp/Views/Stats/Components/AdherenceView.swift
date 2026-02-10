import SwiftUI

struct AdherenceView: View {
    let last4WeeksAdherence: Double
    let overallPlanAdherence: Double
    let weeks: [Week]
    
    private var missedWorkouts: [(weekNumber: Int, count: Int)] {
        weeks.map { week in
            let missed = week.activeWorkouts - week.completedWorkouts
            return (weekNumber: week.weekNumber, count: max(0, missed))
        }
        .filter { $0.count > 0 }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("Adherence")
                .font(.inter(size: 18, weight: .semibold))
            
            // Circular progress ring
            HStack(spacing: 24) {
                ZStack {
                    // Background circle
                    Circle()
                        .stroke(Color(.systemGray5), lineWidth: 12)
                        .frame(width: 100, height: 100)
                    
                    // Progress circle
                    Circle()
                        .trim(from: 0, to: CGFloat(overallPlanAdherence / 100))
                        .stroke(
                            Color.stridePrimary,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                    
                    // Percentage text
                    VStack(spacing: 2) {
                        Text("\(Int(overallPlanAdherence))%")
                            .font(.barlowCondensed(size: 24, weight: .medium))
                        Text("Overall")
                            .font(.inter(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Comparison stats
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Last 4 Weeks")
                            .font(.inter(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("\(Int(last4WeeksAdherence))%")
                            .font(.barlowCondensed(size: 20, weight: .medium))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Overall Plan")
                            .font(.inter(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("\(Int(overallPlanAdherence))%")
                            .font(.barlowCondensed(size: 20, weight: .medium))
                    }
                }
                
                Spacer()
            }
            
            // Missed workouts (subtle dots, not shameful)
            if !missedWorkouts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Missed Workouts")
                        .font(.inter(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 8) {
                        ForEach(missedWorkouts.prefix(20), id: \.weekNumber) { missed in
                            Circle()
                                .fill(Color(.systemGray4))
                                .frame(width: 6, height: 6)
                        }
                        
                        if missedWorkouts.count > 20 {
                            Text("+\(missedWorkouts.count - 20)")
                                .font(.inter(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(hex: "F9F9F9"))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    AdherenceView(
        last4WeeksAdherence: 94,
        overallPlanAdherence: 91,
        weeks: []
    )
    .padding()
}
