import SwiftUI

struct StatsSummarySection: View {
    let viewModel: StatsViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            // 2x2 Grid
            HStack(spacing: 12) {
                // Weekly Distance
                StatCardView(
                    title: "Weekly Distance",
                    value: viewModel.currentWeekStats.displayText,
                    subtitle: viewModel.currentWeekStats.percentageText,
                    changeText: weeklyChangeText
                )
                
                // Year-to-Date
                StatCardView(
                    title: "Year-to-Date",
                    value: "\(Int(viewModel.yearToDateDistance)) km",
                    subtitle: "in \(Calendar.current.component(.year, from: Date()))"
                )
            }
            
            HStack(spacing: 12) {
                // Rolling 4-Week Average
                StatCardView(
                    title: "4-Week Average",
                    value: "\(Int(viewModel.rolling4WeekAverage)) km",
                    subtitle: "Rolling average"
                )
                
                // Race Countdown
                StatCardView(
                    title: "Race Countdown",
                    value: "\(viewModel.plan.daysUntilRace) days",
                    subtitle: viewModel.plan.raceName ?? viewModel.plan.raceType.displayName
                )
            }
        }
    }
    
    private var weeklyChangeText: String? {
        let change = viewModel.weeklyDistanceChange
        guard abs(change) > 0.1 else { return nil }
        
        let sign = change > 0 ? "+" : ""
        return "\(sign)\(Int(change))% vs last week"
    }
}

// MARK: - No Plan Summary Section
struct StatsSummarySectionNoPlan: View {
    let weeklyStats: WeeklyDistanceStats
    let yearToDate: Double
    let fourWeekAverage: Double
    var onRaceCountdownTap: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 12) {
            // Row 1
            HStack(spacing: 12) {
                // Weekly Distance
                StatCardView(
                    title: "Weekly Distance",
                    value: weeklyStats.displayText,
                    subtitle: weeklyStats.percentageText
                )
                
                // Year-to-Date
                StatCardView(
                    title: "Year-to-Date",
                    value: "\(Int(yearToDate)) km",
                    subtitle: "in \(Calendar.current.component(.year, from: Date()))"
                )
            }
            
            // Row 2
            HStack(spacing: 12) {
                // Rolling 4-Week Average
                StatCardView(
                    title: "4-Week Average",
                    value: "\(Int(fourWeekAverage)) km",
                    subtitle: "Rolling average"
                )
                
                // Race Countdown — N/A, tappable to go to Plan tab
                Button(action: { onRaceCountdownTap?() }) {
                    StatCardView(
                        title: "Race Countdown",
                        value: "N/A",
                        subtitle: "Tap to create a plan"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    let plan = TrainingPlan(
        raceType: .marathon,
        raceDate: Date().addingTimeInterval(86400 * 91),
        raceName: "Boston Marathon",
        currentWeeklyMileage: 50,
        longestRecentRun: 20,
        fitnessLevel: .intermediate,
        startDate: Date()
    )
    let viewModel = StatsViewModel(plan: plan)
    
    return StatsSummarySection(viewModel: viewModel)
        .padding()
}
