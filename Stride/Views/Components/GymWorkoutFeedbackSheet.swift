import SwiftUI

/// Feedback sheet specifically for gym workouts
struct GymWorkoutFeedbackSheet: View {
    let workout: PlannedWorkout
    let storageManager: StorageManager
    @Environment(\.dismiss) private var dismiss
    @Binding var showReviewScreen: Bool
    @Binding var reviewFeedback: WorkoutFeedback?
    
    @State private var completionStatus: WorkoutCompletionStatus = .completedAsPlanned
    @State private var effortRating: Int = 5
    @State private var fatigueLevel: Int = 3
    @State private var painLevel: Int = 0
    @State private var selectedPainAreas: Set<InjuryArea> = []
    @State private var weightFeel: WeightFeel? = .justRight
    @State private var formBreakdown: Bool = false
    @State private var notes: String = ""
    @FocusState private var isNotesFocused: Bool
    
    // Effort descriptions
    private func effortDescription(for rating: Int) -> String {
        switch rating {
        case 1...3: return "Very easy"
        case 4...5: return "Comfortable"
        case 6...7: return "Challenging"
        case 8...9: return "Very hard"
        case 10: return "Max effort"
        default: return ""
        }
    }
    
    // Fatigue descriptions
    private let fatigueDescriptions: [Int: String] = [
        1: "Fresh & energized",
        2: "Slightly tired",
        3: "Moderate fatigue",
        4: "Very tired",
        5: "Exhausted"
    ]
    
    // Pain descriptions
    private func painDescription(for level: Int) -> String {
        if level == 0 { return "No pain" }
        if level <= 3 { return "Mild discomfort" }
        if level <= 6 { return "Manageable pain" }
        return "Concerning pain"
    }
    
