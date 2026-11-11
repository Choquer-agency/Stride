import SwiftUI
import UIKit

/// Guided gym session player: one stage per screen, circuit-ordered.
/// Timed stages show a giant countdown; rep stages show an adjustable weight
/// (thumb-drag, with equipment-specific increments) that's remembered and logged.
struct GymWorkoutPlayerView: View {
    let workout: Workout
    /// Called once when the athlete finishes the whole session.
    let onFinished: (_ summary: String) -> Void

    @ObservedObject private var heartRate = HeartRateManager.shared

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var stages: [GymSessionModel.Stage] = []
    @State private var stageIndex = 0
    @State private var showAbandonConfirm = false
    @State private var sessionStart = Date()
    @State private var sessionID = UUID()
    @State private var recoveryOwnerID: String?
    @State private var didInitialize = false
    @State private var sessionEnded = false
    @State private var recoveryError: String?
    @State private var selectedGuide: GymGuideSelection?

    /// Timed stages run full brand-red with white text.
    private var isRedMode: Bool {
        guard stageIndex < stages.count else { return false }
        if case .timed = stages[stageIndex].kind { return true }
        return false
    }

    private var fgPrimary: Color { .white }
    private var fgSecondary: Color { .white.opacity(0.62) }

    // Weight adjustments this session: exercise name → chosen kg
    @State private var weights: [String: Double] = [:]
    @State private var dragAccumulator: CGFloat = 0

    // Timer state for the current timed stage
    @State private var remainingSeconds = 0
    @State private var timerRunning = false
    @State private var timer: Timer?
    @State private var showSkiPreview = false
    @State private var stageStartedAt: Date?
    @State private var stageSampleStartIndex = 0
    @State private var skiBlockSampleStartIndex = 0
    @State private var skiBlockDuration = 0

    // v1 mixed kg and relabelled pounds, so it cannot be safely reused.
    private let overridesKey = "gym_weight_overrides_canonical_kg_v2"
    @AppStorage("gym_bar_weight_kg") private var barWeightKg = 20.0

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer()
            if showSkiPreview {
                skiPreview
            } else if stageIndex >= stages.count {
                completeContent
            } else {
                ScrollView {
                    stageContent(stages[stageIndex])
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
            Spacer()
            footer
        }
        .background {
            Color(red: 0.055, green: 0.055, blue: 0.065).ignoresSafeArea()
                .overlay {
                    Canvas { context, size in
                        var dots = Path()
                        for x in stride(from: 0.0, to: size.width, by: 8) {
                            for y in stride(from: 0.0, to: size.height, by: 8) {
                                dots.addEllipse(in: CGRect(x: x, y: y, width: 1, height: 1))
                            }
                        }
                        context.fill(dots, with: .color(.white.opacity(0.055)))
                    }.ignoresSafeArea()
                }
        }
        .onAppear {
            heartRate.startScanning(owner: "gym")
            UIApplication.shared.isIdleTimerDisabled = true
            guard !didInitialize else { return }
            let prescription = workout.details ?? workout.title
            stages = GymSessionModel.stages(fromPrescription: prescription)
            prefillWeights()
            recoveryOwnerID = AuthService.shared.currentUserID
            if let owner = recoveryOwnerID,
               let saved = GymSessionRecoveryStore.load(ownerID: owner, workoutID: workout.id,
                   prescription: prescription, stageCount: stages.count) {
                sessionID = saved.sessionID
                sessionStart = saved.sessionStart
                stageIndex = saved.stageIndex
                weights = saved.weights
                prepareStage()
                remainingSeconds = min(saved.remainingSeconds, stageIndex < stages.count ? stageSeconds(stages[stageIndex]) : 0)
            } else {
                prepareStage()
            }
            didInitialize = true
            AuthService.shared.beginWorkoutProtection(sessionID)
            saveCheckpoint()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            pauseTimer()
            heartRate.stopAndDisconnect(owner: "gym")
        }
        .onChange(of: scenePhase) { _, phase in
            // Freeze the current hold when leaving. Returning never skips exercises.
            if phase != .active { pauseTimer() }
        }
        .interactiveDismissDisabled()
        .alert("Session recovery", isPresented: Binding(
            get: { recoveryError != nil }, set: { if !$0 { recoveryError = nil } }
        )) {
            Button("OK", role: .cancel) { recoveryError = nil }
        } message: {
            Text(recoveryError ?? "Could not save gym progress. Keep this session open and try again.")
        }
        .sheet(item: $selectedGuide) { selection in
            expandedGuide(selection)
        }
        .confirmationDialog("Leave this session?", isPresented: $showAbandonConfirm) {
            Button("Leave without finishing", role: .destructive) {
                endRecovery()
                dismiss()
            }
            Button("Keep going", role: .cancel) {}
        }
    }

