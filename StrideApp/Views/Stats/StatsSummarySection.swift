import SwiftUI
import Charts

struct StatsSummarySection: View {
    let viewModel: StatsViewModel
    var body: some View {
        let weekly = viewModel.currentWeekStats
        let interval = StatsTrainingData.week(containing: Date())
        let runs = viewModel.runLogs.filter { $0.completedAt >= interval.start && $0.completedAt < interval.end }.count
        VStack(alignment: .leading, spacing: 12) {
            RaceGoalBanner(plan: viewModel.plan)
            HStack {
                Text("Your training, at a glance").font(.inter(size: 18, weight: .semibold))
                Spacer()
            }.padding(.top, 10)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCardView(title: "This Week", value: weekly.displayText,
                    subtitle: "Monday–Sunday · \(Int(weekly.percentage))% of plan")
                StatCardView(title: "Runs This Week", value: "\(runs)", subtitle: "Completed runs")
                StatCardView(title: "Year to Date", value: String(format: "%.0f km", viewModel.yearToDateDistance),
                    subtitle: "Recorded in \(Calendar.current.component(.year, from: Date()))")
                StatCardView(title: "4-Week Average", value: String(format: "%.1f km", viewModel.rolling4WeekAverage),
                    subtitle: "Last 4 completed weeks")
            }
            if weekly.planned > 0 {
                ProgressView(value: min(weekly.completed / weekly.planned, 1)).tint(.stridePrimary)
                Text(weekly.completed >= weekly.planned ? "Weekly distance target reached." : String(format: "%.1f km remaining in this week’s plan. This week is still in progress.", max(0, weekly.planned - weekly.completed)))
                    .font(.inter(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}

struct RaceGoalBanner: View {
    let plan: TrainingPlan
    var body: some View {
        HStack(spacing: 16) {
            FlagIconView(size: 32, color: .white)
            VStack(alignment: .leading, spacing: 6) {
                Text("WORKING TOWARD").font(.inter(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                Text(plan.raceName ?? plan.displayDistance).font(.inter(size: 19, weight: .semibold))
                Text(plan.raceDate.formatted(.dateTime.month(.wide).day().year()))
                    .font(.inter(size: 12)).foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 4)
            VStack(spacing: 0) {
                let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: plan.raceDate)).day ?? 0
                Text(days >= 0 ? "\(days)" : "Finished").font(.barlowCondensed(size: days >= 0 ? 44 : 24, weight: .semibold))
                Text(days >= 0 ? "DAYS TO GO" : "RACE DAY PASSED").font(.inter(size: 8, weight: .semibold))
            }
        }
        .foregroundStyle(.white).padding(20)
        .background(LinearGradient(colors: [.stridePrimary, .strideDarkRed], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20))
    }
}

struct StatsSummarySectionNoPlan: View {
    let weeklyStats: WeeklyDistanceStats
    let yearToDate: Double
    let fourWeekAverage: Double
    var onRaceCountdownTap: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCardView(title: "This Week", value: weeklyStats.displayText, subtitle: "Monday–Sunday")
                StatCardView(title: "Year to Date", value: String(format: "%.0f km", yearToDate), subtitle: "Recorded distance")
                StatCardView(title: "4-Week Average", value: String(format: "%.1f km", fourWeekAverage), subtitle: "Last 4 completed weeks")
                Button(action: { onRaceCountdownTap?() }) {
                    StatCardView(title: "Next Goal", value: "Set a race", subtitle: "Build your training plan")
                }.buttonStyle(.plain)
            }
        }
    }
}

struct TrainingTrendsSection: View {
    let summaries: [TrainingInsightSummary]
    private var summary: TrainingInsightSummary { summaries[0] }
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Heart Rate Trend", systemImage: "heart.fill")
                    .font(.inter(size: 18, weight: .semibold)).foregroundStyle(Color.heartRatePink)
                Text("Easy, long and recovery runs · weekly averages")
                    .font(.inter(size: 11)).foregroundStyle(.secondary)
                if summaries.contains(where: { $0.weeks.contains { $0.heartRate != nil } }) {
                    Chart {
                        ForEach(summaries.indices, id: \.self) { index in
                            let series = summaries[index]
                            ForEach(series.weeks.filter { $0.heartRate != nil }) { point in
                                LineMark(x: .value("Week", point.start), y: .value("HR", point.heartRate!),
                                         series: .value("Run type", typeLabel(series)))
                                    .foregroundStyle(by: .value("Run type", typeLabel(series)))
                                    .lineStyle(StrokeStyle(lineWidth: 2))
                                PointMark(x: .value("Week", point.start), y: .value("HR", point.heartRate!))
                                    .foregroundStyle(by: .value("Run type", typeLabel(series)))
                                    .symbol(by: .value("Run type", typeLabel(series))).symbolSize(28)
                            }
                        }
                    }
                    .chartForegroundStyleScale(domain: ["Easy", "Long", "Recovery"], range: seriesColors)
                    .chartSymbolScale(domain: ["Easy", "Long", "Recovery"], range: [.circle, .square, .triangle])
                    .chartLegend(.hidden)
                    .chartYScale(domain: hrDomain)
                    .chartXScale(domain: dateDomain, range: .plotDimension(padding: 20))
                    .chartXAxis(.hidden)
                    .chartYAxis { AxisMarks { AxisGridLine(); AxisValueLabel().font(.inter(size: 10)) } }
                    .frame(height: 150)
                    trendDates
                    HStack(spacing: 16) {
                        ForEach(summaries.indices, id: \.self) { index in
                            HStack(spacing: 5) {
                                Image(systemName: ["circle.fill", "square.fill", "triangle.fill"][index])
                                    .font(.system(size: 8)).foregroundStyle(seriesColors[index])
                                Text(typeLabel(summaries[index])).font(.inter(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Text("Recorded heart rate will build these trends. Missing readings aren’t treated as zero.")
                        .font(.inter(size: 13)).foregroundStyle(.secondary)
                }
                ForEach(summaries.indices, id: \.self) { index in
                    let series = summaries[index]
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(typeLabel(series)).foregroundStyle(seriesColors[index])
                            Spacer()
                            Text(series.recentHR.map { String(format: "%.0f bpm", $0) } ?? "No recent HR")
                            if let pace = series.recentPace {
                                Text("· \(paceText(pace))/km").foregroundStyle(.secondary)
                            }
                        }.font(.inter(size: 12, weight: .semibold))
                        Text(hrInsight(series)).font(.inter(size: 11)).foregroundStyle(.secondary)
                        if let range = series.inRangePercent {
                            Text(String(format: "%.0f%% of recorded time in %d–%d bpm", range, series.heartRateRange.lowerBound, series.heartRateRange.upperBound))
                                .font(.inter(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                }
                Text("Last 14 days compared with the previous 14, within each run type. Pace, hills and heat affect heart rate.")
                    .font(.inter(size: 10)).foregroundStyle(.secondary)
            }.trendCard()

            VStack(alignment: .leading, spacing: 14) {
                Label("How Runs Feel", systemImage: "face.smiling")
                    .font(.inter(size: 18, weight: .semibold))
                if let feeling = summary.recentFeeling {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        trendMetric(String(format: "%.1f", feeling), label: "out of 5", color: .orange)
                        Text(feelingInsight).font(.inter(size: 13, weight: .medium))
                    }
                    let points = summary.weeks.filter { $0.feeling != nil }
                    Chart(points) { point in
                        LineMark(x: .value("Week", point.start), y: .value("Feeling", point.feeling!))
                            .foregroundStyle(Color.orange).lineStyle(StrokeStyle(lineWidth: 2))
                        PointMark(x: .value("Week", point.start), y: .value("Feeling", point.feeling!))
                            .foregroundStyle(Color.orange).symbolSize(25)
                    }
                    .chartYScale(domain: 0...5)
                    .chartXScale(domain: dateDomain, range: .plotDimension(padding: 20))
                    .chartXAxis(.hidden)
                    .chartYAxis { AxisMarks(values: [0, 3, 5]) { AxisGridLine(); AxisValueLabel().font(.inter(size: 10)) } }
                    .frame(height: 120)
                    trendDates
                    Text("\(summary.ratedCount) rated runs in the last 14 days. Unrated runs are excluded.").font(.inter(size: 10)).foregroundStyle(.secondary)
                } else {
                    Text("Your post-run ratings will show whether training is feeling better or harder over time.")
                        .font(.inter(size: 13)).foregroundStyle(.secondary)
                }
                Text("0 Terrible  ·  3 Okay  ·  5 Amazing. Higher means you felt better; this is not RPE.")
                    .font(.inter(size: 10)).foregroundStyle(.secondary)
            }.trendCard()
        }
    }
    private let seriesColors: [Color] = [.heartRatePink, .purple, .teal]
    private var trendDates: some View {
        GeometryReader { geometry in
            ForEach(dateTicks, id: \.self) { date in
                let fraction = date.timeIntervalSince(dateDomain.lowerBound) / max(1, dateDomain.upperBound.timeIntervalSince(dateDomain.lowerBound))
                Text(date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.inter(size: 10)).foregroundStyle(.secondary).fixedSize()
                    .position(x: 20 + max(0, geometry.size.width - 64) * fraction, y: 7)
            }
        }.frame(height: 14)
    }
    private var dateDomain: ClosedRange<Date> {
        let end = summary.weeks.last?.start ?? Date()
        return (summary.weeks.first?.start ?? end.addingTimeInterval(-7 * 86400))...end
    }
    private var dateTicks: [Date] {
        let dates = summary.weeks.map(\.start)
        return [0, 2, 5, 7].filter { dates.indices.contains($0) }.map { dates[$0] }
    }
    private func typeLabel(_ series: TrainingInsightSummary) -> String {
        series.heartRateType == .longRun ? "Long" : series.heartRateType == .recovery ? "Recovery" : "Easy"
    }
    private var hrDomain: ClosedRange<Double> {
        let values = summaries.flatMap { $0.weeks.compactMap(\.heartRate) }
        return max(0, (values.min() ?? 130) - 5)...max((values.max() ?? 147) + 5, (values.min() ?? 130) + 1)
    }
    private func hrInsight(_ series: TrainingInsightSummary) -> String {
        guard let recent = series.recentHR, let previous = series.previousHR,
              series.recentHRCount >= 2, series.previousHRCount >= 2,
              let pace = series.recentPace, let oldPace = series.previousPace else {
            return "\(series.recentHRCount) recent runs with HR · building a comparison baseline."
        }
        let delta = recent - previous, paceDelta = pace - oldPace
        let description = abs(delta) < 1 ? "Similar heart rate" : String(format: "%.0f bpm %@", abs(delta), delta < 0 ? "lower" : "higher")
        let context = abs(paceDelta) <= 10 ? "at a similar average pace" : (paceDelta > 0 ? "alongside a slower average pace" : "alongside a faster average pace")
        return "\(description) \(context)."
    }
    private var feelingInsight: String {
        guard let recent = summary.recentFeeling, let prior = summary.previousFeeling else { return "Building your personal baseline" }
        let delta = recent - prior
        return abs(delta) < 0.1 ? "Similar to the previous 14 days" : String(format: "%.1f points %@ than the previous 14 days", abs(delta), delta > 0 ? "higher" : "lower")
    }
    private func trendMetric(_ value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.barlowCondensed(size: 32, weight: .medium)).foregroundStyle(color)
            Text(label).font(.inter(size: 10)).foregroundStyle(.secondary)
        }
    }
    private func paceText(_ value: Double) -> String { String(format: "%d:%02d", Int(value.rounded()) / 60, Int(value.rounded()) % 60) }
}

private extension View {
    func trendCard() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}
