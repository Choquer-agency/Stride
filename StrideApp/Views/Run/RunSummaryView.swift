import SwiftUI

struct RunSummaryView: View {
    let result: RunResult
    let score: Int?
    var onSave: (_ feedbackRating: Int?, _ notes: String) -> Void
    
    @State private var feedbackRating: Int? = nil
    @State private var feedbackNotes: String = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    // Logo
                    StrideLogoView(height: 32)
                        .padding(.top, 32)
                        .padding(.bottom, 8)
                    
                    // Title
                    Text("Run Complete")
                        .font(.inter(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(1)
                        .padding(.bottom, 24)
                    
                    // Score Ring (planned runs only)
                    if let score = score {
                        scoreRing(score: score)
                            .padding(.bottom, 28)
                    }
                    
                    // Primary Stats
                    primaryStats
                        .padding(.bottom, 28)
                    
                    // Planned vs Actual (planned runs only)
                    if result.isPlannedRun {
                        plannedVsActualCard
                            .padding(.bottom, 20)
                    }
                    
                    // Kilometer Splits
                    if !result.kmSplits.isEmpty {
                        splitsSection
                            .padding(.bottom, 20)
                    }
                    
                    // How Did It Feel?
                    feedbackSection
                        .padding(.bottom, 20)
                    
                    // Notes
                    notesSection
                        .padding(.bottom, 28)
                    
                    // Save Workout Button
                    Button {
                        onSave(feedbackRating, feedbackNotes)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Save Workout")
                                .font(.inter(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.stridePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.bottom, 60)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
            }
        }
        .background(Color(.systemBackground))
    }
    
    // MARK: - Score Ring
    
    private func scoreRing(score: Int) -> some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 10)
                .frame(width: 140, height: 140)
            
