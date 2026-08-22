import SwiftUI

// MARK: - Beginner Equipment Step
/// What's available for strength work + anything else the coach should honor.
/// Pre-seeded from the preset; chips toggle in and out of the equipment string.
struct BeginnerEquipmentStepView: View {
    @Binding var data: OnboardingData

    private struct EquipmentChip: Identifiable {
        var id: String { name }
        let name: String
        let icon: String
    }

    private let chips: [EquipmentChip] = [
        EquipmentChip(name: "Light dumbbells (5–10 lb)", icon: "dumbbell"),
        EquipmentChip(name: "Kettlebells", icon: "scalemass"),
        EquipmentChip(name: "Bodyweight only", icon: "figure.core.training"),
        EquipmentChip(name: "Resistance bands", icon: "circle.dotted"),
        EquipmentChip(name: "Yoga mat", icon: "rectangle.portrait"),
    ]

    @State private var selected: Set<String> = [
        "Light dumbbells (5–10 lb)", "Kettlebells", "Bodyweight only",
    ]
    @State private var notes: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Title
                VStack(alignment: .leading, spacing: 8) {
                    Text("YOUR EQUIPMENT")
                        .font(.barlowCondensed(size: 28, weight: .bold))

                    Text("Strength sessions only use what you pick here")
                        .font(.inter(size: 14))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 24) {
                    // Peloton callout
                    HStack(spacing: 16) {
                        Image("PelotonLogo")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 28)
                            .foregroundColor(.stridePrimary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Peloton Bike")
                                .font(.inter(size: 15, weight: .semibold))

                            Text("Ride days prescribe a class type and length — you pick the class in the Peloton app")
                                .font(.inter(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.stridePrimary)
                    }
                    .padding()
                    .background(Color.stridePrimary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    // Equipment chips
                    FormField(label: "Strength Equipment", isRequired: false) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(chips) { chip in
                                Button(action: {
                                    withAnimation(.spring(response: 0.3)) {
                                        if selected.contains(chip.name) {
                                            selected.remove(chip.name)
                                        } else {
                                            selected.insert(chip.name)
                                        }
                                        syncEquipment()
                                    }
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: chip.icon)
                                            .font(.system(size: 13))

                                        Text(chip.name)
                                            .font(.inter(size: 12, weight: .medium))
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)

                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        selected.contains(chip.name)
                                            ? Color.stridePrimary
                                            : Color(.secondarySystemBackground)
                                    )
                                    .foregroundColor(selected.contains(chip.name) ? .white : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Notes
                    FormField(label: "Anything else the coach should know?", isRequired: false) {
                        TextField(
                            "e.g. I like a short core class after rides",
                            text: $notes,
                            axis: .vertical
                        )
                        .textFieldStyle(StrideTextFieldStyle())
                        .lineLimit(3...6)
                        .onChange(of: notes) { _, newValue in
                            data.trainingNotes = newValue.isEmpty ? nil : newValue
                        }
                    }

                    // Summary of what the coach will honor
                    InlineRecommendationCard(
                        recommendation: PlanRecommendationEngine.evaluate(data)
                    )
                }

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .onAppear {
            notes = data.trainingNotes ?? ""
            syncEquipment()
        }
    }

    /// Rebuild the equipment string from the selected chips, always keeping
    /// the hard exclusions so the coach never prescribes heavy gear.
    private func syncEquipment() {
        let picked = chips.map(\.name).filter { selected.contains($0) }
        let inventory = picked.isEmpty ? "Bodyweight only" : picked.joined(separator: ", ")
        data.strengthEquipment =
            "\(inventory). Do NOT prescribe: barbell, squat rack, SkiErg, machines, plyometrics."
    }
}

#Preview {
    BeginnerEquipmentStepView(data: .constant(MichellePreset.seededData()))
}