    // MARK: - Header / Footer

    private var skiPreview: some View {
        let sequence = stages.dropFirst(stageIndex).prefix { $0.exerciseName.hasPrefix("SkiErg") }
        let total = sequence.reduce(0) { $0 + stageSeconds($1) }
        return VStack(alignment: .leading, spacing: 18) {
            Text("SESSION / SKIERG").font(.runEyebrow(11)).foregroundStyle(Color.stridePrimary)
            Text("READY TO WORK")
                .font(.barlowCondensed(size: 54)).foregroundStyle(.white)
            Text("\(formatCountdown(total)) TOTAL  ·  \(sequence.count) \(sequence.count == 1 ? "PHASE" : "PHASES")")
                .font(.runEyebrow(12)).foregroundStyle(fgSecondary)
            ForEach(Array(sequence.enumerated()), id: \.element.id) { _, stage in
                HStack {
                    Text(stage.exerciseName.replacingOccurrences(of: "SkiErg — ", with: "").uppercased())
                    Spacer()
                    Text(formatCountdown(stageSeconds(stage)))
                }
                .font(.barlowCondensed(size: 24)).foregroundStyle(.white)
                .padding(16)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
            }
            if sequence.count > 1 {
                Text("HARD AND EASY PHASES ADVANCE AUTOMATICALLY")
                    .font(.runEyebrow(10)).foregroundStyle(fgSecondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                showAbandonConfirm = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(fgSecondary)
                    .padding(10)
            }

            ProgressView(value: Double(min(stageIndex, stages.count)), total: Double(max(stages.count, 1)))
                .tint(.stridePrimary)
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
        if showSkiPreview {
            Button("Start SkiErg") {
                skiBlockSampleStartIndex = heartRate.samples.count
                skiBlockDuration = stages.dropFirst(stageIndex)
                    .prefix { $0.exerciseName.hasPrefix("SkiErg") }
                    .reduce(0) { $0 + stageSeconds($1) }
                showSkiPreview = false
                startTimer()
            }
            .font(.interSemibold(19))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Color.stridePrimary, in: Capsule())
            .padding(.horizontal, 24)
        } else if stageIndex < stages.count {
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
                        if remainingSeconds == 0 { advance() }
                        else { timerRunning ? pauseTimer() : startTimer() }
                    } label: {
                        Text(remainingSeconds == 0 ? "Next" : (timerRunning ? "Pause" : (remainingSeconds == stageSeconds(stage) ? "Start Timer" : "Resume")))
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
                .font(.runEyebrow(11))
                .foregroundColor(.stridePrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.stridePrimary.opacity(0.14)))

            if let setLabel = stage.setLabel {
                Text(setLabel)
                    .font(.runEyebrow(11))
                    .foregroundStyle(fgSecondary)
                    .kerning(1.4)
            }

            Text(stage.exerciseName)
                .font(.barlowCondensed(size: 48))
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

            LiveHeartRateLabel(bpm: heartRate.currentBPM, tint: .heartRatePink)

            switch stage.kind {
            case .timed:
                gymHeartRateGraph(duration: stage.exerciseName.hasPrefix("SkiErg") ? max(skiBlockDuration, stageSeconds(stage)) : stageSeconds(stage),
                                  sampleStartIndex: stage.exerciseName.hasPrefix("SkiErg") ? skiBlockSampleStartIndex : stageSampleStartIndex)
                Text(formatCountdown(remainingSeconds))
                    .font(.barlowCondensed(size: 132, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(fgPrimary)
                    .scaleEffect(remainingSeconds <= 5 && timerRunning ? 1.06 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: remainingSeconds <= 5 && timerRunning)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        pauseTimer()
                        remainingSeconds = 0
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                    .accessibilityHint("Double tap to skip the timer, then tap Next")
                    .accessibilityAction(named: "Skip timer") { pauseTimer(); remainingSeconds = 0 }

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

            if case .timed = stage.kind, stage.loadKg != nil {
                weightControl(for: stage, suffix: stage.loadSuffix)
            }
            guideStrip(for: stage.exerciseName)
        }
    }

    /// Fit the entire instructional photo: cropping can hide support points and joint position.
    @ViewBuilder
    private func guideStrip(for exercise: String) -> some View {
        let guides = Self.guideImages(for: exercise)
        let technique = GymTechniqueGuide.forExercise(exercise)
        if !guides.isEmpty {
            VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(guides.enumerated()), id: \.offset) { index, image in
                        Button {
                            // Reading technique should not consume a timed exercise.
                            if timerRunning { pauseTimer() }
                            selectedGuide = GymGuideSelection(exercise: exercise, firstStep: index)
                        } label: {
                            VStack(spacing: 5) {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: guides.count == 1 ? 190 : 135)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                if let technique, index < technique.labels.count {
                                    Text(technique.labels[index])
                                        .font(.inter(size: 12, weight: .semibold))
                                        .foregroundStyle(fgPrimary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open technique guide: \(exercise), image \(index + 1)")
                    }
                }
                if let cue = technique?.cues.first {
                    Text(cue)
                        .font(.inter(size: 13))
                        .foregroundStyle(fgSecondary)
                        .multilineTextAlignment(.center)
                }
                Text("Tap a photo for the full technique guide")
                    .font(.inter(size: 11))
                    .foregroundStyle(fgSecondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
        }
    }

    private func expandedGuide(_ selection: GymGuideSelection) -> some View {
        let guides = Self.guideImages(for: selection.exercise)
        let technique = GymTechniqueGuide.forExercise(selection.exercise)
        return NavigationStack {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(selection.exercise.components(separatedBy: " (").first ?? selection.exercise)
                            .font(.inter(size: 24, weight: .semibold))
                        if let technique {
                            ForEach(technique.cues, id: \.self) { cue in
                                Text("• " + cue).font(.inter(size: 16))
                            }
                        }
                        ForEach(Array(guides.enumerated()), id: \.offset) { index, image in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(technique.flatMap { index < $0.labels.count ? $0.labels[index] : nil }
                                     ?? "Position \(index + 1)")
                                    .font(.inter(size: 18, weight: .semibold))
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .accessibilityLabel("\(selection.exercise), position \(index + 1)")
                            }
                            .id(index)
                        }
                    }
                    .padding(20)
                }
                .onAppear {
                    if selection.firstStep > 0 { reader.scrollTo(selection.firstStep, anchor: .top) }
                }
            }
            .navigationTitle("Technique")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { selectedGuide = nil }
                }
            }
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
        if let guide = GymTechniqueGuide.forExercise(exercise) { return guide.slug }
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
        let pounds = suffix.hasPrefix("lb")
        let dumbbell = GymSessionModel.isDumbbell(stage.exerciseName)
        let barbellTotal = suffix.contains("total incl. bar")
        let perSide = GymSessionModel.barbellPlateKg(totalKg: current, barKg: barWeightKg)
        return VStack(spacing: 8) {
            Text(GymSessionModel.displayLoad(current, suffix: pounds ? "lb" : "kg"))
                .font(.barlowCondensed(size: 76, weight: .medium))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(dumbbell ? "per dumbbell" : String(suffix.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                .font(.inter(size: 15, weight: .semibold))
                .foregroundStyle(fgSecondary)

            if stage.isStartingLoad {
                Text("Starting load · adjust to keep four reps in reserve")
                    .font(.caption)
                    .foregroundStyle(fgSecondary)
                    .multilineTextAlignment(.center)
            }
            if barbellTotal {
                Text("\(GymSessionModel.number(perSide)) kg per side + \(GymSessionModel.number(barWeightKg)) kg bar")
                    .font(.inter(size: 15, weight: .semibold))
                    .multilineTextAlignment(.center)
                VStack(spacing: 4) {
                    HStack {
                        Text("BAR WEIGHT").font(.runEyebrow(10))
                        Spacer()
                        Text("\(GymSessionModel.number(barWeightKg)) KG").font(.runEyebrow(10))
                    }.foregroundStyle(fgSecondary)
                    Slider(value: $barWeightKg, in: 1...40, step: 0.5)
                        .tint(.stridePrimary)
                        .accessibilityLabel("Bar weight")
                }.padding(.horizontal, 28).padding(.top, 8)
                if current < barWeightKg {
                    Text("Below your bar's weight. Confirm your bar or use a lighter bar.")
                        .font(.caption)
                        .foregroundStyle(fgSecondary)
                }
            }
            Text("SWIPE LOAD UP OR DOWN  ·  5 \(pounds ? "LB" : "KG") STEPS")
                .font(.inter(size: 11))
                .foregroundStyle(fgSecondary)
            if overridesWereReset {
                Text("Loads reset to the prescription after the unit update. Confirm your working weight.")
                    .font(.caption)
                    .foregroundStyle(fgSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    let step: CGFloat = 28
                    let delta = value.translation.height - dragAccumulator
                    if abs(delta) >= step {
                        let increments = Int(-delta / step)
                        if increments != 0 {
                            let kgStep = pounds ? 5 * GymSessionModel.kilogramsPerPound : 5
                            adjustWeight(stage.exerciseName, by: Double(increments) * kgStep,
                                         minimum: dumbbell ? 5 * GymSessionModel.kilogramsPerPound : 0)
                            dragAccumulator += CGFloat(-increments) * step
                        }
                    }
                }
                .onEnded { _ in dragAccumulator = 0 }
        )
    }

    private var overridesWereReset: Bool {
        UserDefaults.standard.dictionary(forKey: "gym_weight_overrides_v1") != nil
            && UserDefaults.standard.dictionary(forKey: overridesKey) == nil
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
        stageStartedAt = nil
        stageSampleStartIndex = heartRate.samples.count
        guard stageIndex < stages.count else { remainingSeconds = 0; saveCheckpoint(); return }
        remainingSeconds = stageSeconds(stages[stageIndex])
        showSkiPreview = stages[stageIndex].exerciseName.hasPrefix("SkiErg")
            && (stageIndex == 0 || !stages[stageIndex - 1].exerciseName.hasPrefix("SkiErg"))
            && remainingSeconds > 0
        saveCheckpoint()
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

    private func gymHeartRateGraph(duration: Int, sampleStartIndex: Int) -> some View {
        let readings = Array(heartRate.samples.dropFirst(sampleStartIndex))
        let firstTime = readings.first?.t ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("HEART RATE / FULL PHASE")
                Spacer()
                Text("0:00 — \(formatCountdown(duration))")
            }.font(.runEyebrow(9)).foregroundStyle(fgSecondary)
            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color.white.opacity(0.055))
                    if readings.count > 1 {
                        Path { path in
                            for (index, reading) in readings.enumerated() {
                                let x = geometry.size.width * min(1, max(0, (reading.t - firstTime) / Double(max(duration, 1))))
                                let y = geometry.size.height * (1 - min(1, max(0, Double(reading.bpm - 80) / 120)))
                                if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                        }.stroke(Color.heartRatePink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    } else {
                        Text("HEART RATE APPEARS WHEN MONITOR CONNECTS")
                            .font(.runEyebrow(9)).foregroundStyle(fgSecondary)
                    }
                }
            }.frame(height: 145)
        }.padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
            .padding(.horizontal, 20)
    }

    private func startTimer() {
        if stageStartedAt == nil { stageStartedAt = Date(); stageSampleStartIndex = heartRate.samples.count }
        timerRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                guard timerRunning else { return }
                if remainingSeconds > 1 {
                    remainingSeconds -= 1
                    saveCheckpoint()
                    if remainingSeconds <= 3 {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        IntervalCuePlayer.shared.countdown(remainingSeconds)
                    }
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    IntervalCuePlayer.shared.completed()
                    advance()
                    if stageIndex < stages.count,
                       stages[stageIndex].exerciseName.hasPrefix("SkiErg"),
                       !showSkiPreview {
                        startTimer()
                    }
                }
            }
        }
    }

    private func pauseTimer() {
        timerRunning = false
        timer?.invalidate()
        saveCheckpoint()
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
            if stage.exerciseName == exercise, let kg = stage.loadKg {
                return kg
            }
        }
        return 0
    }

    private func adjustWeight(_ exercise: String, by delta: Double, minimum: Double) {
        let newValue = max(minimum, currentWeight(for: exercise) + delta)
        withAnimation(.snappy) { weights[exercise] = newValue }
        UISelectionFeedbackGenerator().selectionChanged()
        // Persist immediately: whatever number is on screen when the athlete
        // moves on is the weight they lifted, even if the session is abandoned.
        var overrides = (UserDefaults.standard.dictionary(forKey: overridesKey) as? [String: Double]) ?? [:]
        overrides[overrideStorageKey(for: exercise)] = newValue
        UserDefaults.standard.set(overrides, forKey: overridesKey)
        saveCheckpoint()
    }

    private func prefillWeights() {
        let overrides = (UserDefaults.standard.dictionary(forKey: overridesKey) as? [String: Double]) ?? [:]
        for stage in stages {
            if let kg = stage.loadKg, weights[stage.exerciseName] == nil {
                weights[stage.exerciseName] = overrides[overrideStorageKey(for: stage.exerciseName)] ?? kg
            }
        }
    }

    private func overrideStorageKey(for exercise: String) -> String {
        // A per-side plate load and a total barbell load are different quantities.
        let basis = stages.first(where: { $0.exerciseName == exercise })?.loadSuffix ?? "kg"
        return exercise + "|" + basis
    }

    private var adjustmentSummaryLines: [String] {
        var lines: [String] = []
        var seen = Set<String>()
        for stage in stages {
            guard let prescribed = stage.loadKg,
                  !seen.contains(stage.exerciseName),
                  let chosen = weights[stage.exerciseName],
                  chosen != prescribed else { continue }
            seen.insert(stage.exerciseName)
            lines.append("\(stage.exerciseName): \(GymSessionModel.displayLoad(prescribed, suffix: stage.loadSuffix)) → \(GymSessionModel.displayLoad(chosen, suffix: stage.loadSuffix))")
        }
        return lines
    }

    private var durationSummary: String {
        let minutes = max(1, Int(Date().timeIntervalSince(sessionStart) / 60))
        return "\(stages.count) stages · \(minutes) min"
    }

    private func saveCheckpoint() {
        guard didInitialize, !sessionEnded, let owner = recoveryOwnerID else { return }
        do {
            try GymSessionRecoveryStore.save(.init(ownerID: owner, workoutID: workout.id,
                prescription: workout.details ?? workout.title, sessionID: sessionID,
                sessionStart: sessionStart, stageIndex: stageIndex,
                remainingSeconds: remainingSeconds, weights: weights))
        } catch {
            recoveryError = "Could not save gym progress. Keep this session open and try again."
        }
    }

    private func endRecovery() {
        sessionEnded = true
        timerRunning = false
        timer?.invalidate()
        if let owner = recoveryOwnerID { GymSessionRecoveryStore.remove(ownerID: owner, workoutID: workout.id) }
        AuthService.shared.endWorkoutProtection(sessionID)
    }

    private func finishSession() {
        // Persist chosen weights for next session's prefill
        var overrides = (UserDefaults.standard.dictionary(forKey: overridesKey) as? [String: Double]) ?? [:]
        for (exercise, kg) in weights { overrides[overrideStorageKey(for: exercise)] = kg }
        UserDefaults.standard.set(overrides, forKey: overridesKey)

        var summary = "Completed guided session (\(durationSummary))"
        var loggedExercises = Set<String>()
        let loads = stages.compactMap { stage -> String? in
            guard let kg = weights[stage.exerciseName], loggedExercises.insert(stage.exerciseName).inserted else { return nil }
            return "\(stage.exerciseName): \(GymSessionModel.displayLoad(kg, suffix: stage.loadSuffix))"
        }
        if !loads.isEmpty { summary += ". Loads used: " + loads.joined(separator: "; ") }
        if !adjustmentSummaryLines.isEmpty {
            summary += ". Weight adjustments: " + adjustmentSummaryLines.joined(separator: "; ")
        }
        onFinished(summary)
        endRecovery()
        dismiss()
    }
}


