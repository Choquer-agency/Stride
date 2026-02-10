import SwiftUI

struct PlanGenerationView: View {
    let streamingContent: String
    let isComplete: Bool
    let onViewPlan: () -> Void
    var isEditMode: Bool = false

    @State private var elapsedSeconds: Int = 0
    @State private var timer: Timer?

    private var titleText: String {
        isEditMode ? "UPDATING YOUR TRAINING PLAN" : "PERSONALIZING YOUR TRAINING PLAN"
    }

    private var subtitleText: String {
        isEditMode ? "This usually takes 1–2 minutes" : "This usually takes 2–3 minutes"
    }

    private var loadingText: String {
        isEditMode ? "Applying your changes..." : "Generating your coaching overview..."
    }

    private var buttonText: String {
        isEditMode ? "View Updated Plan" : "View Plan"
    }

    private var estimatedTotalSeconds: Int {
        isEditMode ? 90 : 150
    }

    // Extract only the coaching overview portion (before week data starts)
    private var overviewContent: String {
        let content = streamingContent
        // Stop showing content when week plans begin
        let weekMarkers = ["Week 1", "WEEK 1", "## Week", "### Week", "Week 1:", "**Week 1"]
        for marker in weekMarkers {
            if let range = content.range(of: marker) {
                return String(content[content.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return content
    }
    
    private var estimatedProgress: Double {
        if isComplete { return 1.0 }
        return min(Double(elapsedSeconds) / Double(estimatedTotalSeconds), 0.95)
    }

    private var timeRemainingText: String {
        if isComplete { return "Complete!" }
        let remaining = max(estimatedTotalSeconds - elapsedSeconds, 10)
        if remaining >= 60 {
            let minutes = remaining / 60
            let seconds = remaining % 60
            return "~\(minutes)m \(seconds)s remaining"
        }
        return "~\(remaining)s remaining"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header - Stride Logo
            HStack {
                Spacer()
                StrideLogoView(height: 32)
                Spacer()
            }
            .padding(.top, 16)
            .padding(.bottom, 24)
            
            // Title
            Text(titleText)
                .font(.barlowCondensed(size: 24, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)

            // Time estimate
            Text(subtitleText)
                .font(.inter(size: 12))
                .foregroundColor(.secondary)
                .padding(.bottom, 20)
            
            // Divider
            Divider()
                .padding(.horizontal, 20)
            
            // Scrollable content area
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Section header
                        Text("Coaching Overview")
                            .font(.inter(size: 16, weight: .semibold))
                            .foregroundColor(.stridePrimary)
                            .padding(.top, 24)
                        
                        // Coaching overview content only
                        if !overviewContent.isEmpty {
                            Text(overviewContent)
                                .font(.inter(size: 14))
                                .foregroundColor(.primary.opacity(0.85))
                                .lineSpacing(6)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            // Placeholder while waiting for content
                            HStack(spacing: 8) {
                                ProgressView()
                                    .tint(.stridePrimary)
                                    .scaleEffect(0.8)
                                Text(loadingText)
                                    .font(.inter(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 8)
                        }
                        
                        // Invisible anchor for auto-scroll
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 140)
                }
                .onChange(of: overviewContent) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            
            Spacer(minLength: 0)
            
            // Bottom area: progress bar or View Plan button
            VStack(spacing: 12) {
                if isComplete {
                    // View Plan button
                    GeometryReader { geometry in
                        let buttonWidth = geometry.size.width * 191.0 / 402.0
                        
                        HStack {
                            Spacer()
                            Button(action: onViewPlan) {
                                Text(buttonText)
                                    .font(.inter(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: buttonWidth)
                                    .padding(.vertical, 18)
                                    .background(Color.stridePrimary)
                                    .clipShape(Capsule())
                            }
                            Spacer()
                        }
                    }
                    .frame(height: 56)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    // Progress bar
                    VStack(spacing: 8) {
                        // Progress bar
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // Track
                                Capsule()
                                    .fill(Color(.tertiarySystemBackground))
                                    .frame(height: 6)
                                
                                // Fill
                                Capsule()
                                    .fill(Color.stridePrimary)
                                    .frame(width: geometry.size.width * estimatedProgress, height: 6)
                                    .animation(.easeInOut(duration: 0.5), value: estimatedProgress)
                            }
                        }
                        .frame(height: 6)
                        .padding(.horizontal, 40)
                        
                        // Time remaining
                        Text(timeRemainingText)
                            .font(.inter(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.bottom, 40)
            .animation(.spring(response: 0.5), value: isComplete)
        }
        .background(Color(.systemBackground))
        .onAppear {
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if !isComplete {
                elapsedSeconds += 1
            }
        }
    }
}

#Preview("Loading") {
    PlanGenerationView(
        streamingContent: "Your strong endurance base and consistent training history set you up well for this marathon cycle. Based on your current weekly volume of 45km and longest run of 25km, we'll progressively build your aerobic capacity while introducing targeted speed work to hit your 3:30 goal.\n\nYour training plan is structured into three main phases: Base Building (weeks 1-4), Specific Preparation (weeks 5-8), and Race Sharpening (weeks 9-12). Each phase has a specific purpose designed around your fitness level and schedule constraints.",
        isComplete: false,
        onViewPlan: {}
    )
}

#Preview("Complete") {
    PlanGenerationView(
        streamingContent: "Your strong endurance base and consistent training history set you up well for this marathon cycle. Based on your current weekly volume of 45km and longest run of 25km, we'll progressively build your aerobic capacity while introducing targeted speed work to hit your 3:30 goal.",
        isComplete: true,
        onViewPlan: {}
    )
}
