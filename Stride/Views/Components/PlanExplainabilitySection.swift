import SwiftUI

/// Displays explainability context for how a training plan was generated
/// Provides transparency about generation method, fitness inputs, and pacing decisions
struct PlanExplainabilitySection: View {
    let context: PlanGenerationContext
    let goalName: String
    
    @State private var isExpanded: Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.blue)
                Text("How This Plan Was Built")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 20) {
                    // Generation Method
                    generationMethodSection
                    
                    Divider()
                    
                    // Fitness Inputs
                    fitnessInputsSection
                    
                    Divider()
                    
                    // Goal Influence
                    goalInfluenceSection
                    
                    Divider()
                    
                    // Confidence & Constraints
                    confidenceSection
                    
                    // AI Status (if relevant)
                    if context.llmStatus != .off {
                        Divider()
                        aiStatusSection
                    }
                    
                    // Last Updated
                    Divider()
                    timestampSection
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.08), Color.blue.opacity(0.03)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
    }
    
    // MARK: - Generation Method Section
    
    private var generationMethodSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "gear")
                    .foregroundColor(.blue)
                    .font(.caption)
                Text("Generation Method")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            
            Text(context.generationMethod.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    // MARK: - Fitness Inputs Section
    
    private var fitnessInputsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "figure.run.circle")
                    .foregroundColor(.green)
                    .font(.caption)
                Text("Fitness Inputs")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Baseline:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(context.baselineSource.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                if let vdot = context.baselineVDOT {
                    HStack {
                        Text("VDOT:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1f", vdot))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                
                if let age = context.baselineAgeInDays, age > 0 {
                    HStack {
                        Text("Baseline Age:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(age) days")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(age > 90 ? .orange : .primary)
                    }
                }
            }
            .padding(.leading, 4)
            
            Text(context.baselineSource.description(vdot: context.baselineVDOT, date: context.baselineDate))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }
    
    // MARK: - Goal Influence Section
    
    private var goalInfluenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "target")
                    .foregroundColor(.orange)
                    .font(.caption)
                Text("Goal Influence")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            
            Text(context.goalInfluence.description(goalName: goalName))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    // MARK: - Confidence Section
    
    private var confidenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: context.confidenceLevel.icon)
                    .foregroundColor(confidenceLevelColor)
                    .font(.caption)
                Text(context.confidenceLevel.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            
            Text(context.confidenceLevel.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            // Constraints applied
            if !context.constraintsApplied.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Conservative Adjustments:")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    ForEach(context.constraintsApplied, id: \.self) { constraint in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 4))
                                .foregroundColor(.orange)
                                .padding(.top, 5)
                            
                            Text(constraint)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.leading, 4)
            }
        }
    }
    
    // MARK: - AI Status Section
    
    private var aiStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                    .font(.caption)
                Text("AI Refinement")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            
            HStack {
                Text("Status:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(context.llmStatus.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(context.llmStatus == .enabled ? .purple : .secondary)
            }
            .padding(.leading, 4)
            
            Text(context.llmStatus.description(reason: nil))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }
    
    // MARK: - Timestamp Section
    
    private var timestampSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .foregroundColor(.gray)
                    .font(.caption)
                Text("Last Updated")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Generated:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatDate(context.generatedAt))
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                if let lastAdapted = context.lastAdaptedAt {
                    HStack {
                        Text("Last Adapted:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(formatDate(lastAdapted))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    
                    if let trigger = context.adaptationTrigger {
                        Text("Reason: \(trigger)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }
                }
            }
            .padding(.leading, 4)
        }
    }
    
    // MARK: - Helpers
    
    private var confidenceLevelColor: Color {
        switch context.confidenceLevel {
        case .high:
            return .green
        case .medium:
            return .blue
        case .low:
            return .orange
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            // High confidence with recent baseline
            PlanExplainabilitySection(
                context: PlanGenerationContext(
                    generationMethod: .hybrid,
                    baselineSource: .recentRace,
                    baselineVDOT: 42.5,
                    baselineDate: Calendar.current.date(byAdding: .day, value: -30, to: Date()),
                    goalInfluence: .pacesAligned,
                    confidenceLevel: .high,
                    constraintsApplied: [],
                    llmStatus: .enabled,
                    generatedAt: Date()
                ),
                goalName: "Half Marathon"
            )
            
            // Low confidence without baseline
            PlanExplainabilitySection(
                context: PlanGenerationContext(
                    generationMethod: .ruleBased,
                    baselineSource: .none,
                    baselineVDOT: nil,
                    baselineDate: nil,
                    goalInfluence: .pacesConstrained,
                    confidenceLevel: .low,
                    constraintsApplied: [
                        "Using conservative default paces due to missing baseline",
                        "Goal pace is 15% faster than current fitness suggests - building gradually"
                    ],
                    llmStatus: .off,
                    generatedAt: Date()
                ),
                goalName: "Marathon"
            )
        }
        .padding()
    }
}
