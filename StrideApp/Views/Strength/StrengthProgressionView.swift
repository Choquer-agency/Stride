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
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .task { await load() }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exercise.equipment.capitalized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Progression")
                .font(.title2.weight(.semibold))
        }
    }

    @ViewBuilder
    private var chartSection: some View {
        Chart(points.indices, id: \.self) { i in
            let p = points[i]
            let score = (p.weightKg ?? 0) * Double(p.reps)
            BarMark(
                x: .value("Session", i + 1),
                y: .value("Volume (kg × reps)", score)
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
                    Text("\(p.reps) reps × \((p.weightKg.map { String(format: "%.0f", $0) } ?? "BW")) kg")
                        .font(.callout.monospacedDigit())
                    if let rpe = p.rpe {
                        Text("RPE \(rpe)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
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