    private func painColor(for level: Int) -> Color {
        if level == 0 { return .gray }
        if level <= 3 { return .yellow }
        if level <= 6 { return .orange }
        return .red
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Completion Status Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("How did it go?")
                            .font(.system(size: 20, weight: .semibold))
                        
                        VStack(spacing: 12) {
                            completionStatusButton(.completedAsPlanned)
                            completionStatusButton(.completedModified)
                            completionStatusButton(.stoppedEarly)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    
                    // Effort Rating Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("How hard did it feel?")
                            .font(.system(size: 20, weight: .semibold))
                        
                        // Selected rating display
                        HStack(spacing: 12) {
                            Text("\(effortRating)")
                                .font(.system(size: 48, weight: .medium))
                                .foregroundColor(.stridePrimary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(effortDescription(for: effortRating))
                                    .font(.system(size: 16, weight: .medium))
                                Text("Effort level (RPE)")
                                    .font(.system(size: 14, weight: .light))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.bottom, 8)
                        
                        // Slider
                        VStack(spacing: 12) {
                            Slider(value: Binding(
                                get: { Double(effortRating) },
                                set: { effortRating = Int($0.rounded()) }
                            ), in: 1...10, step: 1)
                            .tint(.stridePrimary)
                            
                            HStack {
                                Text("1")
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("10")
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    // Fatigue Level Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("How fatigued are you?")
                            .font(.system(size: 20, weight: .semibold))
                        
                        // Selected fatigue display
                        HStack(spacing: 12) {
                            Text("\(fatigueLevel)")
                                .font(.system(size: 48, weight: .medium))
                                .foregroundColor(.stridePrimary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(fatigueDescriptions[fatigueLevel] ?? "")
                                    .font(.system(size: 16, weight: .medium))
                                Text("Fatigue level")
                                    .font(.system(size: 14, weight: .light))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.bottom, 8)
                        
                        // Slider
                        VStack(spacing: 12) {
                            Slider(value: Binding(
                                get: { Double(fatigueLevel) },
                                set: { fatigueLevel = Int($0.rounded()) }
                            ), in: 1...5, step: 1)
                            .tint(.stridePrimary)
                            
                            HStack {
                                Text("1")
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("5")
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    // Pain Level Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Any pain or discomfort?")
                            .font(.system(size: 20, weight: .semibold))
                        
                        // Selected pain display
                        HStack(spacing: 12) {
                            Text("\(painLevel)")
                                .font(.system(size: 48, weight: .medium))
                                .foregroundColor(painColor(for: painLevel))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(painDescription(for: painLevel))
                                    .font(.system(size: 16, weight: .medium))
                                Text("Pain level")
                                    .font(.system(size: 14, weight: .light))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.bottom, 8)
                        
                        // Slider
                        VStack(spacing: 12) {
                            Slider(value: Binding(
                                get: { Double(painLevel) },
                                set: { painLevel = Int($0.rounded()) }
                            ), in: 0...10, step: 1)
                            .tint(painColor(for: painLevel))
                            
                            HStack {
                                Text("0")
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("10")
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Pain area selection (show if pain >= 4)
                        if painLevel >= 4 {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Where does it hurt?")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .padding(.top, 8)
                                
                                FlowLayout(spacing: 8) {
                                    ForEach(InjuryArea.allCases, id: \.self) { area in
                                        Button(action: {
                                            if selectedPainAreas.contains(area) {
                                                selectedPainAreas.remove(area)
                                            } else {
                                                selectedPainAreas.insert(area)
                                            }
                                        }) {
                                            Text(area.displayName)
                                                .font(.system(size: 14, weight: .medium))
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(selectedPainAreas.contains(area) ? Color.orange : Color(.systemGray5))
                                                .foregroundColor(selectedPainAreas.contains(area) ? .white : .primary)
                                                .cornerRadius(8)
                                        }
                                    }
                                }
                                
                                if painLevel >= 7 {
                                    HStack(spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.red)
                                        Text("Consider resting or consulting a healthcare provider")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.top, 8)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    // Gym-Specific Section
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Gym-specific feedback")
                            .font(.system(size: 20, weight: .semibold))
                        
                        // Weight Feel
                        VStack(alignment: .leading, spacing: 12) {
                            Text("How did the weights feel?")
                                .font(.system(size: 16, weight: .medium))
                            
                            HStack(spacing: 12) {
                                weightFeelButton(.tooLight)
                                weightFeelButton(.justRight)
                                weightFeelButton(.tooHeavy)
                            }
                        }
                        
                        // Form Breakdown
                        Toggle(isOn: $formBreakdown) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Did your form break down?")
                                    .font(.system(size: 16, weight: .medium))
                                Text("Technical failure during sets")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .tint(.stridePrimary)
                    }
                    .padding(20)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal, 24)
                    
                    // Coach Notes Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Anything you want your coach to know?")
                            .font(.system(size: 20, weight: .semibold))
                        
                        Text("Optional")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        
                        TextEditor(text: $notes)
                            .focused($isNotesFocused)
                            .font(.system(size: 16, weight: .regular))
                            .frame(minHeight: 120)
                            .padding(12)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, 24)
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        // Save Button
                        Button(action: {
                            saveWorkout()
                        }) {
                            Text("Save Workout")
                                .font(.system(size: 18, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .background(Color.stridePrimary)
                                .foregroundColor(.strideBlack)
                                .cornerRadius(100)
                        }
                        
                        // Skip Feedback Button
                        Button(action: {
                            skipFeedback()
                        }) {
                            Text("Skip feedback")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Log Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Completion Status Button
    
    private func completionStatusButton(_ status: WorkoutCompletionStatus) -> some View {
        Button(action: {
            completionStatus = status
        }) {
            HStack {
                Image(systemName: completionStatus == status ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(completionStatus == status ? Color.stridePrimary : .secondary)
                
                Text(status.displayName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding()
            .background(completionStatus == status ? Color.stridePrimary.opacity(0.1) : Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Weight Feel Button
    
    private func weightFeelButton(_ feel: WeightFeel) -> some View {
        Button(action: {
            weightFeel = feel
        }) {
            Text(feel.displayName)
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(weightFeel == feel ? Color.stridePrimary : Color(.systemGray5))
                .foregroundColor(weightFeel == feel ? .strideBlack : .primary)
                .cornerRadius(8)
        }
    }
    
    // MARK: - Actions
    
    private func saveWorkout() {
        // Create a proper workout session for gym workout with metadata
        var session = WorkoutSession(startTime: workout.date)
        session.endTime = Date()
        session.plannedWorkoutId = workout.id
        session.workoutTitle = workout.title
        
        // Save workout session to storage
        storageManager.saveWorkout(session)
        
        // Create WorkoutFeedback
        let feedback = WorkoutFeedback(
            workoutSessionId: session.id,
            plannedWorkoutId: workout.id,
            date: Date(),
            completionStatus: completionStatus,
            paceAdherence: nil, // Gym workouts don't have pace
            perceivedEffort: effortRating,
            fatigueLevel: fatigueLevel,
            painLevel: painLevel,
            painAreas: painLevel >= 4 && !selectedPainAreas.isEmpty ? Array(selectedPainAreas) : nil,
            weightFeel: weightFeel,
            formBreakdown: formBreakdown,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        
        // Save feedback
        do {
            try storageManager.saveWorkoutFeedback(feedback)
        } catch {
            print("❌ Error saving workout feedback: \(error)")
        }
        
        // Dismiss and show review screen
        reviewFeedback = feedback
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showReviewScreen = true
        }
    }
    
    private func skipFeedback() {
        // ✅ Fix: Create proper gym session with workout metadata (no longer creates empty session)
        var session = WorkoutSession(startTime: workout.date)
        session.endTime = Date()
        session.plannedWorkoutId = workout.id
        session.workoutTitle = workout.title
        
        storageManager.saveWorkout(session)
        print("✅ Saved gym workout session without feedback: \(session.id)")
        dismiss()
    }
}