private struct GymGuideSelection: Identifiable {
    let id = UUID()
    let exercise: String
    let firstStep: Int
}

/// Technique labels and cues for the new karting exercises. Neck holds are static,
/// so each direction gets its own hand-placement photo rather than a stretch sequence.
private struct GymTechniqueGuide {
    let slug: String
    let labels: [String]
    let cues: [String]

    static func forExercise(_ exercise: String) -> GymTechniqueGuide? {
        let name = exercise.lowercased()
        if name.contains("bench-supported") && name.contains("row") {
            return GymTechniqueGuide(slug: "bench_supported_db_row", labels: ["1 · Set up", "2 · Row, then lower"], cues: [
                "Support one hand and the same-side knee on the bench; keep the other foot planted.",
                "Keep your back and neck neutral, hips and shoulders square. Let the dumbbell hang below your shoulder.",
                "Pull your working elbow toward your hip, then lower slowly. Keep your shoulder away from your ear; do not twist.",
                "Photos show the right arm working. Reverse the setup for the left arm. Start with 5 lb; adjust in 5 lb steps while keeping four repetitions left in reserve."
            ])
        }
        if name.contains("farmer") && name.contains("hold") {
            return GymTechniqueGuide(slug: "farmer_hold", labels: ["Stand still and hold"], cues: [
                "Stand tall with one light dumbbell in each hand, arms hanging beside your thighs.",
                "Keep wrists straight, shoulders relaxed and ribs stacked over hips. Breathe normally; do not shrug, lean or walk.",
                "Set the weights down before your grip fails. Skip this if your arms are still sore."
            ])
        }
        if name.contains("plate steering") {
            return GymTechniqueGuide(slug: "seated_plate_steering", labels: ["1 · Center", "2 · Turn gently"], cues: [
                "Sit upright with both feet flat. Hold a light plate at lower-chest height, hands on opposite sides.",
                "Keep elbows bent and below your shoulders, with the plate close to you.",
                "Slowly turn the plate a small amount left and right. Keep your torso still, shoulders relaxed and neck neutral."
            ])
        }
        if name.contains("wrist extension") {
            return GymTechniqueGuide(slug: "supported_wrist_extension", labels: ["1 · Lower gently", "2 · Lift the wrist"], cues: [
                "Rest your forearm on your thigh with your palm facing down and your hand just beyond your knee.",
                "Hold a very light dumbbell. Lift the back of your hand through a small comfortable range, then lower slowly.",
                "Keep your forearm and elbow supported. Move at the wrist; do not lift the whole arm. Repeat with the other wrist."
            ])
        }
        if name.contains("neck isometric") {
            let directions = [("front", "forehead"), ("back", "back of your skull"),
                              ("left", "left temple, just above your ear"), ("right", "right temple, just above your ear")]
            guard let direction = directions.first(where: { name.contains("neck isometric " + $0.0) }) else { return nil }
            return GymTechniqueGuide(slug: "neck_isometric_" + direction.0,
                labels: ["Gentle resistance · no movement"], cues: [
                    "Sit upright, head aligned with your spine and chin gently tucked. Place your palm against your " + direction.1 + ".",
                    "Gently press your head into your hand while your hand prevents movement. Use light pressure, about twenty percent effort.",
                    "Hold for five seconds, breathe normally, then release. This is a still hold, not a neck stretch.",
                    "Only do this once soreness has settled. Stop if it increases pain; do not force, bend or twist your neck."
                ])
        }
        if name.contains("thoracic rotation") {
            return GymTechniqueGuide(slug: "thoracic_rotation", labels: ["1 · Set up", "2 · Open gently"], cues: [
                "Start on hands and knees: supporting hand under shoulder, knees under hips. Place the other fingertips lightly behind your ear.",
                "Turn your upper chest gently to open the elbow toward the ceiling, then return. Work within a comfortable range.",
                "Keep hips steady and your lower back neutral. Do not pull on your head or force your neck. Repeat on the other side."
            ])
        }
        return nil
    }
}
