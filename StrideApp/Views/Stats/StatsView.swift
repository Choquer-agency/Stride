import SwiftUI
import SwiftData

struct StatsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<TrainingPlan> { $0.isArchived == false }, sort: \TrainingPlan.createdAt, order: .reverse) private var plans: [TrainingPlan]
    @Query(sort: \RunLog.completedAt, order: .reverse) private var runLogs: [RunLog]

    @State private var selectedWeek: Week?
    @Binding var selectedTab: MainTabView.Tab

    private var activePlan: TrainingPlan? {
        plans.first
    }

    // Calculate weekly distance for no-plan mode
    private var noPlanWeeklyStats: WeeklyDistanceStats {
        StatsViewModel.weeklyDistanceForCurrentCalendarWeek(runLogs: runLogs)
    }

    /// Use runLogs.count as a SwiftUI dependency trigger.
    private var runLogChangeToken: Int {
        runLogs.count
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let plan = activePlan {
                    let viewModel = StatsViewModel(plan: plan, runLogs: runLogs)
                    let filteredWeeks = viewModel.weeksForTimeRange(.fullPlan)

                    // Stride Logo at top center
                    StrideLogoView(height: 32)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    // Summary Cards
                    StatsSummarySection(viewModel: viewModel)
                        .padding(.horizontal, 16)
                        .id(runLogChangeToken)

                    // Distance Bar Chart
                    DistanceBarChartView(runLogs: runLogs)
                        .padding(.horizontal, 16)

                    // Training Composition (for current week or selected week)
                    if let week = selectedWeek ?? plan.currentWeek ?? filteredWeeks.last {
                        TrainingCompositionView(week: week, viewModel: viewModel)
                            .padding(.horizontal, 16)
                    }

                    // Long Run Progression
                    LongRunProgressView(
                        progression: viewModel.longRunProgression,
                        longestRunEver: viewModel.longestRunEver,
                        peakLongRunWeek: viewModel.peakLongRunWeek,
                        raceDistance: plan.customDistanceKm ?? plan.raceType.distanceKm ?? 42.195,
                        planName: plan.raceName ?? plan.displayDistance,
                        totalWeeks: plan.sortedWeeks.count
                    )
                    .padding(.horizontal, 16)

                    // Daily Run Log
                    DailyRunLogView(runLogs: runLogs)
                        .padding(.horizontal, 16)

                    // Milestones
                    MilestonesView(
                        longestRunEver: viewModel.longestRunEverMilestone,
                        highestWeeklyMileage: viewModel.highestWeeklyMileage,
                        fastest5K: viewModel.fastest5K,
                        fastest10K: viewModel.fastest10K,
                        fastest21K: viewModel.fastest21K,
                        fastest42K: viewModel.fastest42K
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 100)
                } else {
                    // No plan — show all plan-independent stats
                    VStack(spacing: 12) {
                        // Stride Logo at top center
                        StrideLogoView(height: 32)
                            .padding(.top, 24)
                            .padding(.bottom, 8)

                        // Summary Cards
                        StatsSummarySectionNoPlan(
                            weeklyStats: noPlanWeeklyStats,
                            yearToDate: StatsViewModel.yearToDateDistance(from: runLogs),
                            fourWeekAverage: StatsViewModel.rolling4WeekAverage(from: runLogs),
                            onRaceCountdownTap: {
                                selectedTab = .plan
                            }
                        )
                        .padding(.horizontal, 16)
                        .id(runLogChangeToken)

                        // Distance Bar Chart
                        DistanceBarChartView(runLogs: runLogs)
                            .padding(.horizontal, 16)

                        // Daily Run Log
                        DailyRunLogView(runLogs: runLogs)
                            .padding(.horizontal, 16)

                        // Milestones
                        MilestonesView(
                            longestRunEver: StatsViewModel.longestRunEver(from: runLogs),
                            highestWeeklyMileage: StatsViewModel.highestWeeklyMileage(from: runLogs),
                            fastest5K: StatsViewModel.fastestConsecutiveTime(from: runLogs, distanceKm: 5),
                            fastest10K: StatsViewModel.fastestConsecutiveTime(from: runLogs, distanceKm: 10),
                            fastest21K: StatsViewModel.fastestConsecutiveTime(from: runLogs, distanceKm: 21),
                            fastest42K: StatsViewModel.fastestConsecutiveTime(from: runLogs, distanceKm: 42)
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 100)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
    }
}

#Preview {
    NavigationStack {
        StatsView(selectedTab: .constant(.stats))
            .modelContainer(for: [TrainingPlan.self, RunLog.self], inMemory: true)
    }
}
