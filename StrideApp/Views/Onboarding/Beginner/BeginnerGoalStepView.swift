import SwiftUI

// MARK: - Beginner Goal Step
/// "Training for something, or building the habit?" — habit block (with a
/// length picker) or a first race (5K/10K/Half + date, completion goal).
struct BeginnerGoalStepView: View {
    @Binding var data: OnboardingData
    @State private var showDatePicker = false

    private let blockOptions = [8, 10, 12]
    private let raceOptions: [RaceType] = [.fiveK, .tenK, .halfMarathon]

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .long
        return f
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Title
                VStack(alignment: .leading, spacing: 8) {
                    Text("WHAT ARE WE WORKING TOWARD?")
                        .font(.barlowCondensed(size: 28, weight: .bold))

                    Text("No wrong answer — a race is optional")
                        .font(.inter(size: 14))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 16) {
                    // Goal type cards
                    goalCard(
                        title: "Build the Habit",
                        subtitle: "No race — a steady block of runs, rides, and strength to make working out routine",
                        icon: "calendar.badge.checkmark",
                        isSelected: data.goalType == .habit
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            data.goalType = .habit
                        }
                    }

                    goalCard(
                        title: "Finish My First Race",
                        subtitle: "Pick an event and train to cross the line smiling — no time goal",
                        icon: "flag.checkered",
                        isSelected: data.goalType == .finish
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            data.goalType = .finish
                        }
                    }

                    if data.goalType == .habit {
                        // Block length
                        FormField(label: "Block Length", isRequired: true) {
                            HStack(spacing: 12) {
                                ForEach(blockOptions, id: \.self) { weeks in
                                    Button(action: {
                                        withAnimation(.spring(response: 0.3)) {
                                            data.blockWeeks = weeks
                                        }
                                    }) {
                                        Text("\(weeks) weeks")
                                            .font(.inter(size: 14, weight: .medium))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                            .background(
                                                data.blockWeeks == weeks
                                                    ? Color.stridePrimary
                                                    : Color(.secondarySystemBackground)
                                            )
                                            .foregroundColor(data.blockWeeks == weeks ? .white : .primary)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    } else {
                        // Race distance
                        FormField(label: "Race Distance", isRequired: true) {
                            HStack(spacing: 12) {
                                ForEach(raceOptions) { race in
                                    Button(action: {
                                        withAnimation(.spring(response: 0.3)) {
                                            data.raceType = race
                                        }
                                    }) {
                                        Text(race.shortName)
                                            .font(.inter(size: 14, weight: .medium))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                            .background(
                                                data.raceType == race
                                                    ? Color.stridePrimary
                                                    : Color(.secondarySystemBackground)
                                            )
                                            .foregroundColor(data.raceType == race ? .white : .primary)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Race date
                        FormField(label: "Race Date", isRequired: true) {
                            Button(action: {
                                showDatePicker = true
                            }) {
                                HStack {
                                    Text(dateFormatter.string(from: data.raceDate))
                                        .font(.inter(size: 15))
                                        .foregroundColor(.primary)

                                    Spacer()

                                    Image(systemName: "calendar")
                                        .font(.caption)
                                        .foregroundColor(.stridePrimary)
                                }
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }

                        // Race name
                        FormField(label: "Race Name", isRequired: true) {
                            TextField("e.g. Vancouver 5K", text: $data.raceName)
                                .textFieldStyle(StrideTextFieldStyle())
                        }
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
        .sheet(isPresented: $showDatePicker) {
            DatePicker(
                "",
                selection: $data.raceDate,
                in: Date()...,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .tint(Color.stridePrimary)
            .labelsHidden()
            .padding()
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .onChange(of: data.raceDate) { _, _ in
                showDatePicker = false
            }
        }
        .onAppear {
            // A finish goal has no time target — keep goalTime clear.
            data.goalTime = ""
        }
    }

    private func goalCard(
        title: String,
        subtitle: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? .white : .stridePrimary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.white.opacity(0.2) : Color.stridePrimary.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.inter(size: 16, weight: .semibold))
                        .foregroundColor(isSelected ? .white : .primary)

                    Text(subtitle)
                        .font(.inter(size: 12))
                        .foregroundColor(isSelected ? .white.opacity(0.85) : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer()
            }
            .padding()
            .background(isSelected ? Color.stridePrimary : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    BeginnerGoalStepView(data: .constant(MichellePreset.seededData()))
}
