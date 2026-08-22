import SwiftUI

// MARK: - Inline Recommendation Card
/// Coach nudge shown under onboarding answers in the beginner flow.
/// Driven by PlanRecommendationEngine — updates instantly as answers change.
struct InlineRecommendationCard: View {
    let recommendation: PlanRecommendation

    private var iconName: String {
        switch recommendation.severity {
        case .success: return "checkmark.circle.fill"
        case .info: return "lightbulb.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .blocking: return "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch recommendation.severity {
        case .success: return .green
        case .info: return .stridePrimary
        case .caution: return .orange
        case .blocking: return .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .foregroundColor(tint)

            Text(recommendation.message)
                .font(.inter(size: 12))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding()
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.spring(response: 0.3), value: recommendation)
    }
}
