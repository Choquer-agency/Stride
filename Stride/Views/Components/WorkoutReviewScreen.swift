import SwiftUI

/// Shows workout feedback summary after logging
struct WorkoutReviewScreen: View {
    let feedback: WorkoutFeedback
    let session: WorkoutSession?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Completion Status Header
                    completionStatusCard
                    
                    // Pace Adherence (runs only)
                    if let paceAdherence = feedback.paceAdherence {
                        paceAdherenceCard(paceAdherence)
                    }
                    
                    // Metrics Card
                    metricsCard
                    
                    // Pain Areas (if any)
                    if let painAreas = feedback.painAreas, !painAreas.isEmpty {
                        painAreasCard(painAreas)
                    }
                    
                    // Coach Notes (if any)
                    if let notes = feedback.notes, !notes.isEmpty {
                        coachNotesCard(notes)
                    }
                    
                    // Confidence Message
                    confidenceMessageCard
                    
                    // Done Button
                    Button(action: {
                        dismiss()
                    }) {
                        Text("Done")
                            .font(.system(size: 18, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(Color.stridePrimary)
                            .foregroundColor(.strideBlack)
                            .cornerRadius(100)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
                .padding(.top, 24)
            }
            .navigationTitle("Workout Logged")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    // MARK: - Completion Status Card
    
    private var completionStatusCard: some View {
        VStack(spacing: 12) {
            Image(systemName: iconForCompletionStatus)
                .font(.system(size: 48))
                .foregroundColor(colorForCompletionStatus)
            
            Text(feedback.completionStatus.displayName)
                .font(.system(size: 24, weight: .semibold))
            
            if let session = session {
                HStack(spacing: 16) {
                    VStack {
                        Text(session.durationSeconds.toFullTimeString())
                            .font(.system(size: 20, weight: .medium))
                        Text("Time")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    
                    if session.totalDistanceKm > 0 {
                        VStack {
                            Text(String(format: "%.2f km", session.totalDistanceKm))
                                .font(.system(size: 20, weight: .medium))
                            Text("Distance")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal, 24)
    }
    
    // MARK: - Pace Adherence Card
    
    private func paceAdherenceCard(_ adherence: PaceAdherence) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "speedometer")
                    .foregroundColor(Color(adherence.color))
                Text("Pace Adherence")
                    .font(.system(size: 18, weight: .semibold))
            }
            
            HStack {
                Circle()
                    .fill(Color(adherence.color))
                    .frame(width: 12, height: 12)
                
                Text(adherence.displayName)
                    .font(.system(size: 16))
                    .foregroundColor(Color(adherence.color))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal, 24)
    }
    
    // MARK: - Metrics Card
    
    private var metricsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How it felt")
                .font(.system(size: 18, weight: .semibold))
            
            // Effort
            HStack(spacing: 12) {
                Image(systemName: "flame.fill")
                    .foregroundColor(.stridePrimary)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Effort")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Text("\(feedback.perceivedEffort)/10")
                        .font(.system(size: 16, weight: .medium))
                }
                
                Spacer()
                
                Text(effortLabel(for: feedback.perceivedEffort))
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Fatigue
            HStack(spacing: 12) {
                Image(systemName: "battery.25")
                    .foregroundColor(.stridePrimary)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fatigue")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Text("\(feedback.fatigueLevel)/5")
                        .font(.system(size: 16, weight: .medium))
                }
                
                Spacer()
                
                Text(fatigueLabel(for: feedback.fatigueLevel))
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Pain
            HStack(spacing: 12) {
                Image(systemName: feedback.painLevel > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundColor(Color(feedback.painSeverity.color))
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pain")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Text("\(feedback.painLevel)/10")
                        .font(.system(size: 16, weight: .medium))
                }
                
                Spacer()
                
                Text(feedback.painSeverity.displayName)
                    .font(.system(size: 14))
                    .foregroundColor(Color(feedback.painSeverity.color))
            }
            
            // Gym-specific
            if let weightFeel = feedback.weightFeel {
                Divider()
                
                HStack(spacing: 12) {
                    Image(systemName: "dumbbell.fill")
                        .foregroundColor(.stridePrimary)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Weights")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Text(weightFeel.displayName)
                            .font(.system(size: 16, weight: .medium))
                    }
                    
                    Spacer()
                }
            }
            
            if let formBreakdown = feedback.formBreakdown {
                Divider()
                
                HStack(spacing: 12) {
                    Image(systemName: formBreakdown ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundColor(formBreakdown ? .orange : .green)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Form")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Text(formBreakdown ? "Broke down" : "Held strong")
                            .font(.system(size: 16, weight: .medium))
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(20)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal, 24)
    }
    
    // MARK: - Pain Areas Card
    
    private func painAreasCard(_ areas: [InjuryArea]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "figure.walk")
                    .foregroundColor(.orange)
                Text("Pain Areas")
                    .font(.system(size: 18, weight: .semibold))
            }
            
            FlowLayout(spacing: 8) {
                ForEach(areas, id: \.self) { area in
                    Text(area.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(8)
                }
            }
            
            if feedback.painLevel >= 7 {
                Text("⚠️ Consider resting or seeing a healthcare provider if pain persists")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal, 24)
    }
    
    // MARK: - Coach Notes Card
    
    private func coachNotesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "message.fill")
                    .foregroundColor(.stridePrimary)
                Text("Your Notes")
                    .font(.system(size: 18, weight: .semibold))
            }
            
            Text(notes)
                .font(.system(size: 16))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal, 24)
    }
    
    // MARK: - Confidence Message Card
    
    private var confidenceMessageCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 24))
                .foregroundColor(.stridePrimary)
            
            Text("We'll use this to adjust next week's plan.")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.stridePrimary.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal, 24)
    }
    
    // MARK: - Helper Properties
    
    private var iconForCompletionStatus: String {
        switch feedback.completionStatus {
        case .completedAsPlanned: return "checkmark.circle.fill"
        case .completedModified: return "checkmark.circle"
        case .skipped: return "xmark.circle"
        case .stoppedEarly: return "pause.circle"
        }
    }
    
    private var colorForCompletionStatus: Color {
        switch feedback.completionStatus {
        case .completedAsPlanned: return .green
        case .completedModified: return .stridePrimary
        case .skipped: return .orange
        case .stoppedEarly: return .yellow
        }
    }
    
    private func effortLabel(for effort: Int) -> String {
        switch effort {
        case 1...3: return "Very easy"
        case 4...5: return "Comfortable"
        case 6...7: return "Challenging"
        case 8...9: return "Very hard"
        case 10: return "Max effort"
        default: return ""
        }
    }
    
    private func fatigueLabel(for fatigue: Int) -> String {
        switch fatigue {
        case 1: return "Fresh & energized"
        case 2: return "Slightly tired"
        case 3: return "Moderate fatigue"
        case 4: return "Very tired"
        case 5: return "Exhausted"
        default: return ""
        }
    }
}

// MARK: - Flow Layout for Pain Areas

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}
