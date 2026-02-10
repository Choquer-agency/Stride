import SwiftUI

struct OnboardingProgressIndicator: View {
    let currentStep: Int
    let totalSteps: Int
    let showConflictStep: Bool
    
    // Pill dimensions matching WeekPillView style
    private let pillWidth: CGFloat = 36
    private let pillHeight: CGFloat = 48
    
    var body: some View {
        HStack(spacing: 16) {
            ForEach(1...4, id: \.self) { step in
                OnboardingStepPill(
                    step: step,
                    isSelected: step == currentStep || (currentStep == 5 && step == 4),
                    label: stepLabel(for: step)
                )
            }
        }
        .padding(.horizontal, 16)
    }
    
    private func stepLabel(for step: Int) -> String {
        switch step {
        case 1: return "Goal"
        case 2: return "Fitness"
        case 3: return "Schedule"
        case 4: return "History"
        default: return ""
        }
    }
}

// MARK: - Onboarding Step Pill
struct OnboardingStepPill: View {
    let step: Int
    let isSelected: Bool
    let label: String
    
    private let pillWidth: CGFloat = 36
    private let pillHeight: CGFloat = 48
    
    var body: some View {
        VStack(spacing: 6) {
            Text("\(step)")
                .font(.inter(size: 13, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .white : .secondary)
                .frame(width: pillWidth, height: pillHeight)
                .background(
                    RoundedRectangle(cornerRadius: pillWidth / 2, style: .continuous)
                        .fill(isSelected ? Color.stridePrimary : Color(.tertiarySystemBackground))
                )
            
            Text(label)
                .font(.inter(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .stridePrimary : .secondary)
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        OnboardingProgressIndicator(currentStep: 1, totalSteps: 5, showConflictStep: false)
        OnboardingProgressIndicator(currentStep: 2, totalSteps: 5, showConflictStep: false)
        OnboardingProgressIndicator(currentStep: 3, totalSteps: 5, showConflictStep: false)
        OnboardingProgressIndicator(currentStep: 4, totalSteps: 5, showConflictStep: false)
    }
    .padding()
    .background(Color(.systemBackground))
}
