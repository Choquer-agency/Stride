import SwiftUI

/// Sheet shown after finishing a workout to capture effort and notes before saving
struct WorkoutCompletionSheet: View {
    @ObservedObject var workoutManager: WorkoutManager
    let storageManager: StorageManager
    @Environment(\.dismiss) private var dismiss
    @Binding var showReviewScreen: Bool
    @Binding var reviewFeedback: WorkoutFeedback?
    
    @State private var effortRating: Int = 5
    @State private var fatigueLevel: Int = 3
    @State private var painLevel: Int = 0
    @State private var selectedPainAreas: Set<InjuryArea> = []
    @State private var notes: String = ""
    @FocusState private var isNotesFocused: Bool
    
    // Effort descriptions (updated to match spec)
    private func effortDescription(for rating: Int) -> String {
        switch rating {
        case 1...3: return "Very easy"
        case 4...5: return "Comfortable"
        case 6...7: return "Challenging"
        case 8...9: return "Very hard"
        case 10: return "Max effort"
        default: return ""
        }
    }
    
    // Fatigue descriptions
    private let fatigueDescriptions: [Int: String] = [
        1: "Fresh & energized",
        2: "Slightly tired",
        3: "Moderate fatigue",
        4: "Very tired",
        5: "Exhausted"
    ]
    
    // Pain descriptions
    private func painDescription(for level: Int) -> String {
        if level == 0 { return "No pain" }
        if level <= 3 { return "Mild discomfort" }
        if level <= 6 { return "Manageable pain" }
        return "Concerning pain"
    }
    
