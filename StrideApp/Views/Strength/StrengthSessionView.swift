import SwiftUI

/// Detailed session log — exercise picker + sets table.
/// Phase 9 v1 keeps the per-set entry minimal; Phase 9.1 adds last-set pre-fill.
struct StrengthSessionView: View {
    @ObservedObject var viewModel: StrengthViewModel
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var workoutSets: [SetEntry] = []
    @State private var showLibrary = false
    @State private var durationMinutes: String = ""
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercises") {
                    if workoutSets.isEmpty {
                        Text("Tap + to add an exercise.").foregroundStyle(.secondary).font(.callout)
                    } else {
                        ForEach(workoutSets) { entry in
                            setRow(for: entry)
                        }
                        .onDelete { indices in
                            workoutSets.remove(atOffsets: indices)
                        }
                    }
                    Button {
                        showLibrary = true
                    } label: {
                        Label("Add exercise", systemImage: "plus.circle")
                    }
                }
                Section("Session") {
                    HStack { Text("Duration"); Spacer(); TextField("min", text: $durationMinutes).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
                if let err = viewModel.error {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
            .navigationTitle("Log details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .disabled(workoutSets.isEmpty || viewModel.isSubmitting)
                }
            }
        }
        .task { await viewModel.loadLibrary() }
        .sheet(isPresented: $showLibrary) {
            ExerciseLibraryView(viewModel: viewModel) { exercise in
                workoutSets.append(SetEntry(
                    exercise: exercise,
                    setNumber: nextSetNumber(for: exercise.id),
                ))
                showLibrary = false
            }
        }
    }

    // MARK: - Set row

    private func setRow(for entry: SetEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.exercise.name).font(.callout.weight(.medium))
                Spacer()
                Text("Set \(entry.setNumber)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                tinyField(label: "reps", text: bindingFor(\SetEntry.reps, entry.id))
                tinyField(label: "kg", text: bindingFor(\SetEntry.weight, entry.id))
                tinyField(label: "rpe", text: bindingFor(\SetEntry.rpe, entry.id))
            }
        }
        .padding(.vertical, 4)
    }

    private func tinyField(label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.tertiary)
            TextField("", text: text)
                .keyboardType(.decimalPad)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .frame(maxWidth: .infinity)
    }

    private func bindingFor(_ keyPath: WritableKeyPath<SetEntry, String>, _ id: UUID) -> Binding<String> {
        Binding(
            get: { workoutSets.first(where: { $0.id == id })?[keyPath: keyPath] ?? "" },
            set: { newValue in
                if let idx = workoutSets.firstIndex(where: { $0.id == id }) {
                    workoutSets[idx][keyPath: keyPath] = newValue
                }
            }
        )
    }

    private func nextSetNumber(for exerciseId: UUID) -> Int {
        let count = workoutSets.filter { $0.exercise.id == exerciseId }.count
        return count + 1
    }

    private func save() async {
        let setsPayload: [[String: Any]] = workoutSets.compactMap { entry -> [String: Any]? in
            guard let reps = Int(entry.reps), reps > 0 else { return nil }
            var d: [String: Any] = [
                "exercise_id": entry.exercise.id.uuidString.lowercased(),
                "set_number": entry.setNumber,
                "reps": reps,
            ]
            if let w = Double(entry.weight) { d["weight_kg"] = w }
            if let r = Int(entry.rpe) { d["rpe"] = r }
            return d
        }
        let dur = Int(durationMinutes)
        let n = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
        let ok = await viewModel.detailedLog(sets: setsPayload, duration: dur, notes: n)
        if ok { onDone(); dismiss() }
    }
}

/// Local-only model for in-progress set entries (before submit).
struct SetEntry: Identifiable {
    let id = UUID()
    let exercise: StrengthExerciseDTO
    let setNumber: Int
    var reps: String = ""
    var weight: String = ""
    var rpe: String = ""
}
