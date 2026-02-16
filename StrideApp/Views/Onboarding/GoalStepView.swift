import SwiftUI

struct GoalStepView: View {
    @Binding var data: OnboardingData
    @State private var showDatePicker = false
    @State private var customDistanceText: String = ""
    @State private var elevationGainText: String = ""

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
                    Text("WHAT'S YOUR GOAL?")
                        .font(.barlowCondensed(size: 28, weight: .bold))

                    Text("Tell us about the race you're training for — or the outcome you want to achieve.")
                        .font(.inter(size: 14))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 24) {
                    // Race Distance
                    FormField(label: "Race Distance", isRequired: true) {
                        Menu {
                            ForEach(RaceType.allCases) { raceType in
                                Button(raceType.displayName) {
                                    data.raceType = raceType
                                    if raceType != .custom {
                                        data.customDistanceKm = nil
                                        data.terrainType = nil
                                        data.elevationGainM = nil
                                        customDistanceText = ""
                                        elevationGainText = ""
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text(data.raceType.displayName)
                                    .font(.inter(size: 15))
                                    .foregroundColor(.primary)

                                Spacer()

                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.stridePrimary)
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }

                    // Custom Distance Field
                    if data.raceType == .custom {
                        FormField(label: "Distance (km)", isRequired: true) {
                            TextField("e.g. 80", text: $customDistanceText)
                                .font(.inter(size: 15))
                                .keyboardType(.decimalPad)
                                .textFieldStyle(StrideTextFieldStyle())
                                .onChange(of: customDistanceText) { _, newValue in
                                    data.customDistanceKm = Double(newValue)
                                }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Terrain Picker (ultra only)
                    if data.isUltraDistance {
                        FormField(label: "Terrain Type", isRequired: false) {
                            Menu {
                                ForEach(TerrainType.allCases) { terrain in
                                    Button(terrain.displayName) {
                                        data.terrainType = terrain
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(data.terrainType?.displayName ?? "Select terrain")
                                        .font(.inter(size: 15))
                                        .foregroundColor(data.terrainType == nil ? .secondary : .primary)

                                    Spacer()

                                    Image(systemName: "chevron.down")
                                        .font(.caption)
                                        .foregroundColor(.stridePrimary)
                                }
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))

                        // Elevation Gain
                        FormField(label: "Elevation Gain (meters)", isRequired: false) {
                            TextField("e.g. 3000", text: $elevationGainText)
                                .font(.inter(size: 15))
                                .keyboardType(.numberPad)
                                .textFieldStyle(StrideTextFieldStyle())
                                .onChange(of: elevationGainText) { _, newValue in
                                    data.elevationGainM = Int(newValue)
                                }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Race Date
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

                    // Race Name (Required)
                    FormField(label: "Race Name", isRequired: true) {
                        TextField("e.g. Boston Marathon", text: $data.raceName)
                            .font(.inter(size: 15))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.words)
                            .textFieldStyle(StrideTextFieldStyle())
                    }

                    // Goal Time (Required)
                    FormField(label: "Goal Time", isRequired: true) {
                        TextField("e.g. 3:30:00", text: $data.goalTime)
                            .font(.inter(size: 15))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .textFieldStyle(StrideTextFieldStyle())
                    }
                }

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .animation(.default, value: data.raceType)
            .animation(.default, value: data.isUltraDistance)
        }
        .scrollDismissesKeyboard(.interactively)
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
    }
}

// MARK: - Form Field Component
struct FormField<Content: View>: View {
    let label: String
    let isRequired: Bool
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.inter(size: 14, weight: .medium))
                
                if isRequired {
                    Text("*")
                        .foregroundColor(.stridePrimary)
                }
            }
            
            content
        }
    }
}

// MARK: - Stride Text Field Style
struct StrideTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    GoalStepView(data: .constant(OnboardingData()))
}
