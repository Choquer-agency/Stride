import SwiftUI
import Charts

enum DistanceChartScale: String, CaseIterable, Identifiable {
    case week = "This Week", month = "4 Weeks", quarter = "12 Weeks", year = "12 Months", allTime = "All Time"
    var id: String { rawValue }
}

struct DistanceBarChartView: View {
    let runLogs: [RunLog]
    var plan: TrainingPlan? = nil
    @State private var selectedScale: DistanceChartScale = .quarter
    @State private var selectedBucket: String?

    private struct Bucket: Identifiable {
        let id: String
        let label: String
        let actual: Double
        let planned: Double
        let current: Bool
    }

    private func buckets() -> [Bucket] {
        let calendar = StatsTrainingData.calendar()
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let workouts = plan?.weeks.flatMap(\.workouts).filter { $0.workoutType.isRunnable } ?? []
        let formatter = DateFormatter()
        let starts: [Date]
        let component: Calendar.Component
        switch selectedScale {
        case .week:
            let monday = StatsTrainingData.week(containing: now).start
            starts = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
            component = .day; formatter.dateFormat = "EEE"
        case .month, .quarter:
            let count = selectedScale == .month ? 4 : 12
            let monday = StatsTrainingData.week(containing: now).start
            starts = (0..<count).reversed().compactMap { calendar.date(byAdding: .weekOfYear, value: -$0, to: monday) }
            component = .weekOfYear; formatter.dateFormat = "MMM d"
        case .year:
            let month = calendar.dateInterval(of: .month, for: now)!.start
            starts = (0..<12).reversed().compactMap { calendar.date(byAdding: .month, value: -$0, to: month) }
            component = .month; formatter.dateFormat = "MMM"
        case .allTime:
            let year = calendar.component(.year, from: now)
            let first = min(year, runLogs.map { calendar.component(.year, from: $0.completedAt) }.min() ?? year)
            starts = (first...year).compactMap { calendar.date(from: DateComponents(year: $0, month: 1, day: 1)) }
            component = .year; formatter.dateFormat = "yyyy"
        }
        return starts.map { start in
            let end = calendar.date(byAdding: component, value: 1, to: start)!
            let actual = runLogs.filter { $0.completedAt >= start && $0.completedAt < end && $0.completedAt <= now }.reduce(0) { $0 + $1.distanceKm }
            let planned = workouts.filter { $0.date >= start && $0.date < end }.reduce(0) { $0 + ($1.distanceKm ?? 0) }
            return Bucket(id: String(start.timeIntervalSince1970), label: formatter.string(from: start),
                actual: actual, planned: planned, current: today >= start && today < end)
        }
    }

    var body: some View {
        let data = buckets()
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(plan == nil ? "Distance Over Time" : "Distance vs Plan").font(.inter(size: 18, weight: .semibold))
                Spacer()
                Menu {
                    Picker("Period", selection: $selectedScale) {
                        ForEach(DistanceChartScale.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(selectedScale.rawValue)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                    }
                    .font(.inter(size: 12, weight: .medium))
                    .foregroundStyle(Color.stridePrimary)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Color.stridePrimary.opacity(0.07), in: Capsule())
                }
                .accessibilityLabel("Chart period: \(selectedScale.rawValue)")
            }
            HStack(spacing: 18) {
                legend("Completed", color: .stridePrimary)
                if plan != nil { legend("Planned", color: Color(red: 0.92, green: 0.73, blue: 0.32)) }
                Spacer()
                Text("km").font(.inter(size: 11)).foregroundStyle(.secondary)
            }
            Chart {
                ForEach(data) { bucket in
                    if plan != nil {
                        BarMark(x: .value("Period", bucket.id), yStart: .value("Start", 0), yEnd: .value("Planned", bucket.planned), width: .ratio(0.8))
                            .foregroundStyle(Color(red: 0.92, green: 0.73, blue: 0.32).opacity(0.65)).cornerRadius(4)
                    }
                    BarMark(x: .value("Period", bucket.id), yStart: .value("Start", 0), yEnd: .value("Completed", bucket.actual), width: .ratio(0.8))
                        .foregroundStyle(Color.stridePrimary).cornerRadius(3)
                    if selectedBucket == bucket.id {
                        RuleMark(x: .value("Selected", bucket.id)).foregroundStyle(Color.secondary.opacity(0.25))
                    }
                }
            }
            .chartXSelection(value: $selectedBucket)
            .chartXAxis {
                AxisMarks(values: data.map(\.id)) { value in
                    AxisValueLabel {
                        if let id = value.as(String.self), let index = data.firstIndex(where: { $0.id == id }),
                           data.count <= 7 || index % 2 == 0 {
                            Text(data[index].label).font(.inter(size: 9))
                        }
                    }
                }
            }
            .chartYAxis { AxisMarks { AxisGridLine(); AxisValueLabel().font(.inter(size: 10)) } }
            .frame(height: 190)
            if let selected = data.first(where: { $0.id == selectedBucket }) {
                Text("\(selected.label) · \(String(format: "%.1f", selected.actual)) km completed" + (plan == nil ? "" : " / \(String(format: "%.1f", selected.planned)) km planned") + (selected.current ? " · In progress" : ""))
                    .font(.inter(size: 11, weight: .medium))
            } else {
                Text("Tap a bar to compare saved runs with the plan. The current period is still in progress.")
                    .font(.inter(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(18).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) { RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10); Text(title).font(.inter(size: 11)).foregroundStyle(.secondary) }
    }
}
