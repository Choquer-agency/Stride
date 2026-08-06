import SwiftUI

/// Race-prep logistics checklist. Surfaced from
/// `stride://race-prep/checklist/{event_id}` and from race-prep entry/review push.
///
/// Renders by category, with checkable items + weather banner + A/B/C goals.
/// Items toggle optimistically and PATCH server-side.
struct RacePrepChecklistView: View {
    let eventId: UUID

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: RacePrepChecklistViewModel

    init(eventId: UUID) {
        self.eventId = eventId
        _viewModel = StateObject(wrappedValue: RacePrepChecklistViewModel(eventId: eventId))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if viewModel.isLoading && viewModel.checklist == nil {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                    } else if let cl = viewModel.checklist {
                        if let weather = cl.weatherForecast {
                            weatherBanner(weather)
                        }
                        goalsSection
                        ForEach(viewModel.itemsByCategory, id: \.category) { group in
                            categorySection(category: group.category, items: group.items, indices: group.indices)
                        }
                    } else if let err = viewModel.error {
                        VStack(spacing: 12) {
                            Text(err).foregroundStyle(.secondary)
                            Button("Generate checklist") { Task { await viewModel.regenerate() } }
                                .buttonStyle(.borderedProminent)
                                .tint(Color.stridePrimary)
                        }.frame(maxWidth: .infinity).padding(.top, 60)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("Race checklist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.checklist != nil {
                        Button { Task { await viewModel.regenerate() } } label: {
                            Image(systemName: "arrow.clockwise")
                        }.disabled(viewModel.isLoading)
                    }
                }
            }
        }
        .task { await viewModel.refresh() }
    }

    // MARK: - Sections

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

    private var goalsSection: some View {
        let cl = viewModel.checklist
        return VStack(alignment: .leading, spacing: 8) {
            Text("Goals")
                .font(.headline)
            HStack(spacing: 12) {
                goalTile(label: "A", seconds: cl?.aGoalSeconds, color: Color.green)
                goalTile(label: "B", seconds: cl?.bGoalSeconds, color: Color.stridePrimary)
                goalTile(label: "C", seconds: cl?.cGoalSeconds, color: Color.gray)
            }
        }
    }

    private func goalTile(label: String, seconds: Int?, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(color)
            Text(seconds.map(formatTime) ?? "—")
                .font(.callout.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func formatTime(_ s: Int) -> String {
        let h = s / 3600
        let m = (s % 3600) / 60
        return h > 0 ? String(format: "%d:%02d", h, m) : String(format: "%dm", m)
    }

    private func categorySection(category: String, items: [RaceLogisticsItemDTO], indices: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(category.capitalized)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ForEach(items.indices, id: \.self) { i in
                checklistRow(item: items[i], absoluteIndex: indices[i])
            }
        }
    }

    private func checklistRow(item: RaceLogisticsItemDTO, absoluteIndex: Int) -> some View {
        Button {
            Task { await viewModel.toggleItem(at: absoluteIndex, completed: !item.completed) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.completed ? Color.stridePrimary : Color.gray.opacity(0.5))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.label)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .strikethrough(item.completed, color: .secondary)
                    if let detail = item.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                    }
                    if let note = item.athleteNote, !note.isEmpty {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .italic()
                    }
                }
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - View model

@MainActor
final class RacePrepChecklistViewModel: ObservableObject {
    let eventId: UUID
    @Published private(set) var checklist: RaceLogisticsChecklistDTO?
    @Published private(set) var isLoading: Bool = false
    @Published var error: String?

    init(eventId: UUID) {
        self.eventId = eventId
    }

    var itemsByCategory: [(category: String, items: [RaceLogisticsItemDTO], indices: [Int])] {
        guard let cl = checklist else { return [] }
        var groups: [String: (items: [RaceLogisticsItemDTO], indices: [Int])] = [:]
        for (i, item) in cl.items.enumerated() {
            let cat = item.category ?? "other"
            var entry = groups[cat] ?? (items: [], indices: [])
            entry.items.append(item)
            entry.indices.append(i)
            groups[cat] = entry
        }
        let order = ["gear", "timing", "hydration", "course", "pacing", "mental", "travel", "post_race", "other"]
        return order.compactMap { c in
            groups[c].map { (category: c, items: $0.items, indices: $0.indices) }
        }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            self.checklist = try await APIService.shared.getRaceLogisticsChecklist(eventId: eventId)
            self.error = nil
        } catch {
            self.error = "No checklist yet — tap to generate."
        }
    }

    func regenerate() async {
        isLoading = true
        defer { isLoading = false }
        do {
            self.checklist = try await APIService.shared.regenerateRaceLogisticsChecklist(eventId: eventId)
            self.error = nil
        } catch {
            self.error = "Couldn't generate checklist."
        }
    }

    func toggleItem(at index: Int, completed: Bool) async {
        do {
            self.checklist = try await APIService.shared.toggleRaceLogisticsItem(
                eventId: eventId,
                itemIndex: index,
                completed: completed,
            )
        } catch {
            // Surface but don't block
            self.error = "Couldn't update item — try again."
        }
    }
}
