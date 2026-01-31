import SwiftUI

/// Simplified view for gym/strength workouts - no exercise details
struct GymWorkoutDetailView: View {
    let workout: PlannedWorkout
    @ObservedObject var planManager: TrainingPlanManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header Card
                headerCard
                
                // Simple motivational message
                messageCard
                
                // Action Button
                actionButton
                
                Spacer(minLength: 20)
            }
            .padding()
        }
        .navigationTitle("Strength Training")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Header Card
    
    private var headerCard: some View {
        VStack(spacing: 16) {
            // Icon
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 60))
                .foregroundColor(.brown)
            
            // Date
            Text(formatDate(workout.date))
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if workout.completed {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Completed")
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
    
    // MARK: - Message Card
    
    private var messageCard: some View {
        VStack(spacing: 16) {
            Text("Strength Training Day")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Take time today to focus on building strength that supports your running. Choose exercises that work for you and your available equipment.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Divider()
                .padding(.vertical, 8)
            
            VStack(alignment: .leading, spacing: 12) {
                suggestionRow(icon: "figure.strengthtraining.traditional", text: "Focus on lower body and core")
                suggestionRow(icon: "clock", text: "30-45 minutes is plenty")
                suggestionRow(icon: "heart", text: "Listen to your body")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
    
    private func suggestionRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.brown)
                .frame(width: 28)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
    
    // MARK: - Action Button
    
    private var actionButton: some View {
        VStack(spacing: 12) {
            if !workout.completed {
                Button(action: markComplete) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Mark Complete")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Completed")
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Actions
    
    private func markComplete() {
        planManager.markWorkoutCompleted(workout.id)
        dismiss()
    }
    
    // MARK: - Helpers
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    let workout = PlannedWorkout(
        date: Date(),
        type: .gym,
        title: "Strength Training",
        description: nil
    )
    
    return NavigationStack {
        GymWorkoutDetailView(
            workout: workout,
            planManager: TrainingPlanManager(storageManager: StorageManager())
        )
    }
}
