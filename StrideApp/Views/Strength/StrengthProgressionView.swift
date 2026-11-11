import Charts
import SwiftUI

/// Per-exercise progression line chart. Plots best set's score (reps × weight)
/// over the last 10 sessions.
struct StrengthProgressionView: View {
    let exercise: StrengthExerciseDTO

    @Environment(\.dismiss) private var dismiss
    @State private var points: [StrengthProgressionPointDTO] = []
    @State private var isLoading: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerSection
                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else if points.isEmpty {
                        Text("No history yet for \(exercise.name).")
                            .font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else {
                        chartSection
                        listSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle(exercise.name.uppercased())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .strideSecondaryScreen()
        .task { await load() }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exercise.equipment.capitalized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("PROGRESSION")
                .font(.barlowCondensed(size: 43))
        }
    }

    @ViewBuilder
    private var chartSection: some View {
        Chart(points.indices, id: \.self) { i in
            let p = points[i]
            let weight = p.weightKg.map { isDumbbell ? GymSessionModel.dumbbellPounds($0) : $0 } ?? 0
            let score = weight * Double(p.reps)
            BarMark(
                x: .value("Session", i + 1),
                y: .value(isDumbbell ? "Volume (lb each × reps)" : "Volume (kg × reps)", score)
            )
            .foregroundStyle(Color.stridePrimary)
        }
        .frame(height: 180)
        .chartXAxis { AxisMarks() }
    }

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent sets (best per session)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(points.indices.reversed(), id: \.self) { i in
                let p = points[i]
                HStack {
                    Text(p.date ?? "?")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(p.reps) reps × \(p.weightKg.map { GymSessionModel.displayLoad($0, suffix: loadSuffix) } ?? "Bodyweight")")
                        .font(.callout.monospacedDigit())
                    if let rpe = p.rpe {
                        Text("RPE \(rpe)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var isDumbbell: Bool { GymSessionModel.isDumbbell(exercise.name + " " + exercise.equipment) }
    private var loadSuffix: String {
        if isDumbbell { return "lb each" }
        return GymSessionModel.isBarbell(exercise.name + " " + exercise.equipment) ? "kg total incl. bar" : "kg"
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            self.points = try await APIService.shared.getStrengthProgression(exerciseId: exercise.id, limit: 10)
        } catch {
            // Silent
        }
    }
}
