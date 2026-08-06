import SwiftUI

/// Race fueling plan with 4 collapsible phases (3 days before / race morning /
/// during / post). Auto-generated 14 days pre-race; regenerable via API.
struct RaceFuelingPlanView: View {
    let eventId: UUID

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: RaceFuelingPlanViewModel

    init(eventId: UUID) {
        self.eventId = eventId
        _viewModel = StateObject(wrappedValue: RaceFuelingPlanViewModel(eventId: eventId))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if viewModel.isLoading && viewModel.plan == nil {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                    } else if let plan = viewModel.plan {
                        if let weather = plan.weatherForecast {
                            weatherBanner(weather)
                        }
                        phaseSection(title: "3 days before", phase: plan.threeDaysBefore)
                        phaseSection(title: "Race morning", phase: plan.raceMorning)
                        phaseSection(title: "During the race", phase: plan.duringRace)
                        phaseSection(title: "Post-race", phase: plan.postRace)
                    } else if let err = viewModel.error {
                        VStack(spacing: 12) {
                            Text(err).foregroundStyle(.secondary)
                            Button("Generate plan") { Task { await viewModel.regenerate() } }
                                .buttonStyle(.borderedProminent)
                                .tint(Color.stridePrimary)
                        }.frame(maxWidth: .infinity).padding(.top, 60)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("Race fueling")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.plan != nil {
                        Button { Task { await viewModel.regenerate() } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(viewModel.isLoading)
                    }
                }
            }
        }
        .task { await viewModel.refresh() }
    }

    @ViewBuilder
    private func weatherBanner(_ weather: AnyJSONDict) -> some View {
        let raw = weather.raw
        if let conditions = raw["conditions"] as? String {
            HStack(spacing: 8) {
                Image(systemName: "thermometer.sun")
                    .foregroundStyle(Color.stridePrimary)
                Text(conditions).font(.callout)
                if let h = raw["high_temp_f"] as? Int {
                    Text("\(h)°F").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color.stridePrimary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private func phaseSection(title: String, phase: AnyJSONDict?) -> some View {
        if let phase {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                if let summary = phase.raw["summary"] as? String {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }
                if let items = phase.raw["items"] as? [Any] {
                    ForEach(items.indices, id: \.self) { i in
                        if let item = items[i] as? [String: Any] {
                            phaseItemRow(item: item)
                        }
                    }
                }
            }
            .padding(14)
            .background(Color.gray.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func phaseItemRow(item: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text((item["label"] as? String) ?? "—")
                    .font(.callout.weight(.semibold))
                if let when = item["when"] as? String {
                    Text("· \(when)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let detail = item["detail"] as? String {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineSpacing(2)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - View model

@MainActor
final class RaceFuelingPlanViewModel: ObservableObject {
    let eventId: UUID
    @Published private(set) var plan: RaceFuelingPlanDTO?
    @Published private(set) var isLoading: Bool = false
    @Published var error: String?

    init(eventId: UUID) {
        self.eventId = eventId
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            self.plan = try await APIService.shared.getRaceFuelingPlan(eventId: eventId)
            self.error = nil
        } catch {
            self.error = "No race fueling plan yet — generate one."
        }
    }

    func regenerate() async {
        isLoading = true
        defer { isLoading = false }
        do {
            self.plan = try await APIService.shared.regenerateRaceFuelingPlan(eventId: eventId)
            self.error = nil
        } catch {
            self.error = "Couldn't generate plan."
        }
    }
}
