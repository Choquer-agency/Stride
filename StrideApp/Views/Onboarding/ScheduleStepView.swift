import SwiftUI

struct ScheduleStepView: View {
    @Binding var data: OnboardingData
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var showDatePicker = false
    
    private var scheduleValidation: (isValid: Bool, message: String?) {
        viewModel.validateSchedule()
    }
    
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
                    Text("YOUR TRAINING SCHEDULE")
                        .font(.barlowCondensed(size: 28, weight: .bold))
                    
                    Text("Let us know your availability and preferences")
                        .font(.inter(size: 14))
                        .foregroundStyle(.secondary)
                }
                
                VStack(spacing: 24) {
                    // Start Date
                    FormField(label: "Training Start Date", isRequired: true) {
                        VStack(spacing: 0) {
                            Button(action: {
                                withAnimation(.spring(response: 0.3)) {
                                    showDatePicker.toggle()
                                }
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
                            
                            if showDatePicker {
                                DatePicker(
                                    "",
                                    selection: $data.startDate,
                                    in: Date()...,
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.graphical)
                                .tint(Color.stridePrimary)
                                .labelsHidden()
                                .padding(.top, 8)
                                .onChange(of: data.startDate) { _, _ in
                                    withAnimation(.spring(response: 0.3)) {
                                        showDatePicker = false
                                    }
                                }
                            }
                        }
                    }
                    
                    // Rest Days
                    FormField(label: "Preferred Rest Days", isRequired: false) {
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
                    
                    // Long Run Day
                    FormField(label: "Preferred Long Run Day", isRequired: true) {
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
                    
                    // Double Days Toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Allow Double Days")
                                .font(.inter(size: 15, weight: .medium))
                            
                            Text("Two workouts in one day")
                                .font(.inter(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $data.doubleDaysAllowed)
                            .tint(.stridePrimary)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    
                    // Training Volume Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Weekly Training Volume")
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
                        
                        // Running Days
                        HStack {
                            Text("Running Days")
                                .font(.inter(size: 15))
                            
                            Spacer()
                            
                            Stepper("\(data.runningDaysPerWeek) days", value: $data.runningDaysPerWeek, in: 3...7)
                                .font(.inter(size: 14))
                                .fixedSize()
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        
                        // Gym Days
                        HStack {
                            Text("Gym Sessions")
                                .font(.inter(size: 15))
                            
                            Spacer()
                            
                            Stepper("\(data.gymDaysPerWeek) days", value: $data.gymDaysPerWeek, in: 0...4)
                                .font(.inter(size: 14))
                                .fixedSize()
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    
                    // Validation Message
                    if !scheduleValidation.isValid, let message = scheduleValidation.message {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            
                            Text(message)
                                .font(.inter(size: 12))
                                .foregroundColor(.primary)
                        }
                        .padding()
                        .background(Color.orange.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }
    
    private func autoSelectSchedule() {
        let isUltra = data.raceType.isUltra
        let isMarathonDistance = [.halfMarathon, .marathon].contains(data.raceType)
        let isBeginner = data.fitnessLevel == .beginner
        let isAdvanced = data.fitnessLevel == .advanced
        
        withAnimation(.spring(response: 0.3)) {
            if isUltra {
                data.runningDaysPerWeek = isAdvanced ? 6 : 5
                data.gymDaysPerWeek = 2
            } else if isMarathonDistance {
                if isBeginner {
                    data.runningDaysPerWeek = 4
                    data.gymDaysPerWeek = 2
                } else if isAdvanced {
                    data.runningDaysPerWeek = 6
                    data.gymDaysPerWeek = 1
                } else {
                    data.runningDaysPerWeek = 5
                    data.gymDaysPerWeek = 2
                }
            } else {
                if isBeginner {
                    data.runningDaysPerWeek = 3
                    data.gymDaysPerWeek = 2
                } else if isAdvanced {
                    data.runningDaysPerWeek = 5
                    data.gymDaysPerWeek = 2
                } else {
                    data.runningDaysPerWeek = 4
                    data.gymDaysPerWeek = 2
                }
            }
        }
    }
}

// MARK: - Day Toggle
struct DayToggle: View {
    let day: DayOfWeek
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(day.initial)
                .font(.inter(size: 12, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(isSelected ? Color.stridePrimary : Color(.secondarySystemBackground))
                )
                .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ScheduleStepView(data: .constant(OnboardingData()), viewModel: OnboardingViewModel())
}
