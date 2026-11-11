import SwiftUI
import MapboxMaps

struct OutdoorRunView: View {
    @ObservedObject var viewModel: RunViewModel
    var onStartRun: () -> Void
    var onFinishRun: () -> Void
    var onOpenApp: () -> Void = {}

    // Mapbox viewport tracks the runner with 45° pitch for 3D
    @State private var viewport: Viewport = .followPuck(
        zoom: 18,
        bearing: .heading,
        pitch: 45
    ).padding(.top, 330)

    private static let redPuckImage: UIImage = {
        let size: CGFloat = 28
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))
            UIColor(Color.stridePrimary).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 3, y: 3, width: size - 6, height: size - 6))
        }
    }()

    @State private var showCountdown = true
    @State private var countdownNumber = 3
    @State private var orbPulse: CGFloat = 1
    @State private var numberPulse: CGFloat = 1
    @State private var countdownTask: Task<Void, Never>?
    @State private var showEndConfirmation = false

    var body: some View {
        ZStack {
            // Map layer (always present, full screen)
            mapLayer

            if showCountdown {
                countdownOverlay
                    .transition(.opacity)
            } else if viewModel.intervalPrescriptionWarning != nil {
                RunView(viewModel: viewModel, onFinishRun: onFinishRun, onOpenApp: onOpenApp)
            } else if viewModel.isPaused {
                pausedOverlay
                    .transition(.opacity)
            } else {
                activeRunOverlay
                    .transition(.opacity)
            }

            // Split feedback toast (active run only)
            if !showCountdown, !viewModel.isPaused, let feedback = viewModel.splitFeedback {
                VStack {
                    Spacer().frame(height: 130)
                    splitFeedbackCard(feedback)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: viewModel.splitFeedback != nil)
            }
        }
        .animation(nil, value: viewModel.isPaused)
        .animation(.easeInOut(duration: 0.25), value: showCountdown)
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
        .alert("End Run?", isPresented: $showEndConfirmation) {
            Button("Keep Running", role: .cancel) { }
            Button("End Run", role: .destructive) { onFinishRun() }
        } message: {
            Text("This saves your current distance. Hold to end was required to open this confirmation.")
        }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("--runview-demo-outdoor") {
                viewport = .camera(center: CLLocationCoordinate2D(latitude: 49.2827, longitude: -123.1207), zoom: 16, bearing: 22, pitch: 45)
                    .padding(.top, 330)
                showCountdown = false
                return
            }
            guard !viewModel.hasActiveProvider else {
                showCountdown = false
                return
            }
            startCountdown()
        }
        .onDisappear {
            countdownTask?.cancel()
            countdownTask = nil
            if showCountdown { IntervalCuePlayer.shared.stopStartRunCountdown() }
        }
    }

    // MARK: - Countdown

    private func startCountdown() {
        guard countdownTask == nil, !viewModel.hasActiveProvider else { return }
        countdownTask = Task { @MainActor in
            countdownNumber = 3
            IntervalCuePlayer.shared.startRunCountdown()
            for number in [3, 2, 1] {
                guard !Task.isCancelled else { return }
                countdownNumber = number
                pulseOrb()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            countdownNumber = 0
            pulseOrb()
            // Let the bundled 3.65-second cue finish before starting the provider,
            // whose audio session setup can cut off the final GO beat.
            do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
            onStartRun()
            withAnimation(.easeOut(duration: 0.25)) { showCountdown = false }
            countdownTask = nil
        }
    }

    private func pulseOrb() {
        orbPulse = 0.94
        numberPulse = 0.76
        withAnimation(.spring(response: 0.34, dampingFraction: 0.53)) {
            orbPulse = 1.13
            numberPulse = 1
        }
        withAnimation(.easeOut(duration: 0.55).delay(0.36)) { orbPulse = 1 }
    }

    // MARK: - Countdown Overlay

    private var countdownOverlay: some View {
        GeometryReader { geometry in
            ZStack {
                Color.stridePrimary.opacity(0.92).ignoresSafeArea()
                LinearGradient(colors: [.black.opacity(0.16), .clear, .black.opacity(0.22)],
                               startPoint: .top, endPoint: .bottom).ignoresSafeArea()

                VStack(spacing: 0) {
                    StrideLogoView(height: 35, color: .white)
                        .padding(.top, 20)
                    Spacer(minLength: 28)
                    Text("GET READY.")
                        .font(.barlowCondensed(size: 43))
                        .foregroundStyle(.white)
                    Spacer(minLength: 12)
                    countdownOrb
                        .frame(width: min(geometry.size.width - 44, 350),
                               height: min(geometry.size.height * 0.51, 430))
                    Spacer(minLength: 12)
                    Text("GO CRUSH IT.")
                        .font(.barlowCondensed(size: 29))
                        .foregroundStyle(.white)
                        .padding(.bottom, 48)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(countdownNumber == 0 ? "Go. Go crush it." : "Get ready. \(countdownNumber)")
    }

    private var countdownOrb: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Ellipse()
                    .stroke(.white.opacity(0.26), lineWidth: 1)
                    .padding(8)
                Ellipse()
                    .trim(from: 0.04, to: 0.40)
                    .stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                    .rotationEffect(.degrees(-150))
                    .padding(3)
                ForEach(0..<72, id: \.self) { index in
                    let angle = Double(index) * 2 * .pi / 72 - .pi / 2
                    let wave = (sin(Double(index) * 0.54) + 1) * 1.5
                    let diameter: CGFloat = 3.4 + CGFloat(wave)
                    Circle()
                        .fill(.white.opacity(index < 42 ? 0.96 : 0.62))
                        .frame(width: diameter, height: diameter)
                        .position(x: size.width / 2 + CGFloat(cos(angle)) * (size.width / 2 - 18),
                                  y: size.height / 2 + CGFloat(sin(angle)) * (size.height / 2 - 20))
                }
                Text(countdownNumber == 0 ? "GO" : "\(countdownNumber)")
                    .font(.barlowCondensed(size: countdownNumber == 0 ? 116 : 205))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .scaleEffect(numberPulse)
                    .contentTransition(.numericText())
            }
            .scaleEffect(orbPulse)
            .shadow(color: .white.opacity(0.25), radius: 24)
        }
    }

    // MARK: - Map Layer

    private var mapLayer: some View {
        Map(viewport: $viewport) {
            if viewModel.routeCoordinates.count >= 2 {
                PolylineAnnotationGroup {
                    PolylineAnnotation(lineCoordinates: viewModel.routeCoordinates)
                        .lineColor(StyleColor(UIColor(Color.stridePrimary.opacity(0.22))))
                        .lineWidth(13)
                    PolylineAnnotation(lineCoordinates: viewModel.routeCoordinates)
                        .lineColor(StyleColor(UIColor(Color.stridePrimary)))
                        .lineWidth(4)
                }
                .lineCap(.round)
                .lineJoin(.round)
            }

            Puck2D(bearing: .heading)
                .topImage(Self.redPuckImage)
                .scale(0.7)

            // Simulator previews have no Core Location puck; render one only
            // for the seeded design fixture so the live route can be reviewed.
            if ProcessInfo.processInfo.arguments.contains("--runview-demo-outdoor"),
               let location = viewModel.routeCoordinates.last {
                MapViewAnnotation(coordinate: location) {
                    Circle().fill(Color.stridePrimary)
                        .frame(width: 19, height: 19)
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                        .background(Circle().fill(Color.stridePrimary.opacity(0.28)).frame(width: 38, height: 38))
                }.allowOverlap(true)
            }

            if let startCoord = viewModel.routeCoordinates.first,
               viewModel.routeCoordinates.count > 5 {
                MapViewAnnotation(coordinate: startCoord) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                }
                .allowOverlap(true)
            }
        }
        .mapStyle(.dark)
        .ornamentOptions(OrnamentOptions(
            scaleBar: ScaleBarViewOptions(visibility: .hidden),
            compass: CompassViewOptions(visibility: .hidden),
            logo: LogoViewOptions(margins: CGPoint(x: -10000, y: -10000)),
            attributionButton: AttributionButtonOptions(margins: CGPoint(x: -10000, y: -10000))
        ))
        .ignoresSafeArea()
    }

    // MARK: - Active Run Overlay

    private var activeRunOverlay: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.18)
                LinearGradient(colors: [.black.opacity(0.42), .black.opacity(0.10), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: geometry.size.height * 0.61)
                    .frame(maxHeight: .infinity, alignment: .top)
                LinearGradient(colors: [.clear, .black.opacity(0.40)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: geometry.size.height * 0.32)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                Canvas { context, size in
                    for x in stride(from: CGFloat(4), through: size.width, by: 8) {
                        for y in stride(from: CGFloat(4), through: size.height, by: 8) {
                            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)),
                                         with: .color(.white.opacity(0.09)))
                        }
                    }
                }
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    HStack {
                        Button(action: onOpenApp) {
                            Image("StrideLogoDark")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 24)
                                .frame(minWidth: 95, minHeight: 44, alignment: .leading)
                        }
                        .accessibilityLabel("Open Stride app")
                        Spacer()
                        Text("OUTDOOR")
                            .font(.runEyebrow(10))
                            .tracking(1.5)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.38), in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.24)))
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Text((viewModel.plannedWorkoutTitle ?? "FREE RUN").uppercased())
                            .font(.barlowCondensed(size: 31, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 10)
                        Text(formatTime(viewModel.elapsedTime))
                            .font(.barlowCondensed(size: 31, weight: .medium))
                            .monospacedDigit()
                    }
                    .padding(.top, 22)

                    Text("CURRENT PACE /KM")
                        .font(.runEyebrow(11))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.66))
                        .padding(.top, 24)
                    Text(viewModel.currentPace.replacingOccurrences(of: " /km", with: ""))
                        .font(.barlowCondensed(size: min(143, geometry.size.height * 0.18), weight: .medium))
                        .monospacedDigit()
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("TARGET")
                            .font(.runEyebrow(11))
                            .foregroundStyle(.white.opacity(0.68))
                        Text(targetPaceText)
                            .font(.barlowCondensed(size: 28, weight: .medium))
                            .monospacedDigit()
                        Spacer(minLength: 4)
                        if viewModel.targetPaceMinSec != nil {
                            Circle().fill(Color(red: 0.24, green: 0.62, blue: 1)).frame(width: 8, height: 8)
                            Text(targetStatus)
                                .font(.runEyebrow(10))
                                .foregroundStyle(Color(red: 0.30, green: 0.70, blue: 1))
                        }
                    }
                    .padding(.top, 4)

                    if viewModel.isIntervalWorkout {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(viewModel.intervalComplete ? "WORKOUT COMPLETE" :
                                     (viewModel.currentIntervalSegment?.displayLabel.uppercased() ?? "INTERVAL"))
                                    .font(.runEyebrow(10)).foregroundStyle(Color.stridePrimary)
                                if let next = viewModel.nextIntervalSegment, !viewModel.intervalComplete {
                                    Text("NEXT / \(next.displayLabel.uppercased())")
                                        .font(.runEyebrow(9)).foregroundStyle(.white.opacity(0.62))
                                }
                            }
                            Spacer(minLength: 4)
                            if !viewModel.intervalComplete {
                                Text(String(format: "%d:%02d", Int(ceil(viewModel.intervalPhaseRemaining)) / 60,
                                            Int(ceil(viewModel.intervalPhaseRemaining)) % 60))
                                    .font(.barlowCondensed(size: 33)).monospacedDigit()
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.black.opacity(0.50), in: RoundedRectangle(cornerRadius: 16))
                        .padding(.top, 10)
                    }

                    Rectangle()
                        .fill(.white.opacity(0.25))
                        .frame(height: 1)
                        .padding(.top, 18)

                    HStack(spacing: 0) {
                        metric("AVERAGE PACE /KM", value: averagePaceText)
                        metric("HEART RATE /BPM", value: viewModel.heartRate > 0 ? "\(viewModel.heartRate)" : "—", symbol: "heart.fill")
                    }
                    .padding(.top, 17)

                    HStack(spacing: 0) {
                        metric("DISTANCE TO GO", value: remainingDistanceText, unit: "KM")
                        metric("DISTANCE", value: distanceProgressText, compact: true)
                    }
                    .padding(.top, 22)

                    Spacer(minLength: 32)

                    HStack {
                        Circle().fill(viewModel.hasActiveProvider ? Color(red: 0.24, green: 0.62, blue: 1) : .gray)
                            .frame(width: 6, height: 6)
                        Text(viewModel.hasActiveProvider ? "GPS LOCKED · ROUTE LIVE" : "WAITING FOR GPS")
                        Spacer()
                        Text("© MAPBOX · © OPENSTREETMAP")
                    }
                    .font(.runEyebrow(8))
                    .tracking(0.4)
                    .foregroundStyle(.white.opacity(0.64))
                    .padding(.bottom, 14)

                    Button { viewModel.pauseRun() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "pause.fill").font(.system(size: 18))
                            Text("PAUSE SESSION")
                                .font(.barlowCondensed(size: 24, weight: .semibold))
                                .tracking(1)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 59)
                        .background(Color.stridePrimary, in: Capsule())
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.top, 55)
                .padding(.bottom, 44)
            }
            .ignoresSafeArea(edges: [.top, .bottom])
        }
        .preferredColorScheme(.dark)
    }

    private func metric(_ label: String, value: String, unit: String? = nil,
                        symbol: String? = nil, compact: Bool = false) -> some View {
        VStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(.runEyebrow(10))
                .tracking(1.3)
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.barlowCondensed(size: compact ? 30 : 49, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit {
                    Text(unit).font(.runEyebrow(11)).foregroundStyle(.white.opacity(0.7))
                }
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 19)).foregroundStyle(.pink)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var targetPaceText: String {
        guard let min = viewModel.targetPaceMinSec, let max = viewModel.targetPaceMaxSec else { return "FREE RUN" }
        func pace(_ seconds: Double) -> String { String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
        return "\(pace(min))–\(pace(max)) /km"
    }

    private var targetStatus: String {
        switch viewModel.paceZone {
        case .onPace, .slightlyFast: return "ON TARGET"
        case .slightlySlow, .tooSlow: return "SLOW"
        case .tooFast: return "FAST"
        case .noTarget: return "ACQUIRING"
        }
    }

    private var averagePaceText: String {
        guard viewModel.distance > 0.05 else { return "—" }
        let seconds = Int(viewModel.elapsedTime / viewModel.distance)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var remainingDistanceText: String {
        guard let target = viewModel.targetDistanceKm else { return "—" }
        return String(format: "%.2f", max(0, target - viewModel.distance))
    }

    private var distanceProgressText: String {
        let covered = String(format: "%.2f", viewModel.distance)
        guard let target = viewModel.targetDistanceKm else { return "\(covered) KM" }
        return "\(covered) / \(String(format: "%.0f", target)) KM"
    }

    // MARK: - Paused Overlay

    private var pausedOverlay: some View {
        ZStack {
            // Red overlay
            Color.stridePrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Logo
                Button(action: onOpenApp) {
                    StrideLogoView(height: 35, color: .white)
                }
                .accessibilityLabel("Open Stride app")
                .padding(.top, 30)

                // "Pause Run" label
                Text("Pause Run")
                    .font(.inter(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.top, 12)

                // Pause duration timer
                Text(formatTime(viewModel.currentPauseDuration))
                    .font(.barlowCondensed(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 4)

                Spacer()

                // Distance
                VStack(spacing: 4) {
                    Text(String(format: "%.2f", viewModel.distance))
                        .font(.barlowCondensed(size: 100, weight: .medium))
                        .foregroundColor(.white)
                    Text("Distance (km)")
                        .font(.inter(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer().frame(height: 28)

                // Time
                VStack(spacing: 4) {
                    Text(formatTime(viewModel.elapsedTime))
                        .font(.barlowCondensed(size: 100, weight: .medium))
                        .foregroundColor(.white)
                    Text("Time")
                        .font(.inter(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer().frame(height: 28)

                // Avg Pace
                VStack(spacing: 4) {
                    Text(viewModel.currentPace)
                        .font(.barlowCondensed(size: 100, weight: .medium))
                        .foregroundColor(.white)
                    Text("Avg Pace")
                        .font(.inter(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                // Resume + End Run buttons
                HStack(spacing: 12) {
                    Button {
                        viewModel.resumeRun()
                    } label: {
                        Text("Resume")
                            .font(.inter(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.black)
                            .clipShape(Capsule())
                    }

                    HoldToEndRunButton(foreground: .stridePrimary, background: .white) {
                        showEndConfirmation = true
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Split Feedback Card

    private func splitFeedbackCard(_ feedback: SplitFeedback) -> some View {
        let bgColor: Color = feedback.category == .faster ? .blue : Color.stridePrimary

        return HStack(spacing: 8) {
            Text("\(feedback.pace) /km")
                .font(.barlowCondensed(size: 22, weight: .medium))
                .foregroundColor(.white)

            if let diff = feedback.diffSeconds {
                Text(diff <= 0 ? "\(diff)s" : "+\(diff)s")
                    .font(.barlowCondensed(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(bgColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
    }

    // MARK: - Helpers

    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

#Preview {
    OutdoorRunView(viewModel: RunViewModel(), onStartRun: {}, onFinishRun: {})
}