    private func painColor(for level: Int) -> Color {
        if level == 0 { return .gray }
        if level <= 3 { return .yellow }
        if level <= 6 { return .orange }
        return .red
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Effort Rating Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("How did it feel?")
                            .font(.system(size: 20, weight: .semibold))
                        
                        // Selected rating display
                        HStack(spacing: 12) {
                            Text("\(effortRating)")
                                .font(.system(size: 48, weight: .medium))
                                .foregroundColor(.stridePrimary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(effortDescription(for: effortRating))
                                    .font(.system(size: 16, weight: .medium))
                                Text("Effort level")
                                    .font(.system(size: 14, weight: .light))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.bottom, 8)
                        
                        // Slider
                        VStack(spacing: 12) {
                            Slider(value: Binding(
                                get: { Double(effortRating) },
                                set: { effortRating = Int($0.rounded()) }
                            ), in: 1...10, step: 1)
                            .tint(.stridePrimary)
                            
                            HStack {
                                Text("1")
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("10")
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    
                    // Interval Comparison (if guided workout)
                    if let workout = workoutManager.plannedWorkout,
                       let intervals = workout.intervals,
                       let completions = workoutManager.currentSession?.intervalCompletions,
                       !completions.isEmpty {
                        intervalComparisonSection(intervals: intervals, completions: completions)
                    }
                    
                    // Fatigue Level Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("How fatigued are you?")
                            .font(.system(size: 20, weight: .semibold))
                        
                        // Selected fatigue display
                        HStack(spacing: 12) {
                            Text("\(fatigueLevel)")
                                .font(.system(size: 48, weight: .medium))
                                .foregroundColor(.stridePrimary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(fatigueDescriptions[fatigueLevel] ?? "")
                                    .font(.system(size: 16, weight: .medium))
                                Text("Fatigue level")
                                    .font(.system(size: 14, weight: .light))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.bottom, 8)
                        
                        // Slider
                        VStack(spacing: 12) {
                            Slider(value: Binding(
                                get: { Double(fatigueLevel) },
                                set: { fatigueLevel = Int($0.rounded()) }
                            ), in: 1...5, step: 1)
                            .tint(.stridePrimary)
                            
                            HStack {
                                Text("1")
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("5")
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    // Pain Level Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Any pain or discomfort?")
                            .font(.system(size: 20, weight: .semibold))
                        
                        // Selected pain display
                        HStack(spacing: 12) {
                            Text("\(painLevel)")
                                .font(.system(size: 48, weight: .medium))
                                .foregroundColor(painColor(for: painLevel))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(painDescription(for: painLevel))
                                    .font(.system(size: 16, weight: .medium))
                                Text("Pain level")
                                    .font(.system(size: 14, weight: .light))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.bottom, 8)
                        
                        // Slider
                        VStack(spacing: 12) {
                            Slider(value: Binding(
                                get: { Double(painLevel) },
                                set: { painLevel = Int($0.rounded()) }
                            ), in: 0...10, step: 1)
                            .tint(painColor(for: painLevel))
                            
                            HStack {
                                Text("0")
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("10")
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Pain area selection (show if pain >= 4)
                        if painLevel >= 4 {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Where does it hurt?")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .padding(.top, 8)
                                
                                FlowLayout(spacing: 8) {
                                    ForEach(InjuryArea.allCases, id: \.self) { area in
                                        Button(action: {
                                            if selectedPainAreas.contains(area) {
                                                selectedPainAreas.remove(area)
                                            } else {
                                                selectedPainAreas.insert(area)
                                            }
                                        }) {
                                            Text(area.displayName)
                                                .font(.system(size: 14, weight: .medium))
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(selectedPainAreas.contains(area) ? Color.orange : Color(.systemGray5))
                                                .foregroundColor(selectedPainAreas.contains(area) ? .white : .primary)
                                                .cornerRadius(8)
                                        }
                                    }
                                }
                                
                                if painLevel >= 7 {
                                    HStack(spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.red)
                                        Text("Consider resting or consulting a healthcare provider")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.top, 8)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    // Coach Notes Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Anything you want your coach to know?")
                            .font(.system(size: 20, weight: .semibold))
                        
                        Text("Optional")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        
                        TextEditor(text: $notes)
                            .focused($isNotesFocused)
                            .font(.system(size: 16, weight: .regular))
                            .frame(minHeight: 120)
                            .padding(12)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, 24)
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        // Save Button
                        Button(action: {
                            saveWorkout()
                        }) {
                            Text("Save Workout")
                                .font(.system(size: 18, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .background(Color.stridePrimary)
                                .foregroundColor(.strideBlack)
                                .cornerRadius(100)
                        }
                        
                        // Skip Feedback Button
                        Button(action: {
                            skipFeedback()
                        }) {
                            Text("Skip feedback")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Complete Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func saveWorkout() {
        guard let session = workoutManager.currentSession else { return }
        
        // Calculate pace adherence for runs
        let paceAdherence = calculatePaceAdherence()
        
        // Create WorkoutFeedback
        let feedback = WorkoutFeedback(
            workoutSessionId: session.id,
            plannedWorkoutId: session.plannedWorkoutId,
            date: Date(),
            completionStatus: .completedAsPlanned,
            paceAdherence: paceAdherence,
            perceivedEffort: effortRating,
            fatigueLevel: fatigueLevel,
            painLevel: painLevel,
            painAreas: painLevel >= 4 && !selectedPainAreas.isEmpty ? Array(selectedPainAreas) : nil,
            weightFeel: nil,
            formBreakdown: nil,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        
        // Save feedback
        do {
            try storageManager.saveWorkoutFeedback(feedback)
        } catch {
            print("❌ Error saving workout feedback: \(error)")
        }
        
        // Save workout session (keep old fields for backwards compatibility)
        if var session = workoutManager.currentSession {
            session.effortRating = effortRating
            session.fatigueLevel = fatigueLevel
            session.injuryFlag = painLevel >= 4
            session.injuryNotes = painLevel >= 4 && !selectedPainAreas.isEmpty ? selectedPainAreas.map { $0.displayName }.joined(separator: ", ") : nil
            session.notes = feedback.notes
            workoutManager.currentSession = session
        }
        
        workoutManager.finalizeWorkout()
        
        // Dismiss and show review screen
        reviewFeedback = feedback
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showReviewScreen = true
        }
    }
    
    private func skipFeedback() {
        // Save workout without feedback
        workoutManager.finalizeWorkout()
        dismiss()
    }
    
    // MARK: - Pace Adherence Calculation
    
    private func calculatePaceAdherence() -> PaceAdherence? {
        guard let session = workoutManager.currentSession,
              let workout = workoutManager.plannedWorkout,
              let completions = session.intervalCompletions else {
            return nil
        }
        
        // For interval workouts: compare work intervals
        let workIntervals = completions.filter { completion in
            if let interval = workout.intervals?.first(where: { $0.id == completion.intervalId }) {
                return interval.type == .work
            }
            return false
        }
        
        if !workIntervals.isEmpty {
            // Calculate average pace difference for work intervals
            var totalDiff: Double = 0
            var count = 0
            
            for completion in workIntervals {
                guard let targetPace = completion.targetPaceSecondsPerKm,
                      let actualPace = completion.actualAvgPaceSecondsPerKm else {
                    continue
                }
                
                totalDiff += abs(actualPace - targetPace)
                count += 1
            }
            
            if count > 0 {
                let avgDiff = totalDiff / Double(count)
                if avgDiff <= 5 { return .onTarget }
                if avgDiff <= 15 { return .slightlyOff }
                return .offTarget
            }
        }
        
        // For easy/long runs: compare overall pace to target
        if let targetPace = workout.targetPaceSecondsPerKm {
            let actualPace = session.avgPaceSecondsPerKm
            let diff = abs(actualPace - targetPace)
            
            if diff <= 5 { return .onTarget }
            if diff <= 15 { return .slightlyOff }
            return .offTarget
        }
        
        return nil
    }
    
    // MARK: - Interval Comparison Section
    
    private func intervalComparisonSection(intervals: [PlannedWorkout.Interval], completions: [IntervalCompletion]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Interval Performance")
                .font(.system(size: 20, weight: .semibold))
            
            VStack(spacing: 8) {
                ForEach(intervals.sorted(by: { $0.order < $1.order })) { interval in
                    if let completion = completions.first(where: { $0.intervalId == interval.id }) {
                        intervalComparisonRow(interval: interval, completion: completion)
                    }
                }
            }
            
            // Overall adherence score
            let adherenceScore = calculateAdherenceScore(intervals: intervals, completions: completions)
            HStack {
                Image(systemName: adherenceScore >= 80 ? "star.fill" : "star")
                    .foregroundColor(.stridePrimary)
                Text("Overall adherence: \(Int(adherenceScore))%")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal, 24)
    }
    
    private func intervalComparisonRow(interval: PlannedWorkout.Interval, completion: IntervalCompletion) -> some View {
        HStack(spacing: 12) {
            // Interval type badge
            Circle()
                .fill(colorForIntervalType(interval.type))
                .frame(width: 12, height: 12)
            
            // Interval name
            Text(interval.type.displayName)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            
            Spacer()
            
            // Status or comparison
            if completion.status == .skipped {
                Text("Skipped")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(4)
            } else if let targetPace = completion.targetPaceSecondsPerKm,
                      let actualPace = completion.actualAvgPaceSecondsPerKm {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(actualPace.toPaceString())
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(paceComparisonColor(target: targetPace, actual: actualPace, type: interval.type))
                    
                    Text("target: \(targetPace.toPaceString())")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("—")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
    
    private func calculateAdherenceScore(intervals: [PlannedWorkout.Interval], completions: [IntervalCompletion]) -> Double {
        let completedIntervals = completions.filter { $0.status == .completed }
        guard !completedIntervals.isEmpty else { return 0 }
        
        var totalScore: Double = 0
        var count: Double = 0
        
        for completion in completedIntervals {
            guard let targetPace = completion.targetPaceSecondsPerKm,
                  let actualPace = completion.actualAvgPaceSecondsPerKm,
                  let interval = intervals.first(where: { $0.id == completion.intervalId }) else {
                continue
            }
            
            let difference = abs(actualPace - targetPace)
            let tolerance = paceToleranceForInterval(interval).green
            
            // Score: 100% if within tolerance, scales down linearly beyond that
            let score = max(0, 100 - (difference / tolerance * 100))
            totalScore += score
            count += 1
        }
        
        return count > 0 ? totalScore / count : 0
    }
    
    private func paceComparisonColor(target: Double, actual: Double, type: PlannedWorkout.Interval.IntervalType) -> Color {
        let difference = abs(actual - target)
        let tolerance = paceToleranceForInterval(PlannedWorkout.Interval(order: 0, type: type, description: ""))
        
        if difference <= tolerance.green {
            return .green
        } else if difference <= tolerance.yellow {
            return .yellow
        } else {
            return .red
        }
    }
    
    private struct PaceTolerance {
        let green: Double
        let yellow: Double
    }
    
    private func paceToleranceForInterval(_ interval: PlannedWorkout.Interval) -> PaceTolerance {
        switch interval.type {
        case .warmup, .recovery, .cooldown:
            return PaceTolerance(green: 15, yellow: 25)
        case .work:
            return PaceTolerance(green: 5, yellow: 10)
        }
    }
    
    private func colorForIntervalType(_ type: PlannedWorkout.Interval.IntervalType) -> Color {
        switch type {
        case .warmup: return .blue
        case .work: return .red
        case .recovery: return .green
        case .cooldown: return .cyan
        }
    }
}
