import SwiftUI

// MARK: - Beginner Level Step
/// Experience level with honest contextual descriptions, plus a "longest
/// continuous jog" question that anchors the plan's starting point.
struct BeginnerLevelStepView: View {
    @Binding var data: OnboardingData

    private struct LevelOption {
        let level: FitnessLevel
        let title: String
        let subtitle: String
    }

    private let levels: [LevelOption] = [
        LevelOption(
            level: .beginner,
            title: "Beginner",
            subtitle: "Just getting into it — running is new, or it's been a long time"
        ),
        LevelOption(
            level: .intermediate,
            title: "Intermediate",
            subtitle: "Runs once or twice a week; a 10K or half marathon feels like a big goal"
        ),
        LevelOption(
            level: .advanced,
            title: "Advanced",
            subtitle: "Runs most days; races often — multiple marathons a year territory"
        ),
    ]

    /// Longest-continuous-jog chips → seed the fitness numbers honestly.
    private struct JogOption {
        let label: String
        let longestKm: Int
        let weeklyKm: Int
    }

    private let jogOptions: [JogOption] = [
        JogOption(label: "Not yet", longestKm: 0, weeklyKm: 0),
        JogOption(label: "5–10 min", longestKm: 1, weeklyKm: 2),
        JogOption(label: "10–20 min", longestKm: 3, weeklyKm: 5),
        JogOption(label: "20–30 min", longestKm: 4, weeklyKm: 8),
        JogOption(label: "30+ min", longestKm: 6, weeklyKm: 12),
    ]

    @State private var selectedJogLabel: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Title
                VStack(alignment: .leading, spacing: 8) {
                    Text("WHERE ARE YOU STARTING FROM?")
                        .font(.barlowCondensed(size: 28, weight: .bold))

                    Text("Honest answers make better plans")
                        .font(.inter(size: 14))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 16) {
                    // Level cards
                    ForEach(levels, id: \.level) { option in
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                data.fitnessLevel = option.level
                            }
                        }) {
                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.title)
                                        .font(.inter(size: 16, weight: .semibold))
                                        .foregroundColor(data.fitnessLevel == option.level ? .white : .primary)

                                    Text(option.subtitle)
                                        .font(.inter(size: 12))
                                        .foregroundColor(data.fitnessLevel == option.level ? .white.opacity(0.85) : .secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer()

                                if data.fitnessLevel == option.level {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.white)
                                }
                            }
                            .padding()
                            .background(
                                data.fitnessLevel == option.level
                                    ? Color.stridePrimary
                                    : Color(.secondarySystemBackground)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    // Longest continuous jog
                    FormField(label: "Longest jog you could do right now, without stopping", isRequired: false) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                            ForEach(jogOptions, id: \.label) { option in
                                Button(action: {
                                    withAnimation(.spring(response: 0.3)) {
                                        selectedJogLabel = option.label
                                        data.longestRecentRun = option.longestKm
                                        data.currentWeeklyMileage = option.weeklyKm
                                    }
                                }) {
                                    Text(option.label)
                                        .font(.inter(size: 13, weight: .medium))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(
                                            selectedJogLabel == option.label
                                                ? Color.stridePrimary
                                                : Color(.secondarySystemBackground)
                                        )
                                        .foregroundColor(selectedJogLabel == option.label ? .white : .primary)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Injuries / limitations
                    FormField(label: "Anything the coach should know? (injuries, limitations)", isRequired: false) {
                        TextField("Optional", text: $data.previousInjuries, axis: .vertical)
                            .textFieldStyle(StrideTextFieldStyle())
                            .lineLimit(2...4)
                    }

                    // Inline coach nudge
                    InlineRecommendationCard(
                        recommendation: PlanRecommendationEngine.evaluate(data)
                    )
                }

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }
}

#Preview {
    BeginnerLevelStepView(data: .constant(MichellePreset.seededData()))
}
