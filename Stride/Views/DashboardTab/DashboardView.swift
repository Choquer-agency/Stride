import SwiftUI
import Charts

/// Activity dashboard with time period filtering and statistics
struct DashboardView: View {
    @ObservedObject var storageManager: StorageManager
    @ObservedObject var authManager = AuthManager.shared
    
    // State for period selection
    @State private var selectedPeriod: TimePeriod = .month
    @State private var selectedMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var showPeriodPicker = false
    
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
                    // Stride Wordmark Header
                    Image("StrideWordmark")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 50)
                        .padding(.top, 8)
                    
                    // Network status banner (show only if not authenticated)
                    if !authManager.isAuthenticated {
                        NetworkStatusBanner(storageManager: storageManager)
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
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showPeriodPicker) {
                PeriodPickerView(
                    selectedMonth: $selectedMonth,
                    selectedYear: $selectedYear,
                    showMonthPicker: selectedPeriod == .month
                )
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
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(selectedPeriod == period ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            selectedPeriod == period
                                ? Color.green
                                : Color.clear
                        )
                        .cornerRadius(20)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(Color(.systemGray6))
        .cornerRadius(22)
        .padding(.horizontal)
    }
    
    // MARK: - Total Distance Display
    
    private var totalDistanceView: some View {
        VStack(spacing: 4) {
            Text(formatDistance(statistics.totalDistanceKm))
                .font(.system(size: 56, weight: .bold))
                .foregroundColor(.primary)
            
            Text("Kilometers")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
    
    // MARK: - Stats Grid
    
    private var statsGridView: some View {
        HStack(spacing: 16) {
            // Total runs
            StatItemView(
                value: "\(statistics.totalRuns)",
                label: statistics.totalRuns == 1 ? "Run" : "Runs"
            )
            
            // Average pace
            StatItemView(
                value: statistics.avgPaceSecondsPerKm > 0 
                    ? formatPace(statistics.avgPaceSecondsPerKm)
                    : "--:--",
                label: "Avg. pace"
            )
            
            // Total time
            StatItemView(
                value: formatTotalTime(statistics.totalTimeSeconds),
                label: "Time"
            )
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
                        .foregroundStyle(Color.green.gradient)
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
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text(String(format: "%.0f", km))
                                        .font(.caption2)
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
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 220)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(16)
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.run")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No workouts")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text(emptyStateMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            #if DEBUG
            if storageManager.workouts.isEmpty {
                Button("Generate test data") {
                    TestDataGenerator.generateTestWorkouts(storageManager: storageManager)
                }
                .buttonStyle(.borderedProminent)
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

// MARK: - Stat Item View

struct StatItemView: View {
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}
