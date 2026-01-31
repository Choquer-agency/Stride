import SwiftUI

/// Bottom sheet for selecting alternative exercises
struct ExerciseAlternativeSheet: View {
    let assignment: ExerciseAssignment
    let workout: PlannedWorkout
    @ObservedObject var planManager: TrainingPlanManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var alternatives: [Exercise] = []
    @State private var selectedExercise: Exercise?
    
    private let library = ExerciseLibrary.shared
    private let selector = ExerciseSelector()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Current exercise header
                if let current = library.getExercise(slug: assignment.exerciseSlug) {
                    currentExerciseHeader(current)
                }
                
                Divider()
                
                // Alternatives list
                if alternatives.isEmpty {
                    emptyStateView
                } else {
                    alternativesList
                }
            }
            .navigationTitle("Find Alternative")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Replace") {
                        replaceExercise()
                    }
                    .disabled(selectedExercise == nil)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                loadAlternatives()
            }
        }
    }
    
    // MARK: - Current Exercise Header
    
    private func currentExerciseHeader(_ exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Exercise")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                Image(systemName: exercise.imageName)
                    .font(.system(size: 24))
                    .foregroundColor(.green)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name)
                        .font(.headline)
                    
                    Text("Equipment: " + exercise.requiredEquipment.map { $0.displayName }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }
    
    // MARK: - Alternatives List
    
    private var alternativesList: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Tap an alternative to select it")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top)
                
                ForEach(alternatives) { exercise in
                    alternativeCard(exercise)
                }
            }
            .padding()
        }
    }
    
    private func alternativeCard(_ exercise: Exercise) -> some View {
        Button(action: {
            selectedExercise = exercise
        }) {
            HStack(alignment: .top, spacing: 12) {
                // Selection indicator
                Image(systemName: selectedExercise?.id == exercise.id ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundColor(selectedExercise?.id == exercise.id ? .green : .secondary)
                
                // Exercise info
                VStack(alignment: .leading, spacing: 8) {
                    Text(exercise.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(exercise.whyItHelpsRunners)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    
                    // Equipment badge
                    HStack(spacing: 4) {
                        Image(systemName: "dumbbell")
                            .font(.caption)
                        Text(exercise.requiredEquipment.map { $0.displayName }.joined(separator: ", "))
                            .font(.caption)
                    }
                    .foregroundColor(.brown)
                }
                
                Spacer()
            }
            .padding()
            .background(
                selectedExercise?.id == exercise.id ?
                Color.green.opacity(0.1) :
                Color(.systemGray6)
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        selectedExercise?.id == exercise.id ? Color.green : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("No Alternatives Available")
                .font(.headline)
            
            Text("This exercise cannot be substituted with your current equipment.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Actions
    
    private func loadAlternatives() {
        // Load user's available equipment
        let userProfile = planManager.getUserProfile()
        
        // Find alternatives
        let foundAlternatives = selector.findBestAlternative(
            for: assignment.exerciseSlug,
            availableEquipment: userProfile.availableEquipment
        )
        
        if let alternative = foundAlternatives {
            alternatives = [alternative]
        }
        
        // Also add curated alternatives that match equipment
        let curated = library.findAlternatives(for: assignment.exerciseSlug)
            .filter { Set($0.requiredEquipment).isSubset(of: userProfile.availableEquipment) }
        
        alternatives.append(contentsOf: curated.filter { alt in
            !alternatives.contains(where: { $0.id == alt.id })
        })
    }
    
    private func replaceExercise() {
        guard let newExercise = selectedExercise else { return }
        
        // Create new assignment with selected exercise
        let newAssignment = ExerciseAssignment(
            id: assignment.id,
            exerciseSlug: newExercise.slug,
            order: assignment.order,
            sets: newExercise.defaultSets,
            reps: newExercise.defaultReps,
            durationSeconds: newExercise.defaultDurationSeconds,
            restSeconds: newExercise.defaultRestSeconds,
            loadType: newExercise.loadType,
            rpeTarget: assignment.rpeTarget
        )
        
        // Update workout's exercise program
        if var exerciseProgram = workout.exerciseProgram {
            if let index = exerciseProgram.firstIndex(where: { $0.id == assignment.id }) {
                exerciseProgram[index] = newAssignment
                
                // Create updated workout
                let updatedWorkout = PlannedWorkout(
                    id: workout.id,
                    date: workout.date,
                    type: workout.type,
                    title: workout.title,
                    description: workout.description,
                    completed: workout.completed,
                    actualWorkoutId: workout.actualWorkoutId,
                    targetDistanceKm: workout.targetDistanceKm,
                    targetDurationSeconds: workout.targetDurationSeconds,
                    targetPaceSecondsPerKm: workout.targetPaceSecondsPerKm,
                    intervals: workout.intervals,
                    exerciseProgram: exerciseProgram,
                    warmupBlock: workout.warmupBlock,
                    cooldownBlock: workout.cooldownBlock
                )
                
                // Update in plan manager
                planManager.updateWorkout(updatedWorkout)
            }
        }
        
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    let exercise = Exercise(
        slug: "bulgarian_split_squat",
        name: "Bulgarian Split Squat",
        category: .strength,
        primaryMuscles: [.quads, .glutes],
        runnerBenefit: .powerDevelopment,
        supportsGoals: [.general],
        defaultSets: 3,
        defaultReps: 8...12,
        defaultRestSeconds: 90,
        loadType: .fixedRecommendation,
        loadGuidance: "Moderate weight",
        whyItHelpsRunners: "Builds single-leg strength.",
        requiredEquipment: [.dumbbells],
        movementPattern: .lunge
    )
    
    let assignment = ExerciseAssignment(
        exerciseSlug: "bulgarian_split_squat",
        order: 1,
        sets: 3,
        reps: 8...12,
        restSeconds: 90
    )
    
    let workout = PlannedWorkout(
        date: Date(),
        type: .gym,
        title: "Strength Training",
        exerciseProgram: [assignment]
    )
    
    return ExerciseAlternativeSheet(
        assignment: assignment,
        workout: workout,
        planManager: TrainingPlanManager(storageManager: StorageManager())
    )
}
