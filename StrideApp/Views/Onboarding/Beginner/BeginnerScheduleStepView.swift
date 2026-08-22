import SwiftUI

// MARK: - Beginner Schedule Step
/// Shape the week: run days, Peloton rides, strength days, rest days.
/// The recommendation card reacts to every change.
struct BeginnerScheduleStepView: View {
    @Binding var data: OnboardingData
    @State private var showDatePicker = false

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
                    Text("SHAPE YOUR WEEK")
                        .font(.barlowCondensed(size: 28, weight: .bold))

                    Text("How do you want to mix runs, rides, and strength?")
                        .font(.inter(size: 14))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 24) {
                    // Start Date
                    FormField(label: "Start Date", isRequired: true) {
                        Button(action: {
                            showDatePicker = true
                        }) {
                            HStack {
                                Text(dateFormatter.string(from: data.startDate))
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

                    // Weekly mix
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Weekly Mix")
                                .font(.inter(size: 16, weight: .semibold))

                            Spacer()

                            Button(action: { autoSelectSchedule() }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles")
                                    Text("Auto")
                                }
                                .font(.inter(size: 12, weight: .medium))
                                .foregroundColor(.stridePrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.stridePrimary.opacity(0.15))
                                .clipShape(Capsule())
                            }
                        }

                        // Run days
                        sessionRow(
                            label: "Run Days",
                            icon: { AnyView(Image(systemName: "figure.run").foregroundColor(.stridePrimary)) }
                        ) {
                            Stepper("\(data.runningDaysPerWeek) days", value: $data.runningDaysPerWeek, in: 1...7)
                                .font(.inter(size: 14))
                                .fixedSize()
                        }

                        // Peloton rides — shows the Peloton logo
                        sessionRow(
                            label: "Peloton Rides",
                            icon: {
                                AnyView(
                                    Image("PelotonLogo")
                                        .renderingMode(.template)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 16, height: 20)
                                        .foregroundColor(.stridePrimary)
                                )
                            }
                        ) {
                            Stepper("\(data.crossTrainDaysPerWeek) days", value: $data.crossTrainDaysPerWeek, in: 0...5)
                                .font(.inter(size: 14))
                                .fixedSize()
                        }

                        // Strength days
                        sessionRow(
                            label: "Strength Days",
                            icon: { AnyView(Image(systemName: "dumbbell").foregroundColor(.stridePrimary)) }
                        ) {
                            Stepper("\(data.gymDaysPerWeek) days", value: $data.gymDaysPerWeek, in: 0...4)
                                .font(.inter(size: 14))
                                .fixedSize()
                        }
                    }

                    // Rest days
                    FormField(label: "Days You Can't Work Out", isRequired: false) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                            ForEach(DayOfWeek.allCases) { day in
                                DayToggle(
                                    day: day,
                                    isSelected: data.restDays.contains(day)
                                ) {
                                    withAnimation(.spring(response: 0.3)) {
                                        if data.restDays.contains(day) {
                                            data.restDays.remove(day)
                                        } else {
                                            data.restDays.insert(day)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Long session day
                    FormField(label: "Best Day for Your Longer Session", isRequired: true) {
                        Menu {
                            ForEach(DayOfWeek.allCases) { day in
                                Button(day.rawValue) {
                                    data.longRunDay = day
                                }
                            }
                        } label: {
                            HStack {
                                Text(data.longRunDay.rawValue)
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
                selection: $data.startDate,
                in: Date()...,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .tint(Color.stridePrimary)
            .labelsHidden()
            .padding()
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .onChange(of: data.startDate) { _, _ in
                showDatePicker = false
            }
        }
    }

    private func sessionRow<Content: View>(
        label: String,
        icon: () -> AnyView,
        @ViewBuilder control: () -> Content
    ) -> some View {
        HStack {
            icon()
                .frame(width: 24)

            Text(label)
                .font(.inter(size: 15))

            Spacer()

            control()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func autoSelectSchedule() {
        withAnimation(.spring(response: 0.3)) {
            if data.goalType == .habit {
                data.runningDaysPerWeek = 2
                data.crossTrainDaysPerWeek = 2
                data.gymDaysPerWeek = 2
            } else {
                data.runningDaysPerWeek = 3
                data.crossTrainDaysPerWeek = 2
                data.gymDaysPerWeek = 1
            }
        }
    }
}

#Preview {
    BeginnerScheduleStepView(data: .constant(MichellePreset.seededData()))
}