            // Progress arc
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100.0)
                .stroke(
                    scoreColor(score),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .frame(width: 140, height: 140)
                .rotationEffect(.degrees(-90))
            
            // Score text
            VStack(spacing: 2) {
                Text("\(score)")
                    .font(.barlowCondensed(size: 48, weight: .bold))
                    .foregroundColor(.primary)
                
                Text("Score")
                    .font(.inter(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 90...100: return .green
        case 75..<90: return .stridePrimary
        case 60..<75: return .orange
        default: return .red
        }
    }
    
    // MARK: - Primary Stats
    
    private var primaryStats: some View {
        HStack(spacing: 0) {
            // Distance
            VStack(spacing: 4) {
                Text(result.distanceDisplay)
                    .font(.barlowCondensed(size: 44, weight: .medium))
                    .foregroundColor(.primary)
                Text("km")
                    .font(.inter(size: 13, weight: .regular))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            
            // Divider
            Rectangle()
                .fill(Color(.systemGray4))
                .frame(width: 1, height: 50)
            
            // Time
            VStack(spacing: 4) {
                Text(result.durationDisplay)
                    .font(.barlowCondensed(size: 44, weight: .medium))
                    .foregroundColor(.primary)
                Text("Time")
                    .font(.inter(size: 13, weight: .regular))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            
            // Divider
            Rectangle()
                .fill(Color(.systemGray4))
                .frame(width: 1, height: 50)
            
            // Pace
            VStack(spacing: 4) {
                Text(result.avgPaceDisplay)
                    .font(.barlowCondensed(size: 44, weight: .medium))
                    .foregroundColor(.primary)
                Text("/km")
                    .font(.inter(size: 13, weight: .regular))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(Color(hex: "F9F9F9"))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    // MARK: - Planned vs Actual
    
    private var plannedVsActualCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.stridePrimary)
                Text("Plan Comparison")
                    .font(.inter(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
            }
            
            // Workout title
            if let title = result.plannedWorkoutTitle {
                Text(title)
                    .font(.inter(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            // Comparison rows
            VStack(spacing: 12) {
                if let targetDist = result.targetDistanceKm {
                    comparisonRow(
                        label: "Distance",
                        planned: formatDistance(targetDist),
                        actual: formatDistance(result.distanceKm),
                        isGood: result.distanceKm >= targetDist
                    )
                }
                
                if let targetPace = result.targetPaceDescription {
                    comparisonRow(
                        label: "Avg Pace",
                        planned: targetPace,
                        actual: result.avgPaceDisplay + " /km",
                        isGood: isPaceGood()
                    )
                }
                
                if let targetMins = result.targetDurationMinutes {
                    comparisonRow(
                        label: "Duration",
                        planned: formatDurationMinutes(targetMins),
                        actual: result.durationDisplay,
                        isGood: true
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(hex: "F9F9F9"))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    private func comparisonRow(label: String, planned: String, actual: String, isGood: Bool) -> some View {
        HStack {
            Text(label)
                .font(.inter(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
            
            Spacer()
            
            // Planned
            VStack(spacing: 2) {
                Text(planned)
                    .font(.barlowCondensed(size: 18, weight: .medium))
                    .foregroundColor(.secondary)
                Text("Planned")
                    .font(.inter(size: 10, weight: .regular))
                    .foregroundColor(Color(.tertiaryLabel))
            }
            .frame(width: 80)
            
            // Arrow
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            
            // Actual
            VStack(spacing: 2) {
                Text(actual)
                    .font(.barlowCondensed(size: 18, weight: .medium))
                    .foregroundColor(isGood ? .green : .orange)
                Text("Actual")
                    .font(.inter(size: 10, weight: .regular))
                    .foregroundColor(Color(.tertiaryLabel))
            }
            .frame(width: 80)
        }
    }
    
    // MARK: - Splits Section
    
    private var splitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kilometer Splits")
                .font(.inter(size: 15, weight: .semibold))
                .foregroundColor(.primary)
            
            // Header row
            HStack(spacing: 0) {
                Text("KM")
                    .font(.inter(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 30, alignment: .leading)
                
                Spacer()
                
                Text("Pace")
                    .font(.inter(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("Time")
                    .font(.inter(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 70, alignment: .trailing)
            }
            
            ForEach(result.kmSplits) { split in
                HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Text("\(split.kilometer)")
                            .font(.barlowCondensed(size: 18, weight: .medium))
                            .foregroundColor(.primary)
                        
                        if split.isFastest {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.stridePrimary)
                        }
                    }
                    .frame(width: 50, alignment: .leading)
                    
                    Spacer()
                    
                    Text("\(split.pace) /km")
                        .font(.barlowCondensed(size: 18, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text(formatSplitTime(split.time))
                        .font(.barlowCondensed(size: 18, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 70, alignment: .trailing)
                }
                .padding(.vertical, 6)
                
                if split.kilometer < result.kmSplits.count {
                    Rectangle()
                        .fill(Color.stridePrimary.opacity(0.2))
                        .frame(height: 1)
                }
            }
        }
        .padding(16)
        .background(Color(hex: "F9F9F9"))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    // MARK: - Feedback Section
    
    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How did it feel?")
                .font(.inter(size: 15, weight: .semibold))
                .foregroundColor(.primary)
            
            HStack(spacing: 0) {
                ForEach(0...5, id: \.self) { rating in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            feedbackRating = rating
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Text("\(rating)")
                                .font(.barlowCondensed(size: 24, weight: .medium))
                                .foregroundColor(feedbackRating == rating ? .white : .primary)
                            
                            Text(feedbackLabel(for: rating))
                                .font(.inter(size: 9, weight: .medium))
                                .foregroundColor(feedbackRating == rating ? .white.opacity(0.8) : .secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(feedbackRating == rating ? feedbackColor(for: rating) : Color.clear)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(4)
            .background(Color(hex: "F9F9F9"))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
    
    private func feedbackLabel(for rating: Int) -> String {
        switch rating {
        case 0: return "Terrible"
        case 1: return "Rough"
        case 2: return "Tough"
        case 3: return "Okay"
        case 4: return "Good"
        case 5: return "Amazing"
        default: return ""
        }
    }
    
    private func feedbackColor(for rating: Int) -> Color {
        switch rating {
        case 0: return .red
        case 1: return .orange
        case 2: return Color(red: 0.9, green: 0.6, blue: 0.1)
        case 3: return .yellow.opacity(0.8)
        case 4: return Color(red: 0.3, green: 0.7, blue: 0.3)
        case 5: return .green
        default: return .gray
        }
    }
    
    // MARK: - Notes Section
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes")
                .font(.inter(size: 15, weight: .semibold))
                .foregroundColor(.primary)
            
            TextField("Any notes about this run...", text: $feedbackNotes, axis: .vertical)
                .font(.inter(size: 14, weight: .regular))
                .lineLimit(3...6)
                .padding(14)
                .background(Color(hex: "F9F9F9"))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
    
    // MARK: - Helpers
    
    private func formatDistance(_ km: Double) -> String {
        if km == floor(km) {
            return "\(Int(km)) km"
        }
        return String(format: "%.1f km", km)
    }
    
    private func formatDurationMinutes(_ minutes: Int) -> String {
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            if m == 0 { return "\(h)h" }
            return "\(h)h \(m)m"
        }
        return "\(minutes) min"
    }
    
    private func formatSplitTime(_ timeString: String) -> String {
        let components = timeString.split(separator: ":").compactMap { Int($0) }
        if components.count == 3 {
            let hours = components[0]
            let minutes = components[1]
            let seconds = components[2]
            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, minutes, seconds)
            }
            return String(format: "%d:%02d", minutes, seconds)
        } else if components.count == 2 {
            return String(format: "%d:%02d", components[0], components[1])
        }
        return timeString
    }
    
    private func isPaceGood() -> Bool {
        guard let targetPace = RunScoringService.parsePaceToSeconds(result.targetPaceDescription) else {
            return true
        }
        // Within ±5 sec/km of target is good
        return abs(result.avgPaceSecPerKm - targetPace) <= 5.0
    }
}

#Preview {
    RunSummaryView(
        result: RunResult(
            distanceKm: 9.8,
            durationSeconds: 3120,
            avgPaceSecPerKm: 318.4,
            kmSplits: [
                KilometerSplit(kilometer: 1, pace: "5:22", time: "00:05:22", isFastest: false, diffFromFastest: 4),
                KilometerSplit(kilometer: 2, pace: "5:18", time: "00:10:40", isFastest: true, diffFromFastest: 0),
                KilometerSplit(kilometer: 3, pace: "5:25", time: "00:16:05", isFastest: false, diffFromFastest: 7)
            ],
            plannedWorkoutId: UUID(),
            plannedWorkoutTitle: "Easy 10K",
            plannedWorkoutType: .easyRun,
            targetDistanceKm: 10.0,
            targetPaceDescription: "5:30/km",
            targetDurationMinutes: 55,
            dataSource: "bluetooth_ftms",
            treadmillBrand: "Assault Runner"
        ),
        score: 85,
        onSave: { _, _ in }
    )
}
