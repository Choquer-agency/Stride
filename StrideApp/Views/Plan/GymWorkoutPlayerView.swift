import SwiftUI
import UIKit

/// Guided gym session player: one stage per screen, circuit-ordered.
/// Timed stages show a giant countdown; rep stages show an adjustable weight
/// (thumb-drag or chevrons, 5 kg steps) that's remembered and logged.
struct GymWorkoutPlayerView: View {
    let workout: Workout
    /// Called once when the athlete finishes the whole session.
    let onFinished: (_ summary: String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var stages: [GymSessionModel.Stage] = []
    @State private var stageIndex = 0
    @State private var showAbandonConfirm = false
    @State private var sessionStart = Date()

    // Weight adjustments this session: exercise name → chosen kg
    @State private var weights: [String: Double] = [:]
    @State private var dragAccumulator: CGFloat = 0

    // Timer state for the current timed stage
    @State private var remainingSeconds = 0
    @State private var timerRunning = false
    @State private var timer: Timer?

    private let overridesKey = "gym_weight_overrides_v1"

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer()
            if stageIndex >= stages.count {
                completeContent
            } else {
                stageContent(stages[stageIndex])
            }
            Spacer()
            footer
        }
        .background(Color(.systemBackground))
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            stages = GymSessionModel.stages(fromPrescription: workout.details ?? workout.title)
            prefillWeights()
            prepareStage()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            timer?.invalidate()
        }
        .confirmationDialog("Leave this session?", isPresented: $showAbandonConfirm) {
            Button("Leave without finishing", role: .destructive) { dismiss() }
            Button("Keep going", role: .cancel) {}
        }
    }

    // MARK: - Header / Footer

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    stageIndex >= stages.count ? dismiss() : (showAbandonConfirm = true)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(10)
                }
                Spacer()
                if stageIndex < stages.count {
                    Text(stages[stageIndex].sectionLabel)
                        .font(.inter(size: 12, weight: .semibold))
                        .foregroundStyle(Color.stridePrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.stridePrimary.opacity(0.1)))
                }
                Spacer()
                Text(stageIndex < stages.count ? "\(stageIndex + 1)/\(stages.count)" : "Done")
                    .font(.barlowCondensed(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(10)
            }
            .padding(.horizontal, 8)

            ProgressView(value: Double(min(stageIndex, stages.count)), total: Double(max(stages.count, 1)))
                .tint(.stridePrimary)
                .padding(.horizontal, 20)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var footer: some View {
        if stageIndex < stages.count {
            let stage = stages[stageIndex]
            HStack(spacing: 12) {
                if stageIndex > 0 {
                    Button {
                        timer?.invalidate(); timerRunning = false
                        stageIndex -= 1
                        prepareStage()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 54, height: 54)
                            .background(Color(.systemGray6))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                if case .timed = stage.kind {
                    Button {
                        timerRunning ? pauseTimer() : startTimer()
                    } label: {
                        Text(timerRunning ? "Pause" : (remainingSeconds == stageSeconds(stage) ? "Start Timer" : "Resume"))
                            .font(.interSemibold(17))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.stridePrimary)
                } else {
                    Button {
                        advance()
                    } label: {
                        Text("Done")
                            .font(.interSemibold(17))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.stridePrimary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        } else {
            Button {
                finishSession()
            } label: {
                Text("Finish Session")
                    .font(.interSemibold(17))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(.stridePrimary)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Stage content

    @ViewBuilder
    private func stageContent(_ stage: GymSessionModel.Stage) -> some View {
        VStack(spacing: 14) {
            if let setLabel = stage.setLabel {
                Text(setLabel)
                    .font(.inter(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .kerning(1.2)
            }

            Text(stage.exerciseName)
                .font(.inter(size: 28, weight: .semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if let side = stage.sideLabel {
                Text(side)
                    .font(.inter(size: 13, weight: .bold))
                    .kerning(1.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.stridePrimary))
            }

            switch stage.kind {
            case .timed:
                Text(formatCountdown(remainingSeconds))
                    .font(.barlowCondensed(size: 110, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(remainingSeconds <= 5 && timerRunning ? Color.stridePrimary : .primary)

            case .manual(let detail):
                Text(detail)
                    .font(.inter(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Tap Done when finished")
                    .font(.inter(size: 13))
                    .foregroundStyle(.tertiary)

            case .reps(let repsText, let weightKg, let suffix):
                if !repsText.isEmpty {
                    Text(repsText)
                        .font(.inter(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                if weightKg != nil {
                    weightControl(for: stage, suffix: suffix)
                } else if suffix == "BW" {
                    Text("Bodyweight")
                        .font(.inter(size: 15, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                }
            }
        }
    }

    private func weightControl(for stage: GymSessionModel.Stage, suffix: String) -> some View {
        let current = currentWeight(for: stage.exerciseName)
        return VStack(spacing: 6) {
            Button { adjustWeight(stage.exerciseName, by: 5) } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            .buttonStyle(.plain)

            Text("\(current == floor(current) ? String(Int(current)) : String(format: "%.1f", current)) \(suffix)")
                .font(.barlowCondensed(size: 76, weight: .medium))
                .monospacedDigit()
                .contentTransition(.numericText())

            Button { adjustWeight(stage.exerciseName, by: -5) } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            .buttonStyle(.plain)

            Text("slide or tap to adjust · 5 kg steps")
                .font(.inter(size: 11))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    let step: CGFloat = 28   // points of drag per 5 kg
                    let delta = value.translation.height - dragAccumulator
                    if abs(delta) >= step {
                        let increments = Int(-delta / step)
                        if increments != 0 {
                            adjustWeight(stage.exerciseName, by: Double(increments) * 5)
                            dragAccumulator += CGFloat(-increments) * step
                        }
                    }
                }
                .onEnded { _ in dragAccumulator = 0 }
        )
    }

    // MARK: - Completion

    private var completeContent: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.green.opacity(0.15)).frame(width: 76, height: 76)
                Image(systemName: "checkmark")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.green)
            }
            Text("Session complete")
                .font(.inter(size: 24, weight: .semibold))
            Text(durationSummary)
                .font(.inter(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            if !adjustmentSummaryLines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(adjustmentSummaryLines, id: \.self) { line in
                        Text(line)
                            .font(.inter(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Logic

    private func prepareStage() {
        timer?.invalidate()
        timerRunning = false
        dragAccumulator = 0
        guard stageIndex < stages.count else { return }
        remainingSeconds = stageSeconds(stages[stageIndex])
    }

    private func stageSeconds(_ stage: GymSessionModel.Stage) -> Int {
        if case .timed(let seconds) = stage.kind { return seconds }
        return 0
    }

    private func formatCountdown(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func startTimer() {
        timerRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                guard timerRunning else { return }
                if remainingSeconds > 1 {
                    remainingSeconds -= 1
                    if remainingSeconds <= 3 {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    advance()
                }
            }
        }
    }

    private func pauseTimer() {
        timerRunning = false
        timer?.invalidate()
    }

    private func advance() {
        timer?.invalidate()
        timerRunning = false
        stageIndex += 1
        prepareStage()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func currentWeight(for exercise: String) -> Double {
        if let w = weights[exercise] { return w }
        // Fall back to the prescription value from the stage list
        for stage in stages {
            if stage.exerciseName == exercise, case .reps(_, let kg?, _) = stage.kind {
                return kg
            }
        }
        return 0
    }

    private func adjustWeight(_ exercise: String, by delta: Double) {
        let newValue = max(0, currentWeight(for: exercise) + delta)
        withAnimation(.snappy) { weights[exercise] = newValue }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func prefillWeights() {
        let overrides = (UserDefaults.standard.dictionary(forKey: overridesKey) as? [String: Double]) ?? [:]
        for stage in stages {
            if case .reps(_, let kg?, _) = stage.kind, weights[stage.exerciseName] == nil {
                weights[stage.exerciseName] = overrides[stage.exerciseName] ?? kg
            }
        }
    }

    private var adjustmentSummaryLines: [String] {
        var lines: [String] = []
        var seen = Set<String>()
        for stage in stages {
            guard case .reps(_, let prescribed?, let suffix) = stage.kind,
                  !seen.contains(stage.exerciseName),
                  let chosen = weights[stage.exerciseName],
                  chosen != prescribed else { continue }
            seen.insert(stage.exerciseName)
            lines.append("\(stage.exerciseName): \(Int(prescribed)) → \(Int(chosen)) \(suffix)")
        }
        return lines
    }

    private var durationSummary: String {
        let minutes = max(1, Int(Date().timeIntervalSince(sessionStart) / 60))
        return "\(stages.count) stages · \(minutes) min"
    }

    private func finishSession() {
        // Persist chosen weights for next session's prefill
        var overrides = (UserDefaults.standard.dictionary(forKey: overridesKey) as? [String: Double]) ?? [:]
        for (exercise, kg) in weights { overrides[exercise] = kg }
        UserDefaults.standard.set(overrides, forKey: overridesKey)

        var summary = "Completed guided session (\(durationSummary))"
        if !adjustmentSummaryLines.isEmpty {
            summary += ". Weight adjustments: " + adjustmentSummaryLines.joined(separator: "; ")
        }
        onFinished(summary)
        dismiss()
    }
}
