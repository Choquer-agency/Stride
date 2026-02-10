// ============================================================
// TEMP: DELETE THIS ENTIRE FILE after correcting the run data.
// ============================================================

import SwiftUI
import SwiftData

struct TempWorkoutEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Query all completed workouts, most recent first
    @Query(
        filter: #Predicate<Workout> { $0.isCompleted },
        sort: \Workout.date,
        order: .reverse
    ) private var completedWorkouts: [Workout]

    @State private var selectedWorkout: Workout?
    @State private var showEditor = false
    @State private var workoutToDelete: Workout?
    @State private var showDeleteConfirmation = false

    var body: some View {
        List {
            Section {
                Text("Select the workout to edit, or swipe left to delete. This screen is temporary — delete TempWorkoutEditView.swift when done.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Completed Runs") {
                ForEach(completedWorkouts) { workout in
                    Button {
                        selectedWorkout = workout
                        showEditor = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workout.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(workout.formattedDate + " — " + workout.dayOfWeek)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                if let dist = workout.actualDistanceKm {
                                    Text(String(format: "%.2f km", dist))
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(.primary)
                                }
                                if let dur = workout.actualDurationSeconds {
                                    Text(formatDuration(dur))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            workoutToDelete = workout
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Edit Run Data")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showEditor) {
            if let workout = selectedWorkout {
                TempWorkoutEditorSheet(workout: workout) {
                    try? modelContext.save()
                    showEditor = false
                }
            }
        }
        .alert("Delete Run?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                workoutToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let workout = workoutToDelete {
                    modelContext.delete(workout)
                    try? modelContext.save()
                    workoutToDelete = nil
                }
            }
        } message: {
            if let workout = workoutToDelete {
                Text("Are you sure you want to permanently delete \"\(workout.title)\" from \(workout.formattedDate)? This cannot be undone.")
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Editor Sheet

private struct TempWorkoutEditorSheet: View {
    @Bindable var workout: Workout
    let onSave: () -> Void

    // Editable fields
    @State private var durationText: String = ""
    @State private var distanceText: String = ""
    @State private var avgPaceText: String = ""
    @State private var splits: [EditableSplit] = []
    @State private var showSaved = false

    struct EditableSplit: Identifiable {
        let id: Int  // kilometer number
        var pace: String
        var time: String
    }

    var body: some View {
        NavigationStack {
            Form {
                // Top-level stats
                Section("Run Totals") {
                    LabeledField("Total Duration (H:MM:SS)", text: $durationText, placeholder: "1:45:00")
                    LabeledField("Distance (km)", text: $distanceText, placeholder: "21.00")
                    LabeledField("Avg Pace (M:SS)", text: $avgPaceText, placeholder: "5:30")
                }

                // Km splits
                Section("Kilometer Splits") {
                    ForEach($splits) { $split in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("KM \(split.id)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                VStack(alignment: .leading) {
                                    Text("Pace").font(.caption2).foregroundStyle(.tertiary)
                                    TextField("5:30", text: $split.pace)
                                        .font(.body.monospacedDigit())
                                        .textFieldStyle(.roundedBorder)
                                }
                                VStack(alignment: .leading) {
                                    Text("Cumulative").font(.caption2).foregroundStyle(.tertiary)
                                    TextField("00:05:30", text: $split.time)
                                        .font(.body.monospacedDigit())
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Edit: \(workout.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onSave() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { applyChanges() }
                        .fontWeight(.semibold)
                }
            }
            .overlay {
                if showSaved {
                    VStack {
                        Spacer()
                        Text("Saved")
                            .font(.headline)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 40)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onAppear { loadWorkoutData() }
        }
    }

    // MARK: - Load existing data into editable fields

    private func loadWorkoutData() {
        // Duration
        if let dur = workout.actualDurationSeconds {
            let total = Int(dur)
            let h = total / 3600
            let m = (total % 3600) / 60
            let s = total % 60
            durationText = String(format: "%d:%02d:%02d", h, m, s)
        }

        // Distance
        if let dist = workout.actualDistanceKm {
            distanceText = String(format: "%.2f", dist)
        }

        // Average pace
        if let pace = workout.actualAvgPaceSecPerKm, pace > 0, pace < 3600 {
            let m = Int(pace) / 60
            let s = Int(pace) % 60
            avgPaceText = "\(m):\(String(format: "%02d", s))"
        }

        // Splits
        let decoded = workout.decodedKmSplits
        splits = decoded.map { split in
            EditableSplit(id: split.kilometer, pace: split.pace, time: split.time)
        }
    }

    // MARK: - Write changes back to SwiftData

    private func applyChanges() {
        // Parse distance
        if let dist = Double(distanceText) {
            workout.actualDistanceKm = dist
            if workout.title == "Free Run" {
                workout.distanceKm = dist
            }
        }

        // Re-encode splits first (we may derive duration from them)
        let codableSplits = splits.map { split in
            CodableKilometerSplit(
                kilometer: split.id,
                pace: split.pace,
                time: split.time,
                isFastest: false
            )
        }
        let withFastest = markFastest(codableSplits)
        if let data = try? JSONEncoder().encode(withFastest),
           let json = String(data: data, encoding: .utf8) {
            workout.kmSplitsJSON = json
        }

        // Determine total duration:
        // 1. Use the last split's cumulative time if splits exist (most reliable)
        // 2. Fall back to the manually entered duration field
        var resolvedDuration: Double?

        if let lastSplit = splits.last,
           let lastSplitSeconds = parseDuration(lastSplit.time) {
            resolvedDuration = lastSplitSeconds
        }

        // If user also manually edited the duration field and it's larger
        // (e.g., they ran past the last full km), prefer the manual value
        if let manualDuration = parseDuration(durationText),
           manualDuration > (resolvedDuration ?? 0) {
            resolvedDuration = manualDuration
        }

        if let duration = resolvedDuration {
            workout.actualDurationSeconds = duration
            workout.durationMinutes = Int(duration / 60.0)
        }

        // Auto-recalculate avg pace from duration and distance
        if let duration = workout.actualDurationSeconds,
           let distance = workout.actualDistanceKm,
           distance > 0 {
            workout.actualAvgPaceSecPerKm = duration / distance
        }

        withAnimation { showSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            showSaved = false
            onSave()
        }
    }

    // MARK: - Helpers

    private func parseDuration(_ text: String) -> Double? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 3: return Double(parts[0] * 3600 + parts[1] * 60 + parts[2])
        case 2: return Double(parts[0] * 60 + parts[1])
        default: return nil
        }
    }

    private func parsePace(_ text: String) -> Double? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return Double(parts[0] * 60 + parts[1])
    }

    private func markFastest(_ splits: [CodableKilometerSplit]) -> [CodableKilometerSplit] {
        guard !splits.isEmpty else { return splits }
        var fastestIdx = 0
        var fastestSec = Int.max
        for (i, s) in splits.enumerated() {
            if let sec = s.pace.toSeconds, sec < fastestSec {
                fastestSec = sec
                fastestIdx = i
            }
        }
        return splits.enumerated().map { (i, s) in
            CodableKilometerSplit(kilometer: s.kilometer, pace: s.pace, time: s.time, isFastest: i == fastestIdx)
        }
    }
}

// MARK: - Labeled Field Helper

private struct LabeledField: View {
    let label: String
    @Binding var text: String
    let placeholder: String

    init(_ label: String, text: Binding<String>, placeholder: String) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            TextField(placeholder, text: $text)
                .font(.body.monospacedDigit())
                .multilineTextAlignment(.trailing)
                .frame(width: 120)
        }
    }
}
