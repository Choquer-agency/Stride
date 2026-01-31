import SwiftUI

/// Card showing today's planned workout
struct TodaysWorkoutCard: View {
    let workout: PlannedWorkout
    @ObservedObject var planManager: TrainingPlanManager
    @State private var showWorkoutDetail = false
    
    var body: some View {
        Button(action: { showWorkoutDetail = true }) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Today's Workout")
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(.secondary)
                        
                        Text(workout.title)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    if workout.completed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.stridePrimary)
                    } else {
                        workout.type.brandIcon
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 28, height: 28)
                            .foregroundColor(workout.type.brandColor)
                    }
                }
                
                // Stats Row
                if workout.isRunWorkout && !workout.completed {
                    HStack(spacing: 16) {
                        if let distance = workout.targetDistanceKm {
                            statBadge(icon: "ruler", value: String(format: "%.1f km", distance))
                        }
                        
                        if let pace = workout.targetPaceSecondsPerKm {
                            statBadge(icon: "speedometer", value: pace.toPaceString())
                        }
                        
                        if workout.estimatedDurationSeconds > 0 {
                            let minutes = Int(workout.estimatedDurationSeconds / 60)
                            statBadge(icon: "clock", value: "~\(minutes) min")
                        }
                    }
                }
                
                // Completion or Action
                if workout.completed {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.stridePrimary)
                        Text("Completed!")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.stridePrimary)
                    }
                    .padding(.vertical, 8)
                } else {
                    HStack {
                        Text("Tap for details")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(
                LinearGradient(
                    colors: workout.completed
                        ? [Color.stridePrimary.opacity(0.1), Color.stridePrimary.opacity(0.05)]
                        : [Color.blue.opacity(0.1), Color.blue.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(workout.completed ? Color.stridePrimary.opacity(0.3) : Color.blue.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showWorkoutDetail) {
            NavigationStack {
                PlannedWorkoutDetailView(workout: workout, planManager: planManager)
            }
        }
    }
    
    private func statBadge(icon: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
    
    private func colorForType(_ type: PlannedWorkout.WorkoutType) -> Color {
        switch type.color {
        case "green": return .green
        case "blue": return .blue
        case "orange": return .orange
        case "red": return .red
        case "purple": return .purple
        case "brown": return .brown
        case "gray": return .gray
        case "cyan": return .cyan
        default: return .green
        }
    }
}

// MARK: - Preview

#Preview {
    TodaysWorkoutCard(
        workout: PlannedWorkout(
            date: Date(),
            type: .tempoRun,
            title: "Tuesday Tempo",
            description: "Comfortably hard effort",
            targetDistanceKm: 10.0,
            targetPaceSecondsPerKm: 330
        ),
        planManager: TrainingPlanManager(storageManager: StorageManager())
    )
    .padding()
}
