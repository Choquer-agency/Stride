import SwiftUI
import SwiftData

struct StatsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<TrainingPlan> { $0.isArchived == false }, sort: \TrainingPlan.createdAt, order: .reverse) private var plans: [TrainingPlan]
    @Query(sort: \Workout.date, order: .reverse) private var allWorkouts: [Workout]
    
    @State private var selectedWeek: Week?
    @Binding var selectedTab: MainTabView.Tab
    
    private var activePlan: TrainingPlan? {
        plans.first
    }
    
    // Calculate weekly distance for no-plan mode
    private var noPlanWeeklyStats: WeeklyDistanceStats {
        StatsViewModel.weeklyDistanceForCurrentCalendarWeek(workouts: allWorkouts)
    }
    
    /// Use allWorkouts.count as a SwiftUI dependency trigger.
    /// When any workout changes (e.g. isCompleted toggled), SwiftData updates
    /// the @Query which invalidates this view and forces stats recalculation.
    private var workoutChangeToken: Int {
        allWorkouts.filter { $0.isCompleted }.count
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let plan = activePlan {
                    let viewModel = StatsViewModel(plan: plan, additionalWorkouts: allWorkouts)
                    let filteredWeeks = viewModel.weeksForTimeRange(.fullPlan)
                    
                    // Stride Logo at top center
                    StrideLogoView(height: 32)
                        .padding(.top, 24)
                        .padding(.bottom, 8)
                    
                    // Summary Cards — pass workoutChangeToken to force reactivity
                    StatsSummarySection(viewModel: viewModel)
                        .padding(.horizontal, 16)
                        .id(workoutChangeToken)
                    
                    // Distance Bar Chart
                    DistanceBarChartView(workouts: allWorkouts)
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
                        raceDistance: plan.raceType.distanceKm,
                        planName: plan.raceName ?? plan.raceType.displayName,
                        totalWeeks: plan.sortedWeeks.count
                    )
                    .padding(.horizontal, 16)
                    
                    // Daily Run Log
                    DailyRunLogView(workouts: allWorkouts)
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
                        
                        // Summary Cards (weekly distance, YTD, 4-week avg, race countdown)
                        StatsSummarySectionNoPlan(
                            weeklyStats: noPlanWeeklyStats,
                            yearToDate: StatsViewModel.yearToDateDistance(from: allWorkouts),
                            fourWeekAverage: StatsViewModel.rolling4WeekAverage(from: allWorkouts),
                            onRaceCountdownTap: {
                                selectedTab = .plan
                            }
                        )
                        .padding(.horizontal, 16)
                        .id(workoutChangeToken)
                        
                        // Distance Bar Chart (works without a plan)
                        DistanceBarChartView(workouts: allWorkouts)
                            .padding(.horizontal, 16)
                        
                        // Training Composition — hidden (plan-specific)
                        // Long Run Progression — hidden (plan-specific)
                        
                        // Daily Run Log (always shown)
                        DailyRunLogView(workouts: allWorkouts)
                            .padding(.horizontal, 16)
                        
                        // Milestones (always shown, computed from all workouts)
                        MilestonesView(
                            longestRunEver: StatsViewModel.longestRunEver(from: allWorkouts),
                            highestWeeklyMileage: StatsViewModel.highestWeeklyMileage(from: allWorkouts),
                            fastest5K: StatsViewModel.fastestConsecutiveTime(from: allWorkouts, distanceKm: 5),
                            fastest10K: StatsViewModel.fastestConsecutiveTime(from: allWorkouts, distanceKm: 10),
                            fastest21K: StatsViewModel.fastestConsecutiveTime(from: allWorkouts, distanceKm: 21),
                            fastest42K: StatsViewModel.fastestConsecutiveTime(from: allWorkouts, distanceKm: 42)
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
            .modelContainer(for: TrainingPlan.self, inMemory: true)
    }
}
