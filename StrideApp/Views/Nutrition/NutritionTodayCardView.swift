import SwiftUI

/// Compact Run-tab nutrition card. Shows today's calorie + carb progress
/// summary; tap → present full TodayNutritionView.
///
/// Drop into RunLobbyView body:
///     NutritionTodayCardView()
struct NutritionTodayCardView: View {
    @StateObject private var viewModel = NutritionViewModel()
    @State private var showFullView = false

    var body: some View {
        Button { showFullView = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "fork.knife")
                    .font(.title3)
                    .foregroundStyle(Color.stridePrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today's fueling")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let today = viewModel.today {
                        Text(summaryLine(today))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Tap to log a meal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.systemBackground))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.15), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .task { await viewModel.refresh() }
        .sheet(isPresented: $showFullView) {
            TodayNutritionView()
                .onDisappear { Task { await viewModel.refresh() } }
        }
    }

    private func summaryLine(_ today: NutritionTodayDTO) -> String {
        let cal = today.totals.calories
        let carbs = Int(today.totals.carbsG)
        let protein = Int(today.totals.proteinG)
        if today.totals.mealCount == 0 {
            return "Tap to log a meal"
        }
        return "\(cal) kcal · C\(carbs)g · P\(protein)g · \(today.totals.mealCount) meals"
    }
}
