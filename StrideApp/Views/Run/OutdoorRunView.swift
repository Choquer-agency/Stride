import SwiftUI
import MapboxMaps

struct OutdoorRunView: View {
    @ObservedObject var viewModel: RunViewModel
    var onStartRun: () -> Void
    var onFinishRun: () -> Void

    // Mapbox viewport tracks the runner with 45° pitch for 3D
    @State private var viewport: Viewport = .followPuck(
        zoom: 18,
        bearing: .heading,
        pitch: 45
    )

    private static let styleURI = StyleURI(rawValue: "mapbox://styles/choquer/cmnrp6hea002p01suci3bhyid")!

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
    @State private var countdownPaused = false
    @State private var countdownScale: CGFloat = 0.5
    @State private var countdownOpacity: Double = 0
    @State private var introPhase: IntroPhase = .waiting
    @State private var hasPlayedIntro = false

    enum IntroPhase {
        case waiting      // red screen up, no number yet (fetching/playing AI intro)
        case numbers      // 3 → 2 → 1 animating
    }

    private var tts: ElevenLabsTTSService { .shared }

    var body: some View {
        ZStack {
            // Map layer (always present, full screen)
            mapLayer

            if showCountdown {
                countdownOverlay
                    .transition(.opacity)
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
        .animation(.easeInOut(duration: 0.25), value: viewModel.isPaused)
        .animation(.easeInOut(duration: 0.25), value: showCountdown)
        .navigationBarHidden(true)
        .onAppear {
            // Delay to let map calibrate, then start countdown
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                startCountdown()
            }
        }
    }

    // MARK: - Countdown

    private func startCountdown() {
        guard !countdownPaused else { return }

        // On resume (pause → unpause), skip the AI intro and use the bundled countdown.
        if hasPlayedIntro {
            playBundledCountdown()
            return
        }
        hasPlayedIntro = true
        introPhase = .waiting

        // Fetch Claude's motivational intro — which ends with its own spoken
        // countdown. When the audio finishes, the timer starts immediately. If
        // the fetch fails, fall back to the bundled "3, 2, 1, let's go".
        Task {
            let introText = await fetchPreRunIntro()
            await MainActor.run {
                guard !countdownPaused else { return }
                if let text = introText, !text.isEmpty {
                    tts.speakSequence([.text(text)]) {
                        guard !countdownPaused else { return }
                        startRunNow()
                    }
                } else {
                    playBundledCountdown()
                }
            }
        }
    }

    /// Final handoff: Claude's spoken countdown just landed — start the run.
    private func startRunNow() {
        onStartRun()
        withAnimation {
            showCountdown = false
        }
    }

    private func playBundledCountdown() {
        guard !countdownPaused else { return }
        introPhase = .numbers
        countdownNumber = 3
        animateCountdownNumber()

        // Play the full bundled countdown audio (3...2...1...let's go)
        tts.speakSequence([.bundled("countdown_2")])

        // Animate numbers visually: 3 at 0s, 2 at 1s, 1 at 2s, dismiss at 3s
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard !self.countdownPaused else { return }
            self.countdownNumber = 2
            self.animateCountdownNumber()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard !self.countdownPaused else { return }
            self.countdownNumber = 1
            self.animateCountdownNumber()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            guard !self.countdownPaused else { return }
            // "Let's go" just landed — start the run.
            self.onStartRun()
            withAnimation {
                self.showCountdown = false
            }
        }
    }

    /// Build and send the pre-run coach request. Returns nil on any failure so the
    /// caller falls through to the bundled countdown.
    @MainActor
    private func fetchPreRunIntro() async -> String? {
        let athleteName: String? = {
            if case .signedIn(let user) = AuthService.shared.authState { return user.name }
            if case .needsProfile(let user) = AuthService.shared.authState { return user.name }
            return nil
        }()
        let request = PreRunCoachRequest(
            athleteName: athleteName,
            workoutType: viewModel.plannedWorkoutType?.displayName,
            workoutTitle: viewModel.plannedWorkoutTitle,
            targetDistanceKm: viewModel.targetDistanceKm,
            targetDurationMinutes: viewModel.targetDurationMinutes,
            targetPace: viewModel.targetPaceDescription,
            isFreeRun: !viewModel.isPlannedRun,
            goalRace: nil,
            weeksToRace: nil
        )
        do {
            let text = try await APIService.shared.preRunCoach(request: request)
            print("[PreRunCoach] AI intro received (\(text.count) chars): \(text)")
            return text
        } catch {
            print("[PreRunCoach] Falling back to bundled countdown — intro fetch failed: \(error)")
            return nil
        }
    }

    private func animateCountdownNumber() {
        countdownScale = 0.5
        countdownOpacity = 0
        withAnimation(.easeOut(duration: 0.3)) {
            countdownScale = 1.0
            countdownOpacity = 1.0
        }
        withAnimation(.easeIn(duration: 0.2).delay(0.7)) {
            countdownOpacity = 0.3
        }
    }

    // MARK: - Countdown Overlay

