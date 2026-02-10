import SwiftUI

struct ConflictResolutionView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Title
                VStack(alignment: .leading, spacing: 8) {
                    Text("TRAINING CONSIDERATIONS")
                        .font(.barlowCondensed(size: 28, weight: .bold))
                    
                    Text("We've identified some factors that may affect your training plan")
                        .font(.inter(size: 14))
                        .foregroundStyle(.secondary)
                }
                
                // Summary
                if let summary = viewModel.conflictAnalysis?.recommendationSummary {
                    Text(summary)
                        .font(.inter(size: 14))
                        .foregroundStyle(.secondary)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                
                // Goal Comparison
                if let original = viewModel.conflictAnalysis?.originalGoalTime,
                   let recommended = viewModel.conflictAnalysis?.recommendedGoalTime,
                   original != recommended {
                    GoalComparisonCard(original: original, recommended: recommended)
                }
                
                // Conflicts List
                if let conflicts = viewModel.conflictAnalysis?.conflicts {
                    VStack(spacing: 16) {
                        ForEach(conflicts) { conflict in
                            ConflictCard(conflict: conflict)
                        }
                    }
                }
                
                // Choice Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Choose Your Approach")
                        .font(.inter(size: 16, weight: .semibold))
                    
                    // Aggressive Mode
                    ModeSelectionButton(
                        icon: "flame.fill",
                        title: "Override - Train for My Goal",
                        description: "Build an aggressive plan that progressively works toward my original goal. I understand the challenge.",
                        isSelected: viewModel.selectedMode == .aggressive,
                        accentColor: .orange
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            viewModel.selectPlanMode(.aggressive)
                        }
                    }
                    
                    // Recommended Mode
                    ModeSelectionButton(
                        icon: "checkmark.shield.fill",
                        title: "Accept Recommendation",
                        description: "Use the adjusted goal for a more sustainable training approach. I can always exceed it on race day.",
                        isSelected: viewModel.selectedMode == .recommended,
                        accentColor: .green
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            viewModel.selectPlanMode(.recommended)
                        }
                    }
                }
                
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }
}

// MARK: - Goal Comparison Card
struct GoalComparisonCard: View {
    let original: String
    let recommended: String
    
    var body: some View {
        HStack(spacing: 0) {
            // Original Goal
            VStack(spacing: 8) {
                Text("Your Goal")
                    .font(.inter(size: 12))
                    .foregroundStyle(.secondary)
                
                Text(original)
                    .font(.barlowCondensed(size: 24, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(Color(.secondarySystemBackground))
            
            // Arrow
            ZStack {
                Circle()
                    .fill(Color.stridePrimary)
                    .frame(width: 36, height: 36)
                
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.strideBrandBlack)
            }
            .offset(x: 0)
            .zIndex(1)
            
            // Recommended Goal
            VStack(spacing: 8) {
                Text("Recommended")
                    .font(.inter(size: 12))
                    .foregroundStyle(.secondary)
                
                Text(recommended)
                    .font(.barlowCondensed(size: 24, weight: .bold))
                    .foregroundStyle(.green)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(Color.green.opacity(0.1))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.strideBorder, lineWidth: 1)
        )
    }
}

// MARK: - Conflict Card
struct ConflictCard: View {
    let conflict: DetectedConflict
    
    private var riskColor: Color {
        switch conflict.riskLevelEnum {
        case .high: return .red
        case .medium: return .orange
        case .low: return .yellow
        }
    }
    
    private var riskIcon: String {
        switch conflict.riskLevelEnum {
        case .high: return "xmark.circle.fill"
        case .medium: return "exclamationmark.triangle.fill"
        case .low: return "info.circle.fill"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: riskIcon)
                    .foregroundColor(riskColor)
                
                Text(conflict.title)
                    .font(.inter(size: 14, weight: .semibold))
                
                Spacer()
                
                Text(conflict.riskLevelEnum.displayName)
                    .font(.inter(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(riskColor.opacity(0.2))
                    .foregroundColor(riskColor)
                    .clipShape(Capsule())
            }
            
            // Description
            Text(conflict.description)
                .font(.inter(size: 12))
                .foregroundStyle(.secondary)
            
            // Recommendation
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                    .font(.caption)
                
                Text(conflict.recommendation)
                    .font(.inter(size: 12))
                    .foregroundStyle(.primary)
            }
            .padding(12)
            .background(Color.yellow.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(riskColor.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Mode Selection Button
struct ModeSelectionButton: View {
    let icon: String
    let title: String
    let description: String
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isSelected ? accentColor : accentColor.opacity(0.2))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(isSelected ? .white : accentColor)
                }
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.inter(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text(description)
                        .font(.inter(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? accentColor : Color.secondary.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 14, height: 14)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isSelected ? accentColor : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ConflictResolutionView(viewModel: {
        let vm = OnboardingViewModel()
        vm.hasConflicts = true
        vm.conflictAnalysis = ConflictAnalysisResponse(
            hasConflicts: true,
            conflicts: [
                DetectedConflict(
                    conflictType: "goal_vs_fitness",
                    riskLevel: "medium",
                    title: "Ambitious Goal Pace",
                    description: "Your goal pace is 15% faster than what your recent performances suggest.",
                    recommendation: "Consider adjusting your target to 3:45:00 for a more achievable goal."
                )
            ],
            originalGoalTime: "3:30:00",
            recommendedGoalTime: "3:45:00",
            recommendationSummary: "We've identified 1 consideration that may affect your training plan."
        )
        return vm
    }())
}
