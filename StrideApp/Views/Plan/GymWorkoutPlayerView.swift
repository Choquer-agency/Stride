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

    /// Timed stages run full brand-red with white text.
    private var isRedMode: Bool {
        guard stageIndex < stages.count else { return false }
        if case .timed = stages[stageIndex].kind { return true }
        return false
    }

    private var fgPrimary: Color { isRedMode ? .white : .primary }
    private var fgSecondary: Color { isRedMode ? .white.opacity(0.8) : .secondary }

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
        .background((isRedMode ? Color.stridePrimary : Color(.systemBackground)).ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: isRedMode)
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
        HStack(spacing: 12) {
            Button {
                stageIndex >= stages.count ? dismiss() : (showAbandonConfirm = true)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(fgSecondary)
                    .padding(10)
            }

            ProgressView(value: Double(min(stageIndex, stages.count)), total: Double(max(stages.count, 1)))
                .tint(isRedMode ? .white : .stridePrimary)
                .frame(maxWidth: .infinity)

            Text(stageIndex < stages.count ? "\(stageIndex + 1)/\(stages.count)" : "Done")
                .font(.barlowCondensed(size: 18, weight: .medium))
                .foregroundStyle(fgSecondary)
                .padding(10)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var footer: some View {
        if stageIndex < stages.count {
            let stage = stages[stageIndex]
            HStack(spacing: 12) {
                // Back only when the PREVIOUS stage is rep/manual work (an
                // accidental Done is recoverable; a finished timer is not).
                if canGoBack {
                    Button {
                        timer?.invalidate(); timerRunning = false
                        stageIndex -= 1
                        prepareStage()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(fgPrimary)
                            .frame(width: 56, height: 56)
                            .background(isRedMode ? Color.white.opacity(0.2) : Color(.systemGray6))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                if case .timed = stage.kind {
                    Button {
                        timerRunning ? pauseTimer() : startTimer()
                    } label: {
                        Text(timerRunning ? "Pause" : (remainingSeconds == stageSeconds(stage) ? "Start Timer" : "Resume"))
                            .font(.interSemibold(19))
                            .foregroundColor(.stridePrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        advance()
                    } label: {
                        Text("Done")
                            .font(.interSemibold(19))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.stridePrimary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
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
        VStack(spacing: 16) {
            Text(stage.sectionLabel)
                .font(.inter(size: 14, weight: .semibold))
                .foregroundColor(.stridePrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(isRedMode ? Color.white : Color.stridePrimary.opacity(0.1)))

            if let setLabel = stage.setLabel {
                Text(setLabel)
                    .font(.inter(size: 16, weight: .semibold))
                    .foregroundStyle(fgSecondary)
                    .kerning(1.4)
            }

            Text(stage.exerciseName)
                .font(.inter(size: 34, weight: .semibold))
                .foregroundStyle(fgPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if let side = stage.sideLabel {
                Text(side)
                    .font(.inter(size: 15, weight: .bold))
                    .kerning(1.6)
                    .foregroundStyle(isRedMode ? Color.stridePrimary : .white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(isRedMode ? Color.white : Color.stridePrimary))
            }

            switch stage.kind {
            case .timed:
                Text(formatCountdown(remainingSeconds))
                    .font(.barlowCondensed(size: 132, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(fgPrimary)
                    .scaleEffect(remainingSeconds <= 5 && timerRunning ? 1.06 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: remainingSeconds <= 5 && timerRunning)

            case .manual(let detail):
                Text(detail)
                    .font(.inter(size: 24, weight: .medium))
                    .foregroundStyle(fgSecondary)
                Text("Tap Done when finished")
                    .font(.inter(size: 15))
                    .foregroundStyle(fgSecondary.opacity(0.7))

            case .reps(let repsText, let weightKg, let suffix):
                if !repsText.isEmpty {
                    Text(repsDisplay(repsText))
                        .font(.inter(size: 22, weight: .medium))
                        .foregroundStyle(fgSecondary)
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

            guideStrip(for: stage.exerciseName)
        }
    }

    /// How-to photo sequence for the current exercise, shown above the button.
    @ViewBuilder
    private func guideStrip(for exercise: String) -> some View {
        let guides = Self.guideImages(for: exercise)
        if !guides.isEmpty {
            HStack(spacing: 10) {
                ForEach(Array(guides.enumerated()), id: \.offset) { _, image in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: guides.count == 1 ? 190 : 135)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
        }
    }

    private static func guideImages(for exercise: String) -> [UIImage] {
        guard let slug = imageSlug(for: exercise) else { return [] }
        // Coach setting picks the catalog: male images are unprefixed,
        // female/robot are "female_<slug>_N" / "robot_<slug>_N".
        // Fall back to the male image when a catalog is incomplete.
        let style = UserDefaults.standard.string(forKey: "coach_style") ?? "male"
        let prefix = style == "male" ? "" : "\(style)_"
        var images: [UIImage] = []
        for step in 1...4 {
            guard let image = UIImage(named: "\(prefix)\(slug)_\(step)")
                ?? UIImage(named: "\(slug)_\(step)") else { break }
            images.append(image)
        }
        return images
    }

    /// Maps a parsed exercise name to its guide-image slug. Contains-based,
    /// checked in specificity order (e.g. "hip abduction" before "side plank").
    private static func imageSlug(for exercise: String) -> String? {
        let n = exercise.lowercased()
        let rules: [(String, String)] = [
            ("hip abduction", "side_plank_abduction"),
            ("copenhagen", "copenhagen_plank"),
            ("side plank", "side_plank"),
            ("plank", "plank"),
            ("bulgarian", "bulgarian_split_squat"),
            ("split squat", "db_split_squat"),
            ("goblet", "goblet_squat"),
            ("back squat", "back_squat"),
            ("rdl", "barbell_rdl"),
            ("step-up", "box_step_up"),
            ("step up", "box_step_up"),
            ("glute bridge", "single_leg_glute_bridge"),
            ("calf raise", "single_leg_calf_raise"),
            ("balance reach", "single_leg_balance_reach"),
            ("pull-up", "pull_ups"),
            ("pull up", "pull_ups"),
            ("landmine press", "landmine_press"),
            ("landmine rotation", "landmine_rotation"),
            ("russian twist", "med_ball_russian_twist"),
            ("med ball", "med_ball_russian_twist"),
            ("medicine ball", "med_ball_russian_twist"),
            ("suitcase", "suitcase_carry"),
            ("dead bug", "dead_bug"),
            ("bird dog", "bird_dog"),
            ("clamshell", "clamshells"),
            ("hip flexor", "hip_flexor_stretch"),
        ]
        return rules.first { n.contains($0.0) }?.1
    }

    private func weightControl(for stage: GymSessionModel.Stage, suffix: String) -> some View {
        let current = currentWeight(for: stage.exerciseName)
        return VStack(spacing: 8) {
            Text("\(current == floor(current) ? String(Int(current)) : String(format: "%.1f", current)) \(suffix)")
                .font(.barlowCondensed(size: 92, weight: .medium))
                .monospacedDigit()
                .contentTransition(.numericText())

            Text("slide up or down · 5 kg steps")
                .font(.inter(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 16)
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

    /// Back is offered only when the previous stage was rep/manual work.
    private var canGoBack: Bool {
        guard stageIndex > 0, stageIndex <= stages.count - 1 else { return false }
        if case .timed = stages[stageIndex - 1].kind { return false }
        return true
    }

    /// "6" → "6 reps", "8/leg" → "8 per leg", "15/side" → "15 per side"
    private func repsDisplay(_ text: String) -> String {
        var s = text
            .replacingOccurrences(of: "/side", with: " per side")
            .replacingOccurrences(of: "/leg", with: " per leg")
        if s.allSatisfy(\.isNumber), !s.isEmpty { s += " reps" }
        return s
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
        // Persist immediately: whatever number is on screen when the athlete
        // moves on is the weight they lifted, even if the session is abandoned.
        var overrides = (UserDefaults.standard.dictionary(forKey: overridesKey) as? [String: Double]) ?? [:]
        overrides[exercise] = newValue
        UserDefaults.standard.set(overrides, forKey: overridesKey)
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
