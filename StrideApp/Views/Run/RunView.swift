import SwiftUI

struct RunView: View {
    @ObservedObject var viewModel: RunViewModel
    var onFinishRun: () -> Void
    
    @State private var showFinishConfirmation = false
    @State private var splitDismissOffset: CGFloat = 0
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    // Container with 80% width, centered (10% padding on each side)
                    VStack(spacing: 0) {
                        // Header Row
                        headerRow
                            .padding(.top, 30)
                            .padding(.bottom, 24)

                        // Lane Guidance Pace Indicator
                        PaceLaneIndicator(
                            currentPace: viewModel.currentPace,
                            paceZone: viewModel.paceZone,
                            targetPaceMin: viewModel.targetPaceMinSec,
                            targetPaceMax: viewModel.targetPaceMaxSec,
                            isPlannedRun: viewModel.isPlannedRun
                        )
                        .padding(.bottom, 24)
                        
                        // Pace Graph
                        PaceGraphView(dataPoints: viewModel.paceGraphDataPoints)
                            .padding(.bottom, 24)
                        
                        // Metrics Row
                        metricsRow
                            .padding(.bottom, 32)
                        
                        // Kilometer Splits Table
                        kilometerSplitsTable
                            .padding(.bottom, 120) // Extra space for Pause/End buttons
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, UIScreen.main.bounds.width * 0.1)
                }
            }
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

            // Sticky Pause / End Run Buttons
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    // Pause Run (red)
                    Button {
                        // Visual placeholder — treadmill controls pacing
                    } label: {
                        Text("Pause Run")
                            .font(.inter(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 62)
                            .background(Color.stridePrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    
                    // End Run (black)
                    Button {
                        showFinishConfirmation = true
                    } label: {
                        Text("End Run")
                            .font(.inter(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 62)
                            .background(Color.strideBrandBlack)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 34) // Safe area spacing
            }
            .background(
                LinearGradient(
                    stops: [
                        .init(color: Color(.systemBackground).opacity(0), location: 0),
                        .init(color: Color(.systemBackground), location: 0.3)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .alert("End Run?", isPresented: $showFinishConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("End Run", role: .destructive) {
                onFinishRun()
            }
        } message: {
            Text("End your current run and review your results.")
        }
    }
    
    // MARK: - Header Row
    private var headerRow: some View {
        HStack {
            // Timer (Left)
            VStack(alignment: .center, spacing: 4) {
                if viewModel.isTimeBasedWorkout, let remaining = viewModel.remainingTimeSeconds {
                    Text(formatTime(remaining))
                        .font(.barlowCondensed(size: 32, weight: .medium))
                        .foregroundColor(.primary)
                } else {
                    Text(formatTime(viewModel.elapsedTime))
                        .font(.barlowCondensed(size: 32, weight: .medium))
                        .foregroundColor(.primary)
                }

                Text("Time")
                    .font(.inter(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Logo (Center)
            StrideLogoView(height: 32)

            Spacer()

            // Distance (Right)
            VStack(alignment: .center, spacing: 4) {
                // Target distance label (planned runs with distance only)
                if viewModel.isPlannedRun, let target = viewModel.targetDistanceKm {
                    Text("Target: \(formatTargetDistanceLabel(target))")
                        .font(.inter(size: 12, weight: .semibold))
                        .foregroundColor(.stridePrimary)
                }

                Text(String(format: "%.2f", viewModel.distance))
                    .font(.barlowCondensed(size: 32, weight: .medium))
                    .foregroundColor(.primary)

                Text("Distance (km)")
                    .font(.inter(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Metrics Row
    private var metricsRow: some View {
        HStack(spacing: 32) {
            // Pace Drift (Left)
            VStack(alignment: .center, spacing: 4) {
                Text("Pace Drift")
                    .font(.inter(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
                
                Text(viewModel.paceDrift)
                    .font(.barlowCondensed(size: 28, weight: .medium))
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            // Heart Rate / Zone (Right)
            VStack(alignment: .center, spacing: 4) {
                Text("Heart Rate / Zone")
                    .font(.inter(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
                
                Text(viewModel.heartRate > 0 ? "\(viewModel.heartRate)" : "--")
                    .font(.barlowCondensed(size: 28, weight: .medium))
                    .foregroundColor(.primary)
                
                Text(viewModel.heartRateZone.displayText)
                    .font(.inter(size: 12, weight: .medium))
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
                    .font(.inter(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .fixedSize()
                
                // Column 2: Fastest icon (more padding from KM column)
                Color.clear
                    .frame(width: 80)
                
                // Spacer to center Pace
                Spacer()
                
                // Column 3: Pace (centered)
                Text("Pace")
                    .font(.inter(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .fixedSize()

                // Column 4: Diff (no visible header)
                Color.clear
                    .frame(width: 50)

                // Spacer to push Time to far right
                Spacer()

                // Column 5: Time (right-aligned, far right)
                Text("Time")
                    .font(.inter(size: 12, weight: .medium))
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
struct KilometerSplit: Identifiable {
    let id = UUID()
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
