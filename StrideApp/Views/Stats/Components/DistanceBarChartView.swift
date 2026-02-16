import SwiftUI
import Charts

// MARK: - Chart Scale Filter
enum DistanceChartScale: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case quarter = "Quarter"
    case year = "Year"
    case allTime = "All Time"

    var id: String { rawValue }
}

struct DistanceBarChartView: View {
    let runLogs: [RunLog]

    @State private var selectedScale: DistanceChartScale = .week

    // MARK: - Bucket Model
    private struct ChartBucket: Identifiable {
        let id: String          // label used as x-axis value
        let distance: Double    // total completed distance in km
        let isCurrent: Bool     // highlights the current period
    }

    // MARK: - Aggregated Data
    private var chartData: [ChartBucket] {
        switch selectedScale {
        case .week:
            return weekBuckets()
        case .month:
            return monthBuckets()
        case .quarter:
            return quarterBuckets()
        case .year:
            return yearBuckets()
        case .allTime:
            return allTimeBuckets()
        }
    }

    // MARK: - Rolling Average (4-bucket)
    private var rollingAverage: [Double] {
        let distances = chartData.map { $0.distance }
        guard distances.count >= 4 else { return [] }

        var averages: [Double] = []
        for i in 0..<distances.count {
            let start = max(0, i - 3)
            let end = min(distances.count, i + 1)
            let slice = Array(distances[start..<end])
            let avg = slice.reduce(0, +) / Double(slice.count)
            averages.append(avg)
        }
        return averages
    }

    // MARK: - Body
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with picker
            HStack {
                Text("Distance Over Time")
                    .font(.inter(size: 18, weight: .semibold))

                Spacer()

                Picker("Scale", selection: $selectedScale) {
                    ForEach(DistanceChartScale.allCases) { scale in
                        Text(scale.rawValue).tag(scale)
                    }
                }
                .tint(.stridePrimary)
            }

            // Chart
            Chart {
                ForEach(Array(chartData.enumerated()), id: \.element.id) { index, bucket in
                    BarMark(
                        x: .value("Period", bucket.id),
                        y: .value("Distance", bucket.distance)
                    )
                    .foregroundStyle(
                        bucket.isCurrent
                            ? Color.stridePrimary
                            : Color.stridePrimary.opacity(0.55)
                    )
                    .cornerRadius(4)
                }

                // Rolling average line
                if !rollingAverage.isEmpty {
                    ForEach(Array(rollingAverage.enumerated()), id: \.offset) { index, avg in
                        LineMark(
                            x: .value("Period", chartData[index].id),
                            y: .value("Average", avg)
                        )
                        .foregroundStyle(Color.stridePrimary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                    }
                }
            }
            .frame(height: 200)
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            if selectedScale == .month {
                                let ids = chartData.map { $0.id }
                                if let idx = ids.firstIndex(of: label),
                                   idx % 5 == 0 {
                                    Text(label)
                                        .font(.inter(size: 9))
                                } else {
                                    Text("")
                                }
                            } else {
                                Text(label)
                                    .font(.inter(size: 9))
                            }
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let intValue = value.as(Double.self) {
                            Text("\(Int(intValue))")
                                .font(.inter(size: 10))
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(hex: "F9F9F9"))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Helper: sum distance for runLogs in a date range
    private func distanceInRange(from start: Date, to end: Date) -> Double {
        let calendar = Calendar.current
        return runLogs
            .filter { runLog in
                let d = calendar.startOfDay(for: runLog.completedAt)
                return d >= start && d < end
            }
            .reduce(0.0) { $0 + $1.distanceKm }
    }

    // MARK: - Week: Last 7 individual days (including today)
    private func weekBuckets() -> [ChartBucket] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let labelFormatter = DateFormatter()
        labelFormatter.dateFormat = "EEE"

        var buckets: [ChartBucket] = []

        for daysBack in stride(from: 6, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -daysBack, to: today) else { continue }
            let dayStart = calendar.startOfDay(for: day)
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }

            let distance = distanceInRange(from: dayStart, to: dayEnd)
            let label = labelFormatter.string(from: day).uppercased()
            let isCurrent = (daysBack == 0)

            buckets.append(ChartBucket(id: label, distance: distance, isCurrent: isCurrent))
        }

        return buckets
    }

    // MARK: - Month: Last 30 individual days
    private func monthBuckets() -> [ChartBucket] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var buckets: [ChartBucket] = []

        for daysBack in stride(from: 29, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -daysBack, to: today) else { continue }
            let dayStart = calendar.startOfDay(for: day)
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }

            let distance = distanceInRange(from: dayStart, to: dayEnd)
            let isCurrent = (daysBack == 0)

            let monthDay = DateFormatter()
            monthDay.dateFormat = "M/d"
            let uniqueId = monthDay.string(from: day)

            buckets.append(ChartBucket(id: uniqueId, distance: distance, isCurrent: isCurrent))
        }

        return buckets
    }

    // MARK: - Quarter: Weeks over past 3 months (~13 weeks)
    private func quarterBuckets() -> [ChartBucket] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday
        let today = calendar.startOfDay(for: Date())

        let labelFormatter = DateFormatter()
        labelFormatter.dateFormat = "M/d"

        var buckets: [ChartBucket] = []

        for weeksBack in stride(from: 12, through: 0, by: -1) {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -weeksBack, to: today),
                  let mondayOfWeek = calendar.dateInterval(of: .weekOfYear, for: weekStart)?.start,
                  let endOfWeek = calendar.date(byAdding: .day, value: 7, to: mondayOfWeek) else {
                continue
            }

            let distance = distanceInRange(from: mondayOfWeek, to: endOfWeek)
            let label = labelFormatter.string(from: mondayOfWeek).uppercased()
            let isCurrent = (weeksBack == 0)

            buckets.append(ChartBucket(id: label, distance: distance, isCurrent: isCurrent))
        }

        return buckets
    }

    // MARK: - Year: Every month over past 12 months
    private func yearBuckets() -> [ChartBucket] {
        let calendar = Calendar.current
        let today = Date()
        let currentMonth = calendar.dateComponents([.year, .month], from: today)

        let labelFormatter = DateFormatter()
        labelFormatter.dateFormat = "MMM"

        var buckets: [ChartBucket] = []

        for monthsBack in stride(from: 11, through: 0, by: -1) {
            guard let bucketDate = calendar.date(byAdding: .month, value: -monthsBack, to: today),
                  let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: bucketDate)),
                  let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
                continue
            }

            let distance = distanceInRange(from: monthStart, to: monthEnd)
            let label = labelFormatter.string(from: monthStart).uppercased()
            let bucketComponents = calendar.dateComponents([.year, .month], from: monthStart)
            let isCurrent = (bucketComponents.year == currentMonth.year && bucketComponents.month == currentMonth.month)

            buckets.append(ChartBucket(id: label, distance: distance, isCurrent: isCurrent))
        }

        return buckets
    }

    // MARK: - All Time: Yearly buckets since earliest run
    private func allTimeBuckets() -> [ChartBucket] {
        let calendar = Calendar.current
        let today = Date()
        let currentYear = calendar.component(.year, from: today)

        let earliestYear: Int = {
            if let earliest = runLogs.min(by: { $0.completedAt < $1.completedAt }) {
                return calendar.component(.year, from: earliest.completedAt)
            }
            return currentYear
        }()

        var buckets: [ChartBucket] = []

        for year in earliestYear...currentYear {
            guard let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
                  let yearEnd = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else {
                continue
            }

            let distance = distanceInRange(from: yearStart, to: yearEnd)
            let isCurrent = (year == currentYear)

            buckets.append(ChartBucket(id: "\(year)", distance: distance, isCurrent: isCurrent))
        }

        return buckets
    }
}

#Preview {
    DistanceBarChartView(runLogs: [])
        .padding()
}
