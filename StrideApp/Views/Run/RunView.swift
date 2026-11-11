import SwiftUI

struct RunView: View {
    @ObservedObject var viewModel: RunViewModel
    @EnvironmentObject private var bluetoothManager: BluetoothManager
    var onFinishRun: () -> Void
    var onOpenApp: () -> Void = {}

    @State private var showFinishConfirmation = false
    @State private var splitDismissOffset: CGFloat = 0

    /// Work phases retain their red cue; pausing also shows a dedicated red screen.
    private var isWorkPhase: Bool {
        guard !viewModel.intervalComplete else { return false }
        if case .work = viewModel.currentIntervalSegment?.kind { return true }
        return false
    }
    private var intervalFg: Color { isWorkPhase ? .white : .primary }

    /// Verdict-pill accent for the live pace (fill on white screens, text on red)
    private var intervalPillTextColor: Color {
        switch viewModel.paceZone {
        case .onPace, .slightlyFast: return .green
        case .slightlySlow: return .orange
        case .tooSlow: return Color.stridePrimary
        case .tooFast: return .blue
        case .noTarget: return .gray
        }
    }

    /// Bottom-button backdrop matches the live background so the fade is
    /// invisible on both the red work screen and the white screens.
    private var backdropColor: Color {
        viewModel.isPaused || (viewModel.isIntervalWorkout && isWorkPhase) ? Color.stridePrimary : Color(red: 0.055, green: 0.055, blue: 0.065)
    }
    private var intervalFgSoft: Color { isWorkPhase ? .white.opacity(0.8) : .secondary }

