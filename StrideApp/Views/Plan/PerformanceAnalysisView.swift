import SwiftUI
import PostHog

struct PerformanceAnalysisView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PerformanceAnalysisViewModel

    let plan: TrainingPlan
    var onApplyRecommendation: ((String) -> Void)?

    @State private var elapsedSeconds: Int = 0
    @State private var timer: Timer?

    private let estimatedTotalSeconds: Int = 60

    init(plan: TrainingPlan, onApplyRecommendation: ((String) -> Void)? = nil) {
        self.plan = plan
        self.onApplyRecommendation = onApplyRecommendation
        _viewModel = StateObject(wrappedValue: PerformanceAnalysisViewModel(plan: plan))
    }

    private var estimatedProgress: Double {
        if viewModel.isComplete { return 1.0 }
        return min(Double(elapsedSeconds) / Double(estimatedTotalSeconds), 0.95)
    }

    private var timeRemainingText: String {
        if viewModel.isComplete { return "Complete!" }
        let remaining = max(estimatedTotalSeconds - elapsedSeconds, 5)
        if remaining >= 60 {
            let minutes = remaining / 60
            let seconds = remaining % 60
            return "~\(minutes)m \(seconds)s remaining"
        }
        return "~\(remaining)s remaining"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                }

                Spacer()

                StrideLogoView(height: 28)

                Spacer()

                // Invisible spacer for centering
                Color.clear.frame(width: 32, height: 32)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 20)

            // Title
            Text("PERFORMANCE ANALYSIS")
                .font(.barlowCondensed(size: 28, weight: .bold))
                .padding(.bottom, 4)

            Text("Analyzing your completed training data")
                .font(.inter(size: 14))
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)

            Divider()
                .padding(.horizontal, 20)

            // Plan info badge
            HStack(spacing: 8) {
                Image(systemName: "figure.run")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.stridePrimary)

                Text(plan.raceName ?? plan.displayDistance)
                    .font(.inter(size: 13, weight: .medium))

                if let goalTime = plan.goalTime {
                    Text("\u{00B7}")
                        .foregroundStyle(.secondary)
                    Text(goalTime)
                        .font(.barlowCondensed(size: 14, weight: .medium))
                }
            }
            .foregroundStyle(.primary.opacity(0.8))
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(Color(.tertiarySystemBackground))
            .clipShape(Capsule())
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Scrollable analysis content
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !viewModel.streamingContent.isEmpty {
                            Text(viewModel.streamingContent)
                                .font(.inter(size: 14))
                                .foregroundColor(.primary.opacity(0.85))
                                .lineSpacing(6)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .tint(.stridePrimary)
                                    .scaleEffect(0.8)
                                Text("Analyzing your training data...")
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
                    .padding(.top, 20)
                    .padding(.bottom, 140)
                }
                .onChange(of: viewModel.streamingContent) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }

            Spacer(minLength: 0)

            // Bottom area
            VStack(spacing: 12) {
                if viewModel.isComplete {
                    GeometryReader { geometry in
                        let buttonWidth = geometry.size.width * 191.0 / 402.0

                        HStack {
                            Spacer()
                            if let instruction = viewModel.suggestedEditInstruction {
                                Button {
                                    PostHogSDK.shared.capture("recommendation_applied")
                                    dismiss()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        onApplyRecommendation?(instruction)
                                    }
                                } label: {
                                    Text("Apply Recommendation")
                                        .font(.inter(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(width: buttonWidth + 40)
                                        .padding(.vertical, 18)
                                        .background(Color.stridePrimary)
                                        .clipShape(Capsule())
                                }
                            } else {
                                Button(action: { dismiss() }) {
                                    Text("Done")
                                        .font(.inter(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(width: buttonWidth)
                                        .padding(.vertical, 18)
                                        .background(Color(.tertiaryLabel))
                                        .clipShape(Capsule())
                                }
                            }
                            Spacer()
                        }
                    }
                    .frame(height: 56)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    // Progress bar
                    VStack(spacing: 8) {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color(.tertiarySystemBackground))
                                    .frame(height: 6)

                                Capsule()
                                    .fill(Color.stridePrimary)
                                    .frame(width: geometry.size.width * estimatedProgress, height: 6)
                                    .animation(.easeInOut(duration: 0.5), value: estimatedProgress)
                            }
                        }
                        .frame(height: 6)
                        .padding(.horizontal, 40)

                        Text(timeRemainingText)
                            .font(.inter(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.bottom, 40)
            .animation(.spring(response: 0.5), value: viewModel.isComplete)
        }
        .background(Color(.systemBackground))
        .onAppear {
            startTimer()
            Task {
                await viewModel.startAnalysis()
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { }
        } message: {
            Text(viewModel.error ?? "Something went wrong")
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak viewModel] _ in
            Task { @MainActor in
                if !(viewModel?.isComplete ?? true) {
                    self.elapsedSeconds += 1
                }
            }
        }
    }
}
