import SwiftUI

/// Today's nutrition overview — progress rings, hydration counter, meal timeline.
/// Surfaced as full-screen view from Run tab nutrition card and Profile→Nutrition.
struct TodayNutritionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = NutritionViewModel()
    @State private var showLogHub = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let today = viewModel.today {
                        progressRings(today: today)
                        hydrationRow
                        mealsTimeline(today: today)
                        if let gap = today.gap, gap.anyShortfall {
                            gapBanner
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 60)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("Today's fueling")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showLogHub = true } label: { Image(systemName: "plus.circle.fill") }
                }
            }
        }
        .task { await viewModel.refresh() }
        .sheet(isPresented: $showLogHub) {
            NutritionLogHubView()
                .onDisappear { Task { await viewModel.refresh() } }
        }
    }

    // MARK: - Sections

    private func progressRings(today: NutritionTodayDTO) -> some View {
        let cal = today.totals.calories
        let calFloor = today.targets.calorieFloorLeaSafety
        let carbs = today.totals.carbsG
        let carbFloor = today.targets.carbsGFloor
        let protein = today.totals.proteinG
        let proteinFloor = today.targets.proteinGFloor
        let fat = today.totals.fatG
        let fatFloor = today.targets.fatGFloor

        return VStack(alignment: .leading, spacing: 12) {
            Text("Progress")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ringTile(label: "Calories", current: Double(cal), floor: Double(calFloor), unit: "kcal")
                ringTile(label: "Carbs", current: carbs, floor: carbFloor, unit: "g")
                ringTile(label: "Protein", current: protein, floor: proteinFloor, unit: "g")
                ringTile(label: "Fat", current: fat, floor: fatFloor, unit: "g")
            }
        }
    }

    private func ringTile(label: String, current: Double, floor: Double, unit: String) -> some View {
        let pct = floor > 0 ? min(1.0, current / floor) : 0.0
        return VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: pct)
                    .stroke(Color.stridePrimary, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack {
                    Text("\(Int(current))").font(.headline.monospacedDigit())
                    Text("of \(Int(floor)) \(unit)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 110, height: 110)
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
    }

    private var hydrationRow: some View {
        HStack(spacing: 12) {
            Label("Hydration", systemImage: "drop.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.stridePrimary)
            Spacer()
            Text("\((viewModel.hydration?.glassesLogged ?? 0)) glasses")
                .font(.callout.monospacedDigit())
            Button {
                Task { await viewModel.addHydration(glasses: 1) }
            } label: {
                Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(Color.stridePrimary)
            }
        }
        .padding(14)
        .background(Color.stridePrimary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func mealsTimeline(today: NutritionTodayDTO) -> some View {
        let meals = today.totals.meals ?? []
        return VStack(alignment: .leading, spacing: 8) {
            Text("Meals today (\(meals.count))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if meals.isEmpty {
                Text("No meals logged yet.").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(meals) { meal in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meal.mealType.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.callout.weight(.medium))
                            Text("\(meal.totalCalories) kcal · C\(Int(meal.totalCarbsG))g P\(Int(meal.totalProteinG))g")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.gray.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var gapBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill").foregroundStyle(.orange)
            Text("Fueling shortfall — coach has tonight's note.")
                .font(.callout)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