    var body: some View {
        GeometryReader { viewport in
        ZStack(alignment: .bottom) {
            if viewModel.isIntervalWorkout && (!viewModel.isStrideWorkout || isWorkPhase) {
                intervalContent
            } else {
            indoorContent
            .overlay(alignment: .top) {
                if let feedback = viewModel.splitFeedback {
                    splitFeedbackCard(feedback)
                        .offset(y: splitDismissOffset)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if value.translation.height < 0 {
                                        splitDismissOffset = value.translation.height
                                    }
                                }
                                .onEnded { value in
                                    if value.translation.height < -50 {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            viewModel.splitFeedback = nil
                                        }
                                    }
                                    splitDismissOffset = 0
                                }
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 60)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.splitFeedback != nil)
            .onChange(of: viewModel.splitFeedback?.id) { _, _ in
                splitDismissOffset = 0
            }
            }

            if viewModel.isPaused {
                pausedContent
            }

        }
        .background {
            ZStack {
                backdropColor
                if !viewModel.isPaused && !isWorkPhase {
                    indoorDots
                }
            }.ignoresSafeArea()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            runControls
        }
        .transaction { transaction in
            // A pause is a screen-state change, not a resizing animation.
            transaction.animation = nil
        }
        }
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .alert("End Run?", isPresented: $showFinishConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("End Run", role: .destructive) {
                onFinishRun()
            }
        } message: {
            Text("End your current run and review your results.")
        }
    }
    
    private var runControls: some View {
        Group {
            if viewModel.isPaused {
                HStack(spacing: 12) {
                    Button { viewModel.resumeRun() } label: {
                        controlLabel("Resume", foreground: .stridePrimary, background: .white)
                    }
                    HoldToEndRunButton(foreground: .white, background: .strideBrandBlack) {
                        showFinishConfirmation = true
                    }
                }
            } else {
                Button { viewModel.pauseRun() } label: {
                    controlLabel("Pause Run", foreground: isWorkPhase ? .stridePrimary : .white,
                                 background: isWorkPhase ? .white : .stridePrimary)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background((viewModel.isPaused || isWorkPhase ? backdropColor : .clear).ignoresSafeArea(edges: .bottom))
        .transaction { $0.animation = nil }
    }

    private func controlLabel(_ title: String, foreground: Color, background: Color) -> some View {
        Text(title.uppercased())
            .font(.barlowCondensed(size: 24, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .background(background, in: Capsule())
    }

    private var indoorContent: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack {
                    Button(action: onOpenApp) {
                        Image("StrideLogoDark").resizable().scaledToFit().frame(height: 25)
                    }.buttonStyle(.plain).accessibilityLabel("Open Stride app")
                    Spacer()
                    Text("INDOOR").font(.runEyebrow(10)).tracking(1.4)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.white.opacity(0.08), in: Capsule())
                }
                HStack(alignment: .firstTextBaseline) {
                    Text((viewModel.plannedWorkoutTitle ?? "FREE RUN").uppercased())
                        .font(.barlowCondensed(size: 31, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    Text(formatTime(viewModel.elapsedTime))
                        .font(.barlowCondensed(size: 31)).monospacedDigit()
                }.padding(.top, 20)

                if !ProcessInfo.processInfo.arguments.contains("--runview-demo") {
                    TreadmillDataStatusBanner(bluetoothManager: bluetoothManager)
                        .padding(.top, 8)
                }

                Spacer(minLength: 10)
                Text("CURRENT PACE /KM")
                    .font(.runEyebrow(11)).tracking(1.8).foregroundStyle(.white.opacity(0.62))
                Text(viewModel.currentPace)
                    .font(.barlowCondensed(size: min(135, geometry.size.height * 0.17)))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    .contentTransition(.numericText())

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("TARGET").font(.runEyebrow(10)).foregroundStyle(.white.opacity(0.62))
                    Text(indoorTargetPace).font(.barlowCondensed(size: 28))
                    Spacer()
                    if !viewModel.paceZone.statusText.isEmpty {
                        Circle().fill(Color(red: 0.25, green: 0.65, blue: 1)).frame(width: 7, height: 7)
                        Text(viewModel.paceZone.statusText.uppercased())
                            .font(.runEyebrow(9)).foregroundStyle(Color(red: 0.35, green: 0.72, blue: 1))
                    }
                }.padding(.bottom, 13)

                PaceBandGraphView(
                    paces: viewModel.paceGraphPaces,
                    targetMinSec: viewModel.targetPaceMinSec,
                    targetMaxSec: viewModel.targetPaceMaxSec,
                    heartRates: viewModel.paceGraphHeartRates,
                    distances: viewModel.paceGraphDistances,
                    targetHeartRateRange: currentHeartRateTarget,
                    graphHeight: min(138, geometry.size.height * 0.17),
                    paceColor: .stridePrimary,
                    labelColor: .white.opacity(0.65)
                )
                .padding(.vertical, 15)

                Spacer(minLength: 10)
                Rectangle().fill(.white.opacity(0.19)).frame(height: 1)
                HStack(spacing: 0) {
                    indoorMetric("DISTANCE", value: String(format: "%.2f", viewModel.distance), unit: "KM")
                    indoorMetric("TO GO", value: viewModel.targetDistanceKm.map { String(format: "%.2f", max(0, $0 - viewModel.distance)) } ?? "—", unit: "KM")
                }.padding(.top, 14)
                HStack(spacing: 0) {
                    indoorMetric("HEART RATE", value: viewModel.heartRate > 0 ? "\(viewModel.heartRate)" : "—", unit: "BPM")
                    indoorMetric("AVERAGE PACE", value: viewModel.distance > 0.05 ? formatPaceSeconds(viewModel.elapsedTime / viewModel.distance) : "—", unit: "/KM")
                }.padding(.top, 14)
                Spacer(minLength: 14)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22).padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var indoorDots: some View {
        Canvas { context, size in
            for x in stride(from: CGFloat(4), through: size.width, by: 8) {
                for y in stride(from: CGFloat(4), through: size.height, by: 8) {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)),
                                 with: .color(.white.opacity(0.075)))
                }
            }
        }.allowsHitTesting(false)
    }

    private var indoorTargetPace: String {
        guard let fast = viewModel.targetPaceMinSec, let slow = viewModel.targetPaceMaxSec else { return "FREE RUN" }
        return "\(formatPaceSeconds(fast))–\(formatPaceSeconds(slow))"
    }

    private func formatPaceSeconds(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "—" }
        let value = Int(seconds.rounded())
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    private func indoorMetric(_ title: String, value: String, unit: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.runEyebrow(9)).tracking(1.2).foregroundStyle(.white.opacity(0.62))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.barlowCondensed(size: 37)).monospacedDigit()
                Text(unit).font(.runEyebrow(9)).foregroundStyle(.white.opacity(0.62))
            }.lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity)
    }

    // MARK: - Interval Mode

    private var intervalContent: some View {
        GeometryReader { geometry in
            let numberSize: CGFloat = geometry.size.height < 700 ? 72 : 90
            ScrollView {
                VStack(spacing: 12) {
                    HStack {
                        Button(action: onOpenApp) {
                            StrideLogoView(height: 26, color: isWorkPhase ? .white : nil)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open STRIDE app")
                        Spacer()
                        Text(formatTime(viewModel.elapsedTime))
                            .font(.barlowCondensed(size: 26, weight: .medium))
                            .foregroundColor(intervalFgSoft)
                            .monospacedDigit()
                    }
                    .padding(.top, 18)

                    if viewModel.intervalComplete {
                        VStack(spacing: 14) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 46)).foregroundColor(.green)
                            Text("WORKOUT COMPLETE").font(.inter(size: 22, weight: .bold))
                            Text("Pause, then End Run when you're done")
                                .font(.inter(size: 15)).foregroundColor(.secondary)
                        }
                        .padding(.vertical, 24)
                    } else if let segment = viewModel.currentIntervalSegment {
                        VStack(spacing: 4) {
                            Text(segment.displayLabel)
                                .font(.inter(size: 15, weight: .semibold))
                                .foregroundColor(intervalFgSoft)
                            if let duration = segment.durationSec {
                                Text(formatCountdownShort(viewModel.intervalPhaseRemaining))
                                    .font(.barlowCondensed(size: numberSize, weight: .medium))
                                    .foregroundColor(intervalFg)
                                    .monospacedDigit()
                                phaseProgress(1 - viewModel.intervalPhaseRemaining / max(duration, 1))
                            } else if let target = segment.distanceKm {
                                Text(String(format: "%.2f / %.1f km", viewModel.intervalPhaseDistanceDone, target))
                                    .font(.barlowCondensed(size: 52, weight: .medium))
                                    .foregroundColor(intervalFg)
                                    .minimumScaleFactor(0.7)
                                    .lineLimit(1)
                                phaseProgress(viewModel.intervalPhaseDistanceDone / max(target, 0.01))
                            }
                        }

                        VStack(spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(viewModel.isStrideWorkout ? String(format: "%.1f", viewModel.speedKmh) : viewModel.currentPace)
                                    .font(.barlowCondensed(size: numberSize, weight: .medium))
                                    .foregroundColor(intervalFg)
                                    .contentTransition(.numericText())
                                Text(viewModel.isStrideWorkout ? "km/h" : "/km")
                                    .font(.inter(size: 15, weight: .medium))
                                    .foregroundColor(intervalFgSoft)
                            }
                            HStack(spacing: 10) {
                                Text(segment.paceText == "easy" ? "easy — shake it out" : "target \(segment.paceText)")
                                    .font(.inter(size: 15, weight: .semibold))
                                    .foregroundColor(intervalFgSoft)
                                if segment.paceBounds != nil, !viewModel.paceZone.statusText.isEmpty {
                                    Text(viewModel.paceZone.statusText)
                                        .font(.inter(size: 15, weight: .bold))
                                        .foregroundColor(isWorkPhase ? intervalPillTextColor : .white)
                                        .padding(.horizontal, 9).padding(.vertical, 4)
                                        .background(Capsule().fill(isWorkPhase ? Color.white : intervalPillTextColor))
                                }
                            }
                        }
                    }

                    heartRateLine

                    PaceBandGraphView(
                        paces: viewModel.paceGraphPaces,
                        targetMinSec: viewModel.targetPaceMinSec,
                        targetMaxSec: viewModel.targetPaceMaxSec,
                        heartRates: viewModel.paceGraphHeartRates,
                        distances: viewModel.paceGraphDistances,
                        targetHeartRateRange: currentHeartRateTarget,
                        graphHeight: geometry.size.height < 700 ? 72 : 90,
                        paceColor: isWorkPhase ? .white : .stridePrimary,
                        labelColor: intervalFgSoft
                    )

                    if !viewModel.intervalComplete, let next = viewModel.nextIntervalSegment {
                        Text("Next: \(nextLabel(next))")
                            .font(.inter(size: 15, weight: .medium))
                            .foregroundColor(intervalFgSoft)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func phaseProgress(_ fraction: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(isWorkPhase ? Color.white.opacity(0.2) : Color(.systemGray5))
                Capsule().fill(isWorkPhase ? Color.white : Color.stridePrimary)
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 7)
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private var pausedContent: some View {
        VStack(spacing: 18) {
            Button(action: onOpenApp) {
                StrideLogoView(height: 30, color: .white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open STRIDE app")
            Text("RUN PAUSED").font(.inter(size: 16, weight: .semibold))
            Text(formatTime(viewModel.currentPauseDuration))
                .font(.barlowCondensed(size: 24, weight: .medium)).monospacedDigit()
            Spacer()
            Text(String(format: "%.2f km", viewModel.distance))
                .font(.barlowCondensed(size: 70, weight: .medium))
            Text(formatTime(viewModel.elapsedTime))
                .font(.barlowCondensed(size: 54, weight: .medium)).monospacedDigit()
            Text("Run time").font(.inter(size: 15))
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.stridePrimary.ignoresSafeArea())
    }

    private var currentHeartRateTarget: ClosedRange<Int>? {
        let type: WorkoutType?
        if viewModel.isIntervalWorkout, !viewModel.intervalComplete,
           let segment = viewModel.currentIntervalSegment {
            switch segment.kind {
            case .work: type = viewModel.plannedWorkoutType
            case .warmup, .float, .cooldown: type = .easyRun
            }
        } else {
            type = viewModel.plannedWorkoutType
        }
        guard let type, let band = HeartRateZones.band(for: type) else { return nil }
        let bounds = band.split(separator: "–").compactMap { Int($0) }
        guard bounds.count == 2, bounds[0] <= bounds[1] else { return nil }
        return bounds[0]...bounds[1]
    }

    private func nextLabel(_ segment: IntervalSegment) -> String {
        switch segment.kind {
        case .warmup: return "warm-up"
        case .work(let rep, let of):
            let dur = segment.durationSec.map { formatCountdownShort($0) }
                ?? segment.distanceKm.map { String(format: "%g km", $0) } ?? ""
            return "rep \(rep)/\(of) — \(dur) at \(segment.paceText)"
        case .float:
            let dur = segment.durationSec.map { formatCountdownShort($0) }
                ?? segment.distanceKm.map { String(format: "%g km", $0) } ?? ""
            return "\(dur) recovery"
        case .cooldown:
            let km = segment.distanceKm.map { String(format: "%.1f", $0) } ?? ""
            return "\(km) km cool-down"
        }
    }

    private func formatCountdownShort(_ seconds: Double) -> String {
        let s = Int(ceil(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: - Header Row
    private var headerRow: some View {
        HStack {
            Button(action: onOpenApp) {
                StrideLogoView(height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open STRIDE app")
            Spacer()
            if viewModel.isTimeBasedWorkout, let remaining = viewModel.remainingTimeSeconds {
                Text(formatTime(remaining))
                    .font(.barlowCondensed(size: 28, weight: .medium))
                    .foregroundColor(.primary)
                    .monospacedDigit()
            } else {
                Text(formatTime(viewModel.elapsedTime))
                    .font(.barlowCondensed(size: 28, weight: .medium))
                    .foregroundColor(.primary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Pace Block (hero + verdict pill)
    private func paceBlock(size: CGFloat) -> some View {
        VStack(spacing: 0) {
            Text(viewModel.currentPace)
                .font(.barlowCondensed(size: size, weight: .medium))
                .foregroundColor(.primary)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                Text("Pace /km")
                    .font(.inter(size: 15, weight: .regular))
                    .foregroundColor(.secondary)

                if viewModel.isPlannedRun, !viewModel.paceZone.statusText.isEmpty {
                    Text(viewModel.paceZone.statusText)
                        .font(.inter(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(pillColor))
                }
            }
        }
    }

    /// Verdict pill: green = good, red = slow, blue = fast. Color does the
    /// thinking so the text never has to be read mid-stride.
    private var pillColor: Color {
        switch viewModel.paceZone {
        case .onPace, .slightlyFast: return .green
        case .slightlySlow: return .orange
        case .tooSlow: return Color.stridePrimary
        case .tooFast: return .blue
        case .noTarget: return .gray
        }
    }

    // MARK: - Distance Progress
    private var distanceProgress: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(String(format: "%.2f", viewModel.distance))
                        .font(.barlowCondensed(size: 52, weight: .medium))
                        .foregroundColor(.primary)
                        .contentTransition(.numericText())
                    Text("km")
                        .font(.inter(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if viewModel.isPlannedRun, let target = viewModel.targetDistanceKm {
                    Text(remainingLabel(target: target))
                        .font(.inter(size: 15, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }

            if viewModel.isPlannedRun, let target = viewModel.targetDistanceKm, target > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.systemGray5))
                            .frame(height: 10)
                        Capsule()
                            .fill(Color.stridePrimary)
                            .frame(width: max(10, geo.size.width * min(viewModel.distance / target, 1.0)),
                                   height: 10)
                    }
                }
                .frame(height: 10)
            }
        }
    }

    private func remainingLabel(target: Double) -> String {
        let left = target - viewModel.distance
        if left <= 0 { return "target reached" }
        return String(format: "%.2f to go", left)
    }

    // MARK: - Heart Rate Line
    @ViewBuilder
    private var heartRateLine: some View {
        let band = currentHeartRateTarget.map { "\($0.lowerBound)–\($0.upperBound)" }
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                LiveHeartRateLabel(bpm: viewModel.heartRate > 0 ? viewModel.heartRate : nil,
                                   tint: isWorkPhase ? .white : .heartRatePink)
                if let band { Text("Target HR \(band) bpm").font(.inter(size: 15)).foregroundStyle(intervalFgSoft) }
            }
            VStack(spacing: 4) {
                LiveHeartRateLabel(bpm: viewModel.heartRate > 0 ? viewModel.heartRate : nil,
                                   tint: isWorkPhase ? .white : .heartRatePink)
                if let band { Text("Target HR \(band) bpm").font(.inter(size: 15)).foregroundStyle(intervalFgSoft) }
            }
        }
    }
    

    // MARK: - Metrics Row
    private var metricsRow: some View {
        HStack(spacing: 32) {
            // Pace Drift (Left)
            VStack(alignment: .center, spacing: 4) {
                Text("Pace Drift")
                    .font(.inter(size: 15, weight: .regular))
                    .foregroundColor(.secondary)
                
                Text(viewModel.paceDrift)
                    .font(.barlowCondensed(size: 28, weight: .medium))
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            // Heart Rate / Zone (Right)
            VStack(alignment: .center, spacing: 4) {
                Text("Heart Rate / Zone")
                    .font(.inter(size: 15, weight: .regular))
                    .foregroundColor(.secondary)
                
                Text(viewModel.heartRate > 0 ? "\(viewModel.heartRate)" : "--")
                    .font(.barlowCondensed(size: 28, weight: .medium))
                    .foregroundColor(.primary)
                
                Text(viewModel.heartRateZone.displayText)
                    .font(.inter(size: 15, weight: .medium))
                    .foregroundColor(viewModel.heartRateZone.color)
            }
        }
    }
    
    // MARK: - Kilometer Splits Table
    private var kilometerSplitsTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Table Header - 4 columns with specific spacing
            HStack(spacing: 0) {
                // Column 1: KM (left-aligned, fixed size)
                Text("KM")
                    .font(.inter(size: 15, weight: .medium))
                    .foregroundColor(.secondary)
                    .fixedSize()
                
                // Column 2: Fastest icon (more padding from KM column)
                Color.clear
                    .frame(width: 80)
                
                // Spacer to center Pace
                Spacer()
                
                // Column 3: Pace (centered)
                Text("Pace")
                    .font(.inter(size: 15, weight: .medium))
                    .foregroundColor(.secondary)
                    .fixedSize()

                // Column 4: Diff (no visible header)
                Color.clear
                    .frame(width: 50)

                // Spacer to push Time to far right
                Spacer()

                // Column 5: Time (right-aligned, far right)
                Text("Time")
                    .font(.inter(size: 15, weight: .medium))
                    .foregroundColor(.secondary)
                    .fixedSize()
            }
            .lineLimit(1)
            .padding(.bottom, 12)
            
            // Splits Rows - 4 columns with specific spacing
            ForEach(viewModel.kilometerSplits.reversed()) { split in
                HStack(spacing: 0) {
                    // Column 1: KM (left-aligned, fixed size)
                    Text("\(split.kilometer)")
                        .font(.barlowCondensed(size: 22, weight: .medium))
                        .foregroundColor(.primary)
                        .fixedSize()
                    
                    // Column 2: Fastest icon (more padding from KM column)
                    Group {
                        if split.isFastest {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.stridePrimary)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 80)
                    
                    // Spacer to center Pace
                    Spacer()
                    
                    // Column 3: Pace (centered)
                    Text("\(split.pace) /km")
                        .font(.barlowCondensed(size: 22, weight: .medium))
                        .foregroundColor(.primary)
                        .fixedSize()

                    // Column 4: Diff from fastest
                    Text(split.diffFromFastest.map { $0 == 0 ? "\u{2014}" : "+\($0)s" } ?? "")
                        .font(.barlowCondensed(size: 18, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 50)

                    // Spacer to push Time to far right
                    Spacer()

                    // Column 5: Time (right-aligned, far right, no leading zeros)
                    Text(formatTimeString(split.time))
                        .font(.barlowCondensed(size: 22, weight: .medium))
                        .foregroundColor(.primary)
                        .fixedSize()
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.vertical, 12)
                
                // Red separator line
                if split.kilometer > 1 {
                    Rectangle()
                        .fill(Color.stridePrimary.opacity(0.3))
                        .frame(height: 1)
                }
            }
        }
    }
    
    // MARK: - Split Feedback Card
    private func splitFeedbackCard(_ feedback: SplitFeedback) -> some View {
        let bgColor: Color = feedback.category == .faster ? .blue : Color.stridePrimary
        let textColor: Color = .white

        return HStack(spacing: 8) {
            Text("\(feedback.pace) /km")
                .font(.barlowCondensed(size: 22, weight: .medium))
                .foregroundColor(textColor)

            if let diff = feedback.diffSeconds {
                Text(diff <= 0 ? "\(diff)s" : "+\(diff)s")
                    .font(.barlowCondensed(size: 18, weight: .medium))
                    .foregroundColor(textColor.opacity(0.85))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(bgColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
    }

    // MARK: - Helper Functions

    private func formatTargetDistanceLabel(_ km: Double) -> String {
        km == floor(km) ? "\(Int(km))K" : String(format: "%.1fK", km)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    private func formatTimeString(_ timeString: String) -> String {
        // Parse time string (format: "HH:MM:SS" or "MM:SS")
        let components = timeString.split(separator: ":").compactMap { Int($0) }
        
        if components.count == 3 {
            // Format: HH:MM:SS
            let hours = components[0]
            let minutes = components[1]
            let seconds = components[2]
            
            if hours > 0 {
                // Show full format with hours
                return String(format: "%d:%02d:%02d", hours, minutes, seconds)
            } else {
                // Remove hours and leading zero from minutes
                return String(format: "%d:%02d", minutes, seconds)
            }
        } else if components.count == 2 {
            // Format: MM:SS - remove leading zero from minutes if present
            let minutes = components[0]
            let seconds = components[1]
            return String(format: "%d:%02d", minutes, seconds)
        }
        
        return timeString
    }
}

/// An uninterrupted hold is required before the separate finish confirmation.
/// A zero-distance drag gives immediate press/release events, including when the
/// finger moves slightly, unlike a long press attached to a Button.
struct HoldToEndRunButton: View {
    let foreground: Color
    let background: Color
    let onComplete: () -> Void

    @State private var secondsRemaining = 3
    @State private var holdTask: Task<Void, Never>?
    @State private var isHolding = false
    @State private var movedTooFar = false
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            Capsule().fill(background)
            GeometryReader { geometry in
                Capsule()
                    .fill(foreground.opacity(0.22))
                    .frame(width: geometry.size.width * progress)
                    .frame(maxHeight: .infinity, alignment: .leading)
                    .clipShape(Capsule())
            }
            Text(isHolding ? "END IN \(secondsRemaining)" : "HOLD 3 SEC TO END")
                .font(.barlowCondensed(size: 24, weight: .semibold))
                .foregroundStyle(foreground)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .frame(height: 62)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if abs(value.translation.width) > 45 || abs(value.translation.height) > 45 {
                        movedTooFar = true
                        cancelHold()
                    } else if !movedTooFar && !isHolding {
                        beginHold()
                    }
                }
                .onEnded { _ in
                    cancelHold()
                    movedTooFar = false
                }
        )
        .accessibilityLabel(isHolding ? "End run in \(secondsRemaining)" : "Hold for three seconds to end run")
        .onDisappear { cancelHold() }
    }

    private func beginHold() {
        guard holdTask == nil else { return }
        isHolding = true
        secondsRemaining = 3
        progress = 0
        withAnimation(.linear(duration: 3)) { progress = 1 }
        holdTask = Task { @MainActor in
            for remaining in [2, 1, 0] {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard !Task.isCancelled else { return }
                secondsRemaining = remaining
            }
            holdTask = nil
            isHolding = false
            movedTooFar = true // Do not restart while the same finger remains down.
            progress = 0
            onComplete()
        }
    }

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
        isHolding = false
        secondsRemaining = 3
        withAnimation(.none) { progress = 0 }
    }
}

// MARK: - Heart Rate Zone
enum HeartRateZone {
    case zone1, zone2, zone3, zone4, zone5
    
    var displayText: String {
        switch self {
        case .zone1: return "Z1 - Recovery"
        case .zone2: return "Z2 - Aerobic"
        case .zone3: return "Z3 - Tempo"
        case .zone4: return "Z4 - Threshold"
        case .zone5: return "Z5 - Maximum"
        }
    }
    
    var color: Color {
        switch self {
        case .zone1: return .green
        case .zone2: return .blue
        case .zone3: return .yellow
        case .zone4: return Color(red: 1.0, green: 0.5, blue: 0.0) // Warm orange
        case .zone5: return .red
        }
    }
}

// MARK: - Kilometer Split
struct KilometerSplit: Identifiable, Codable {
    var id = UUID()
    let kilometer: Int
    let pace: String
    let time: String
    let isFastest: Bool
    let diffFromFastest: Int?  // seconds slower than fastest split (0 = fastest, nil = not yet computed)
}

#Preview {
    NavigationStack {
        RunView(viewModel: RunViewModel(), onFinishRun: {})
    }
    .environmentObject(BluetoothManager())
}

// MARK: - Treadmill Data Status Banner

/// Shows a warning while a treadmill run is receiving no packets, and a brief
/// diagnostic string when the subscription itself failed. Silent when healthy.
struct TreadmillDataStatusBanner: View {
    @ObservedObject var bluetoothManager: BluetoothManager

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let stale: Bool = {
                guard let last = bluetoothManager.lastPacketAt else { return true }
                return context.date.timeIntervalSince(last) > 5
            }()

            if stale {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 13, weight: .semibold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(bluetoothManager.packetCount == 0
                             ? "No data from treadmill"
                             : "Treadmill signal lost")
                            .font(.inter(size: 15, weight: .semibold))
                        Text(statusDetail)
                            .font(.inter(size: 15, weight: .regular))
                            .opacity(0.85)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.stridePrimary)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 16)
            }
        }
    }

    private var statusDetail: String {
        if bluetoothManager.connectedDevice == nil {
            return "Not connected — check Bluetooth on the console"
        }
        switch bluetoothManager.subscriptionState {
        case "Subscribed":
            return "Connected and subscribed — start the belt / wake the console"
        case "—":
            return "Connected — waiting for the data service"
        default:
            return bluetoothManager.subscriptionState
        }
    }
}
