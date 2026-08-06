import Charts
import SwiftUI

/// Drop-in section for the Stats tab. Renders a 28-day mini-chart per slider
/// (sleep, soreness, motivation, stress) plus a body-area frequency list.
///
/// Add to StatsView with `WellnessTrendsSection()`.
struct WellnessTrendsSection: View {
    @StateObject private var viewModel = WellnessTrendsViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.history.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
            } else if viewModel.history.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .task { await viewModel.refresh() }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No wellness data yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Daily check-ins build the trend coach reads.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle
            chartsGrid
            if !viewModel.frequentAreas.isEmpty {
                areaList
            }
        }
        .padding(16)
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }

    private var sectionTitle: some View {
        HStack {
            Text("Wellness — last 28 days")
                .font(.headline)
            Spacer()
        }
    }

    private var chartsGrid: some View {
        let pairs: [(label: String, values: [WellnessTrendsViewModel.Point])] = [
            ("Sleep", viewModel.sleepSeries),
            ("Soreness", viewModel.sorenessSeries),
            ("Motivation", viewModel.motivationSeries),
            ("Stress", viewModel.stressSeries),
        ]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            ForEach(pairs, id: \.label) { pair in
                VStack(alignment: .leading, spacing: 6) {
                    Text(pair.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    miniChart(values: pair.values)
                }
            }
        }
    }

    @ViewBuilder
    private func miniChart(values: [WellnessTrendsViewModel.Point]) -> some View {
        Chart(values) { point in
            LineMark(
                x: .value("Day", point.date),
                y: .value("Score", point.value)
            )
            .foregroundStyle(Color.stridePrimary)
            .interpolationMethod(.monotone)
            PointMark(
                x: .value("Day", point.date),
                y: .value("Score", point.value)
            )
            .foregroundStyle(Color.stridePrimary)
            .symbolSize(20)
        }
        .chartYScale(domain: 1...5)
        .chartYAxis(.hidden)
        .chartXAxis(.hidden)
        .frame(height: 80)
    }

    private var areaList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Frequent soreness areas")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(viewModel.frequentAreas) { area in
                HStack {
                    Text(area.area.capitalized)
                        .font(.callout)
                    Spacer()
                    Text("\(area.count) days")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - View model

@MainActor
final class WellnessTrendsViewModel: ObservableObject {
    struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let value: Int
    }

    @Published private(set) var history: [WellnessEntryDTO] = []
    @Published private(set) var frequentAreas: [WellnessAreaCount] = []
    @Published private(set) var isLoading: Bool = false

    var sleepSeries: [Point]      { series(\.sleepQuality) }
    var sorenessSeries: [Point]   { series(\.soreness) }
    var motivationSeries: [Point] { series(\.motivation) }
    var stressSeries: [Point]     { series(\.stress) }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let h = APIService.shared.getWellnessHistory(limit: 100)
            async let t = APIService.shared.getWellnessTrends(window: 28)
            self.history = try await h
            self.frequentAreas = try await t.frequentSorenessAreas
        } catch {
            // Silent — Stats section just won't render
        }
    }

    private func series(_ keyPath: KeyPath<WellnessEntryDTO, Int?>) -> [Point] {
        // Only morning entries — they're the canonical full-slider entry.
        history
            .filter { $0.entryMethod == "morning" }
            .compactMap { entry in
                guard let v = entry[keyPath: keyPath] else { return nil }
                return Point(date: entry.submittedAt, value: v)
            }
            .sorted { $0.date < $1.date }
    }
}
