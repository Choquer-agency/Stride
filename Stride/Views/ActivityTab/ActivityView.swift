import SwiftUI
import Charts

/// Unified Activity view combining dashboard stats with workout history
struct ActivityView: View {
    @ObservedObject var storageManager: StorageManager
    @ObservedObject var goalManager: GoalManager
    @ObservedObject var trainingPlanManager: TrainingPlanManager
    
    // State for period selection
    @State private var selectedPeriod: TimePeriod = .month
    @State private var selectedMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var showPeriodPicker = false
    @State private var showGoalSetup = false
    
    // Computed statistics
    private var statistics: ActivityStatistics {
        storageManager.workouts.calculateStatistics(
            for: selectedPeriod,
            month: selectedMonth,
            year: selectedYear
        )
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Today's workout card (if plan exists)
                    if let todaysWorkout = trainingPlanManager.todaysWorkout {
                        TodaysWorkoutCard(workout: todaysWorkout, planManager: trainingPlanManager)
                            .padding(.horizontal)
                    }
                    
                    // Goal card or CTA (at the top)
                    if let goal = goalManager.activeGoal {
                        ActiveGoalCard(goal: goal) {
                            showGoalSetup = true
                        }
                        .padding(.horizontal)
                    } else {
                        SetGoalCTACard {
                            showGoalSetup = true
                        }
                        .padding(.horizontal)
                    }
                    
                    // Period selector tabs
                    periodTabSelector
                    
                    // Month/Year picker (conditional)
                    PeriodDisplayView(
                        month: selectedMonth,
                        year: selectedYear,
                        isVisible: selectedPeriod == .month || selectedPeriod == .year,
                        showMonthAndYear: selectedPeriod == .month,
                        action: { showPeriodPicker = true }
                    )
                    
                    if statistics.totalRuns == 0 {
                        // Empty state
                        emptyStateView
                    } else {
                        // Main statistics display
                        VStack(spacing: 24) {
                            // Total distance - large display
                            totalDistanceView
                            
                            // Three-column stats
                            statsGridView
                            
                            // Bar chart
                            barChartView
                            
                    // Divider before workout list
                    Rectangle()
                        .fill(Color.stridePrimary)
                        .frame(height: 1)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                            
                            // Workout history list
                            workoutHistorySection
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Activity")
            .sheet(isPresented: $showPeriodPicker) {
                PeriodPickerView(
                    selectedMonth: $selectedMonth,
                    selectedYear: $selectedYear,
                    showMonthPicker: selectedPeriod == .month
                )
            }
            .sheet(isPresented: $showGoalSetup) {
                if let goal = goalManager.activeGoal {
                    GoalSetupView(mode: .edit(goal), goalManager: goalManager)
                } else {
                    GoalSetupView(mode: .create, goalManager: goalManager)
                }
            }
        }
    }
    
    // MARK: - Period Tab Selector
    
    private var periodTabSelector: some View {
        HStack(spacing: 12) {
            ForEach(TimePeriod.allCases, id: \.self) { period in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedPeriod = period
                    }
                }) {
                    Text(period.rawValue)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(selectedPeriod == period ? .strideBlack : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            selectedPeriod == period
                                ? .stridePrimary
                                : Color.clear
                        )
                        .cornerRadius(20)
                }
            }
        }
        .padding(4)
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal)
    }
    
    // MARK: - Total Distance Display
    
    private var totalDistanceView: some View {
        VStack(spacing: 8) {
            Text(formatDistance(statistics.totalDistanceKm))
                .font(.system(size: 72, weight: .medium))
                .foregroundColor(.primary)
                .minimumScaleFactor(0.5)
            
            Text("Kilometers")
                .font(.system(size: 16, weight: .light))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
    
    // MARK: - Stats Grid
    
    private var statsGridView: some View {
        HStack(spacing: 20) {
            // Total runs
            VStack(spacing: 8) {
                Text("\(statistics.totalRuns)")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.primary)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                
                Text(statistics.totalRuns == 1 ? "Run" : "Runs")
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            
            // Average pace
            VStack(spacing: 8) {
                Text(statistics.avgPaceSecondsPerKm > 0 
                    ? formatPace(statistics.avgPaceSecondsPerKm)
                    : "--:--")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.primary)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                
                Text("Avg. pace")
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            
            // Total time
            VStack(spacing: 8) {
                Text(formatTotalTime(statistics.totalTimeSeconds))
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.primary)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                
                Text("Time")
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - Bar Chart
    
    private var barChartView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !statistics.dailyAggregates.isEmpty {
                Chart {
                    // Bar marks for daily distance
                    ForEach(statistics.dailyAggregates) { aggregate in
                        BarMark(
                            x: .value("Day", xAxisLabel(for: aggregate)),
                            y: .value("Distance", aggregate.totalDistanceKm)
                        )
                        .foregroundStyle(Color.stridePrimary.gradient)
                        .cornerRadius(4)
                    }
                    
                    // Average line (only for periods with multiple data points)
                    if statistics.avgDistancePerDay > 0 && statistics.dailyAggregates.count > 1 {
                        RuleMark(y: .value("Average", statistics.avgDistancePerDay))
                            .foregroundStyle(.gray.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let km = value.as(Double.self) {
                                if km < 1 {
                                    Text(String(format: "%.1f", km))
                                        .font(.system(size: 12, weight: .light))
                                        .foregroundColor(.secondary)
                                } else {
                                    Text(String(format: "%.0f", km))
                                        .font(.system(size: 12, weight: .light))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.gray.opacity(0.2))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: xAxisMarkCount)) { value in
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(label)
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 220)
                .padding()
            }
        }
    }
    
    // MARK: - Workout History Section
    
    private var workoutHistorySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent workouts")
                .font(.system(size: 18, weight: .semibold))
                .padding(.horizontal, 8)
            
            if storageManager.workouts.isEmpty {
                Text("No workouts yet")
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 32)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(storageManager.workouts) { workout in
                        NavigationLink(destination: HistoryWorkoutDetailView(session: workout, storageManager: storageManager)) {
                            WorkoutRowItemView(session: workout)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.run")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No workouts")
                .font(.system(size: 20, weight: .semibold))
            
            Text(emptyStateMessage)
                .font(.system(size: 14, weight: .light))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            #if DEBUG
            if storageManager.workouts.isEmpty {
                Button("Generate test data") {
                    TestDataGenerator.generateTestWorkouts(storageManager: storageManager)
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.strideBlack)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.stridePrimary)
                .cornerRadius(100)
                .padding(.top)
            }
            #endif
        }
        .frame(height: 300)
        .padding()
    }
    
    private var emptyStateMessage: String {
        if storageManager.workouts.isEmpty {
            return "Complete workouts to see your stats"
        } else {
            switch selectedPeriod {
            case .week: return "No workouts this week"
            case .month: return "No workouts this month"
            case .year: return "No workouts this year"
            case .all: return "No workouts recorded"
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private var xAxisMarkCount: Int {
        switch selectedPeriod {
        case .week: return 7
        case .month: return min(statistics.dailyAggregates.count, 10)
        case .year: return 12
        case .all: return min(statistics.dailyAggregates.count, 10)
        }
    }
    
    private func xAxisLabel(for aggregate: DailyAggregate) -> String {
        switch selectedPeriod {
        case .week:
            // Show day of week
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            return formatter.string(from: aggregate.date)
            
        case .month:
            // Show day number
            return String(aggregate.dayNumber)
            
        case .year:
            // Show month abbreviation
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM"
            return formatter.string(from: aggregate.date)
            
        case .all:
            // Show short date for workouts with data
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: aggregate.date)
        }
    }
    
    private func formatTotalTime(_ seconds: Double) -> String {
        guard seconds > 0 else { return "0:00" }
        
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    private func formatPace(_ secondsPerKm: Double) -> String {
        let totalSeconds = Int(secondsPerKm)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatDistance(_ km: Double) -> String {
        // Show one decimal place, but avoid ".0" for whole numbers
        if km == floor(km) {
            return String(format: "%.0f", km)
        } else {
            return String(format: "%.1f", km)
        }
    }
}

// MARK: - Workout Row Item View

struct WorkoutRowItemView: View {
    let session: WorkoutSession
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                // Left side - Date and title
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.workoutTitle ?? session.startTime.toDefaultWorkoutTitle())
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text(session.startTime.toShortDateString())
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Right side - Key stats
                HStack(spacing: 16) {
                    // Distance
                    VStack(spacing: 2) {
                        Text(String(format: "%.2f", session.totalDistanceKm))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                        Text("km")
                            .font(.system(size: 12, weight: .light))
                            .foregroundColor(.secondary)
                    }
                    
                    // Pace
                    VStack(spacing: 2) {
                        Text(session.avgPaceSecondsPerKm.toPaceString())
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                        Text("pace")
                            .font(.system(size: 12, weight: .light))
                            .foregroundColor(.secondary)
                    }
                    
                    // Chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 16)
            
            // Divider
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 0.5)
        }
    }
}