    private var countdownOverlay: some View {
        ZStack {
            Color.stridePrimary.opacity(0.80)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                StrideLogoView(height: 35, color: .white)
                    .padding(.top, 30)

                Text("Crush It!")
                    .font(.inter(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.top, 16)

                Spacer()

                if introPhase == .numbers {
                    Text("\(countdownNumber)")
                        .font(.barlowCondensed(size: 280, weight: .medium))
                        .foregroundColor(.white)
                        .scaleEffect(countdownScale)
                        .opacity(countdownOpacity)
                        .transition(.opacity)
                } else {
                    // AI intro playing — pulsing dot trio as a "coach is talking" hint.
                    PulsingDots()
                        .frame(height: 40)
                        .transition(.opacity)
                }

                Spacer()

                Button {
                    countdownPaused.toggle()
                    if countdownPaused {
                        tts.stopSpeaking()
                    } else {
                        startCountdown()
                    }
                } label: {
                    Text(countdownPaused ? "Resume" : "Pause")
                        .font(.inter(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 201, height: 56)
                        .background(Color.black)
                        .clipShape(Capsule())
                }
                .padding(.bottom, 50)
            }
        }
    }

    // MARK: - Map Layer

    private var mapLayer: some View {
        Map(viewport: $viewport) {
            if viewModel.routeCoordinates.count >= 2 {
                PolylineAnnotationGroup {
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

            if let startCoord = viewModel.routeCoordinates.first,
               viewModel.routeCoordinates.count > 5 {
                MapViewAnnotation(coordinate: startCoord) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                }
                .allowOverlap(true)
            }
        }
        .mapStyle(MapStyle(uri: Self.styleURI))
        .ornamentOptions(OrnamentOptions(
            scaleBar: ScaleBarViewOptions(visibility: .hidden),
            compass: CompassViewOptions(position: .topRight, margins: CGPoint(x: 16, y: 40)),
            logo: LogoViewOptions(margins: CGPoint(x: -10000, y: -10000)),
            attributionButton: AttributionButtonOptions(margins: CGPoint(x: -10000, y: -10000))
        ))
        .ignoresSafeArea()
    }

    // MARK: - Active Run Overlay

    private var activeRunOverlay: some View {
        ZStack {
            // Top gradient: blur + white fade from very top
            VStack {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .white, location: 0),
                                    .init(color: .white, location: 0.5),
                                    .init(color: .clear, location: 1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    LinearGradient(
                        stops: [
                            .init(color: Color(.systemBackground), location: 0),
                            .init(color: Color(.systemBackground).opacity(0.5), location: 0.5),
                            .init(color: Color(.systemBackground).opacity(0), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .frame(height: 140)
                .ignoresSafeArea(edges: .top)
                .overlay(alignment: .top) {
                    StrideLogoView(height: 35, color: .stridePrimary)
                        .padding(.top, 55)
                }

                Spacer()
            }

            // Bottom stats pinned to bottom
            VStack {
                Spacer()

                VStack(spacing: 12) {
                    // Distance (large)
                    VStack(spacing: 2) {
                        Text(String(format: "%.2f", viewModel.distance))
                            .font(.barlowCondensed(size: 112, weight: .medium))
                            .foregroundColor(.primary)
                        Text("Distance (km)")
                            .font(.inter(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }

                    // Time + Avg Pace side by side
                    HStack(spacing: 0) {
                        VStack(spacing: 2) {
                            Text(formatTime(viewModel.elapsedTime))
                                .font(.barlowCondensed(size: 40, weight: .medium))
                                .foregroundColor(.primary)
                            Text("Time")
                                .font(.inter(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)

                        VStack(spacing: 2) {
                            Text(viewModel.currentPace)
                                .font(.barlowCondensed(size: 40, weight: .medium))
                                .foregroundColor(.primary)
                            Text("Avg Pace")
                                .font(.inter(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 24)

                    // Pause button
                    Button {
                        viewModel.pauseRun()
                    } label: {
                        Text("Pause Run")
                            .font(.inter(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 201, height: 56)
                            .background(Color.stridePrimary)
                            .clipShape(Capsule())
                    }
                    .padding(.bottom, 0)
                }
                .padding(.top, 20)
                .background(
                    ZStack {
                        // Blur layer
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .mask(
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0),
                                        .init(color: .white, location: 0.2),
                                        .init(color: .white, location: 1)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                        // White layer
                        LinearGradient(
                            stops: [
                                .init(color: Color(.systemBackground).opacity(0), location: 0),
                                .init(color: Color(.systemBackground).opacity(0.6), location: 0.12),
                                .init(color: Color(.systemBackground), location: 0.3),
                                .init(color: Color(.systemBackground), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .ignoresSafeArea(edges: .bottom)
                )
            }
        }
    }

    // MARK: - Paused Overlay

    private var pausedOverlay: some View {
        ZStack {
            // Red overlay
            Color.stridePrimary.opacity(0.80)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Logo
                StrideLogoView(height: 35, color: .white)
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

                    Button {
                        onFinishRun()
                    } label: {
                        Text("End Run")
                            .font(.inter(size: 16, weight: .semibold))
                            .foregroundColor(Color.stridePrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.white)
                            .clipShape(Capsule())
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

/// Three dots that pulse in sequence — shown while the AI coach is generating/speaking the intro.
private struct PulsingDots: View {
    @State private var phase: Double = 0

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .opacity(0.35 + 0.65 * max(0, sin(phase + Double(i) * 0.6)))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

#Preview {
    OutdoorRunView(viewModel: RunViewModel(), onStartRun: {}, onFinishRun: {})
}
