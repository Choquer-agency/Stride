import SwiftUI

struct FitnessStepView: View {
    @Binding var data: OnboardingData
    @State private var weeklyMileageText: String = ""
    @State private var longestRunText: String = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Title
                VStack(alignment: .leading, spacing: 8) {
                    Text("CURRENT FITNESS LEVEL")
                        .font(.barlowCondensed(size: 28, weight: .bold))
                    
                    Text("Help us understand where you're starting from")
                        .font(.inter(size: 14))
                        .foregroundStyle(.secondary)
                }
                
                VStack(spacing: 24) {
                    // Weekly Kilometres
                    FormField(label: "Current Weekly Kilometres", isRequired: true) {
                        HStack(spacing: 12) {
                            TextField("0", text: $weeklyMileageText)
                                .keyboardType(.numberPad)
                                .font(.inter(size: 15))
                                .padding()
                                .frame(width: 70)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .onChange(of: weeklyMileageText) { _, newValue in
                                    data.currentWeeklyMileage = Int(newValue) ?? 0
                                }
                            
                            Text("km/week")
                                .foregroundStyle(.secondary)
                                .font(.inter(size: 14))
                            
                            Spacer()
                        }
                    }
                    
                    // Longest Recent Run
                    FormField(label: "Longest Run (past 4 weeks)", isRequired: true) {
                        HStack(spacing: 12) {
                            TextField("0", text: $longestRunText)
                                .keyboardType(.numberPad)
                                .font(.inter(size: 15))
                                .padding()
                                .frame(width: 70)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .onChange(of: longestRunText) { _, newValue in
                                    data.longestRecentRun = Int(newValue) ?? 0
                                }
                            
                            Text("km")
                                .foregroundStyle(.secondary)
                                .font(.inter(size: 14))
                            
                            Spacer()
                        }
                    }
                    
                    // Fitness Level
                    FormField(label: "Fitness Level", isRequired: true) {
                        VStack(spacing: 12) {
                            ForEach(FitnessLevel.allCases) { level in
                                FitnessLevelOption(
                                    level: level,
                                    isSelected: data.fitnessLevel == level
                                ) {
                                    withAnimation(.spring(response: 0.3)) {
                                        data.fitnessLevel = level
                                    }
                                }
                            }
                        }
                    }
                    
                    // Recent Race Times (Optional)
                    FormField(label: "Recent Race Times", isRequired: false) {
                        TextEditor(text: $data.recentRaceTimes)
                            .font(.inter(size: 15))
                            .autocorrectionDisabled()
                            .frame(height: 80)
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                Group {
                                    if data.recentRaceTimes.isEmpty {
                                        Text("e.g., Half marathon: 1:45:00 (3 months ago)")
                                            .font(.inter(size: 14))
                                            .foregroundColor(.secondary)
                                            .padding(.leading, 12)
                                            .padding(.top, 16)
                                    }
                                },
                                alignment: .topLeading
                            )
                    }
                    
                    // Recent Runs (Optional)
                    FormField(label: "Recent Runs (Last 7-14 Days)", isRequired: false) {
                        TextEditor(text: $data.recentRuns)
                            .font(.inter(size: 15))
                            .autocorrectionDisabled()
                            .frame(height: 80)
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                Group {
                                    if data.recentRuns.isEmpty {
                                        Text("e.g., Monday: 10km easy, Wednesday: 8km tempo")
                                            .font(.inter(size: 14))
                                            .foregroundColor(.secondary)
                                            .padding(.leading, 12)
                                            .padding(.top, 16)
                                    }
                                },
                                alignment: .topLeading
                            )
                    }
                }
                
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            if data.currentWeeklyMileage > 0 {
                weeklyMileageText = "\(data.currentWeeklyMileage)"
            }
            if data.longestRecentRun > 0 {
                longestRunText = "\(data.longestRecentRun)"
            }
        }
    }
}

// MARK: - Fitness Level Option
struct FitnessLevelOption: View {
    let level: FitnessLevel
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.stridePrimary : Color.secondary.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Circle()
                            .fill(Color.stridePrimary)
                            .frame(width: 14, height: 14)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.displayName)
                        .font(.inter(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text(level.description)
                        .font(.inter(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? Color.stridePrimary : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    FitnessStepView(data: .constant(OnboardingData()))
}
