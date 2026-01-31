import SwiftUI

/// Mode for goal setup view
enum GoalSetupMode {
    case create
    case edit(Goal)
}

/// Multi-step form for creating or editing a training goal
struct GoalSetupView: View {
    let mode: GoalSetupMode
    @ObservedObject var goalManager: GoalManager
    @Environment(\.dismiss) private var dismiss
    
    // Form state
    @State private var currentStep = 1
    @State private var goalType: Goal.GoalType = .race
    @State private var selectedDistance: Goal.RaceDistance = .halfMarathon
    @State private var customDistance: String = ""
    @State private var eventDate: Date = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var hours: Int = 0
    @State private var minutes: Int = 30
    @State private var seconds: Int = 0
    @State private var goalTitle: String = ""
    @State private var goalNotes: String = ""
    
    // UI state
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false
    
    private let totalSteps = 6
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress indicator
                progressBar
                
                // Step content
                ScrollView {
                    VStack(spacing: 24) {
                        stepContent
                            .padding()
                    }
                }
                
                // Navigation buttons
                navigationButtons
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
            .onAppear {
                loadExistingGoal()
            }
        }
    }
    
    // MARK: - Progress Bar
    
    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(height: 4)
                
                Rectangle()
                    .fill(Color.green)
                    .frame(width: geometry.size.width * (CGFloat(currentStep) / CGFloat(totalSteps)), height: 4)
                    .animation(.easeInOut, value: currentStep)
            }
        }
        .frame(height: 4)
    }
    
    // MARK: - Step Content
    
    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 1:
            step1_GoalType
        case 2:
            step2_Distance
        case 3:
            step3_EventDate
        case 4:
            step4_TargetTime
        case 5:
            step5_TitleAndNotes
        case 6:
            step6_Review
        default:
            EmptyView()
        }
    }
    
    // MARK: - Step 1: Goal Type
    
    private var step1_GoalType: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("What type of goal?")
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(spacing: 12) {
                goalTypeOption(.race, icon: "flag.fill", title: "Race Goal", description: "Train for a standard race distance")
                goalTypeOption(.customTime, icon: "target", title: "Custom Time Goal", description: "Set a custom distance and time goal")
                goalTypeOption(.completion, icon: "figure.walk.circle.fill", title: "Completion Goal", description: "Train to finish strong without a time goal")
            }
        }
    }
    
    private func goalTypeOption(_ type: Goal.GoalType, icon: String, title: String, description: String) -> some View {
        Button(action: {
            goalType = type
        }) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(goalType == type ? .white : .green)
                    .frame(width: 50, height: 50)
                    .background(goalType == type ? Color.green : Color.green.opacity(0.1))
                    .cornerRadius(12)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if goalType == type {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            .padding()
            .background(goalType == type ? Color.green.opacity(0.1) : Color(.systemGray6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(goalType == type ? Color.green : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Step 2: Distance
    
    private var step2_Distance: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(goalType == .race ? "Race distance" : (goalType == .completion ? "Target distance" : "Distance"))
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(spacing: 12) {
                ForEach([Goal.RaceDistance.fiveK, .tenK, .halfMarathon, .marathon, .custom], id: \.self) { distance in
                    distanceOption(distance)
                }
            }
            
            if selectedDistance == .custom {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom Distance (km)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField("Enter distance", text: $customDistance)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Text("Between 1 and 1000 km")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
            }
        }
    }
    
    private func distanceOption(_ distance: Goal.RaceDistance) -> some View {
        Button(action: {
            selectedDistance = distance
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(distance.rawValue)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if let km = distance.kilometers {
                        Text("\(String(format: "%.2f", km)) km")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if selectedDistance == distance {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            .padding()
            .background(selectedDistance == distance ? Color.green.opacity(0.1) : Color(.systemGray6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selectedDistance == distance ? Color.green : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Step 3: Event Date
    
    private var step3_EventDate: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Event date")
                .font(.title2)
                .fontWeight(.bold)
            
            DatePicker(
                "Select date",
                selection: $eventDate,
                in: Calendar.current.date(byAdding: .day, value: 1, to: Date())!...,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            // Show days/weeks until event
            if eventDate > Date() {
                let days = Calendar.current.dateComponents([.day], from: Date(), to: eventDate).day ?? 0
                let weeks = Calendar.current.dateComponents([.weekOfYear], from: Date(), to: eventDate).weekOfYear ?? 0
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.green)
                        Text("\(days) days (\(weeks) weeks) until event")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Step 4: Target Time
    
    private var step4_TargetTime: some View {
        VStack(alignment: .leading, spacing: 20) {
            if goalType == .completion {
                // Completion goals don't need time
                Text("No time goal needed")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("You're training to finish strong and healthy, not chasing a clock.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.green)
                        Text("Focus on completion")
                            .font(.headline)
                    }
                    
                    Text("We'll build your durability, consistency, and aerobic capacity to help you arrive strong and finish with confidence.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
                
            } else {
                // Time-based goals
                Text("Target time")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("What time are you aiming to finish in?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 16) {
                    timePickerColumn(value: $hours, range: 0...23, label: "Hours")
                    timePickerColumn(value: $minutes, range: 0...59, label: "Minutes")
                    timePickerColumn(value: $seconds, range: 0...59, label: "Seconds")
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Show pace
                if let distance = computedDistance, distance > 0 {
                    let totalSeconds = Double(hours * 3600 + minutes * 60 + seconds)
                    if totalSeconds > 0 {
                        let paceSecondsPerKm = totalSeconds / distance
                        let paceMinutes = Int(paceSecondsPerKm) / 60
                        let paceSeconds = Int(paceSecondsPerKm) % 60
                        
                        HStack {
                            Image(systemName: "speedometer")
                                .foregroundColor(.green)
                            Text("Average pace: \(paceMinutes):\(String(format: "%02d", paceSeconds)) per km")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
            }
        }
    }
    
    private func timePickerColumn(value: Binding<Int>, range: ClosedRange<Int>, label: String) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Picker(label, selection: value) {
                ForEach(range, id: \.self) { num in
                    Text(String(format: "%02d", num))
                        .tag(num)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 80, height: 120)
        }
    }
    
    // MARK: - Step 5: Title & Notes
    
    private var step5_TitleAndNotes: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Name your goal")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Optional, but makes it more personal")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Title")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                TextField("e.g., BMO Half Marathon", text: $goalTitle)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Notes")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                TextEditor(text: $goalNotes)
                    .frame(height: 100)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
                
                Text("e.g., Aim: sub 1:35, focus on negative splits")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Step 6: Review
    
    private var step6_Review: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Review your goal")
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(spacing: 16) {
                reviewRow(icon: "target", label: "Goal Type", value: goalType.displayName)
                reviewRow(icon: "ruler", label: "Distance", value: distanceText)
                reviewRow(icon: "calendar", label: "Event Date", value: formatDate(eventDate))
                
                // Only show target time for time-based goals
                if goalType != .completion {
                    reviewRow(icon: "clock", label: "Target Time", value: targetTimeText)
                } else {
                    reviewRow(icon: "heart.fill", label: "Focus", value: "Finish strong and healthy")
                }
                
                if !goalTitle.isEmpty {
                    reviewRow(icon: "text.quote", label: "Title", value: goalTitle)
                }
            }
            
            // Training plan preview
            if let distance = computedDistance {
                let goal = createGoalFromForm()
                let weeks = goal.defaultTrainingWeeks
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.green)
                        Text("Training Preview")
                            .font(.headline)
                    }
                    
                    Text("You have \(goal.weeksRemaining) weeks until \(goalType == .completion ? "event day" : "race day")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if goalType == .completion {
                        Text("Training will emphasize consistency, durability, and injury prevention")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Default plan will be 4 runs/week (adjustable later)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            }
            
            // Edit warning if editing
            if case .edit = mode {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Changing your goal will update your future training plan once planning is enabled.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }
    
    private func reviewRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .foregroundColor(.green)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Navigation Buttons
    
    private var navigationButtons: some View {
        HStack(spacing: 16) {
            if currentStep > 1 {
                Button(action: previousStep) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
                }
            }
            
            Button(action: nextStep) {
                HStack {
                    Text(currentStep == totalSteps ? "Save Goal" : "Continue")
                    if currentStep < totalSteps {
                        Image(systemName: "chevron.right")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(canProceed ? Color.green : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(!canProceed || isSaving)
            .opacity(isSaving ? 0.6 : 1.0)
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    // MARK: - Navigation Logic
    
    private func previousStep() {
        withAnimation {
            currentStep = max(1, currentStep - 1)
        }
    }
    
    private func nextStep() {
        withAnimation {
            if currentStep == totalSteps {
                saveGoal()
            } else {
                currentStep = min(totalSteps, currentStep + 1)
            }
        }
    }
    
    private var canProceed: Bool {
        switch currentStep {
        case 2:
            if selectedDistance == .custom {
                guard let distance = Double(customDistance), distance >= 1, distance <= 1000 else {
                    return false
                }
            }
            return true
        case 4:
            // Completion goals don't need a time, others do
            if goalType == .completion {
                return true
            }
            let totalSeconds = hours * 3600 + minutes * 60 + seconds
            return totalSeconds > 0
        default:
            return true
        }
    }
    
    // MARK: - Save Logic
    
    private func saveGoal() {
        isSaving = true
        
        let goal = createGoalFromForm()
        
        // Validate
        if let error = goal.validate() {
            errorMessage = error
            showError = true
            isSaving = false
            return
        }
        
        Task {
            do {
                switch mode {
                case .create:
                    try await goalManager.setGoal(goal)
                case .edit:
                    try await goalManager.updateGoal(goal)
                }
                
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isSaving = false
                }
            }
        }
    }
    
    private func createGoalFromForm() -> Goal {
        // Only set target time for time-based goals
        let targetTimeSeconds: TimeInterval? = {
            if goalType == .completion {
                return nil
            }
            return TimeInterval(hours * 3600 + minutes * 60 + seconds)
        }()
        
        var goal: Goal
        
        switch mode {
        case .create:
            goal = Goal(
                type: goalType,
                targetTime: targetTimeSeconds,
                eventDate: eventDate,
                title: goalTitle.isEmpty ? nil : goalTitle,
                notes: goalNotes.isEmpty ? nil : goalNotes,
                raceDistance: (goalType == .race || goalType == .completion) ? selectedDistance : nil,
                customDistanceKm: (goalType == .customTime || goalType == .completion || selectedDistance == .custom) ? Double(customDistance) : nil
            )
        case .edit(let existingGoal):
            goal = Goal(
                id: existingGoal.id,
                type: goalType,
                targetTime: targetTimeSeconds,
                eventDate: eventDate,
                createdAt: existingGoal.createdAt,
                isActive: existingGoal.isActive,
                title: goalTitle.isEmpty ? nil : goalTitle,
                notes: goalNotes.isEmpty ? nil : goalNotes,
                raceDistance: (goalType == .race || goalType == .completion) ? selectedDistance : nil,
                customDistanceKm: (goalType == .customTime || goalType == .completion || selectedDistance == .custom) ? Double(customDistance) : nil
            )
        }
        
        return goal
    }
    
    private func loadExistingGoal() {
        guard case .edit(let goal) = mode else { return }
        
        goalType = goal.type
        eventDate = goal.eventDate
        goalTitle = goal.title ?? ""
        goalNotes = goal.notes ?? ""
        
        if let distance = goal.raceDistance {
            selectedDistance = distance
            if distance == .custom, let km = goal.customDistanceKm {
                customDistance = String(format: "%.1f", km)
            }
        } else if let km = goal.customDistanceKm {
            selectedDistance = .custom
            customDistance = String(format: "%.1f", km)
        }
        
        // Only load target time if it exists (time-based goals)
        if let targetTime = goal.targetTime {
            let totalSeconds = Int(targetTime)
            hours = totalSeconds / 3600
            minutes = (totalSeconds % 3600) / 60
            seconds = totalSeconds % 60
        } else {
            hours = 0
            minutes = 0
            seconds = 0
        }
    }
    
    // MARK: - Helpers
    
    private var computedDistance: Double? {
        if goalType == .race || goalType == .completion {
            if selectedDistance == .custom {
                return Double(customDistance)
            }
            return selectedDistance.kilometers
        } else {
            return Double(customDistance)
        }
    }
    
    private var distanceText: String {
        if goalType == .race || goalType == .completion {
            if selectedDistance == .custom {
                return "\(customDistance) km"
            }
            return selectedDistance.rawValue
        } else {
            return "\(customDistance) km"
        }
    }
    
    private var targetTimeText: String {
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Mode Extension

extension GoalSetupMode {
    var title: String {
        switch self {
        case .create:
            return "Set Goal"
        case .edit:
            return "Edit Goal"
        }
    }
}

// MARK: - Preview

#Preview {
    GoalSetupView(
        mode: .create,
        goalManager: GoalManager(storageManager: StorageManager())
    )
}
