import SwiftUI

/// Main entry point for guided workouts
struct WorkoutGuideView: View {
    @ObservedObject var trainingPlanManager: TrainingPlanManager
    @ObservedObject var workoutManager: WorkoutManager
    @ObservedObject var bluetoothManager: BluetoothManager
    
    private var todaysWorkout: PlannedWorkout? {
        trainingPlanManager.todaysWorkout
    }
    
    private var isRestDay: Bool {
        todaysWorkout?.type == .rest
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if workoutManager.isRecording && workoutManager.plannedWorkout != nil {
                    // Active guided workout
                    ActiveGuidedWorkoutView(
                        workoutManager: workoutManager,
                        bluetoothManager: bluetoothManager
                    )
                } else if let workout = todaysWorkout, !isRestDay {
                    // Show workout preview
                    if let intervals = workout.intervals, !intervals.isEmpty {
                        // Structured workout with intervals
                        GuidedWorkoutPreview(
                            workout: workout,
                            workoutManager: workoutManager,
                            bluetoothManager: bluetoothManager
                        )
                    } else {
                        // Simple workout without intervals
                        simpleWorkoutView(workout)
                    }
                } else {
                    // Empty state (no workout or rest day)
                    WorkoutGuideEmptyState(
                        isRestDay: isRestDay,
                        onViewPlan: {
                            // Navigation handled by user tapping Plan tab
                        }
                    )
                }
            }
            .navigationTitle("Workout")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    // MARK: - Simple Workout View
    
    private func simpleWorkoutView(_ workout: PlannedWorkout) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    workout.type.brandIcon
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 60, height: 60)
                        .foregroundColor(workout.type.brandColor)
                    
                    Text(workout.title)
                        .font(.title)
                        .fontWeight(.bold)
                    
                    if let description = workout.description {
                        Text(description)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding()
                
                // Stats
                VStack(spacing: 16) {
                    if let distance = workout.targetDistanceKm {
                        statRow(icon: "ruler", label: "Distance", value: String(format: "%.1f km", distance))
                    }
                    
                    if let pace = workout.targetPaceSecondsPerKm {
                        statRow(icon: "speedometer", label: "Target Pace", value: pace.toPaceString())
                    }
                    
                    if workout.estimatedDurationSeconds > 0 {
                        let minutes = Int(workout.estimatedDurationSeconds / 60)
                        statRow(icon: "clock", label: "Est. Duration", value: "~\(minutes) min")
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(16)
                .padding(.horizontal)
                
                // Connection status (only for run workouts)
                if workout.type != .gym && bluetoothManager.connectedDevice == nil {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Connect your treadmill in Settings to start")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
                
                // Start button
                Button(action: {
                    workoutManager.startWorkout()
                }) {
                    Text("Start Workout")
                        .font(.title2)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(workout.type == .gym || bluetoothManager.connectedDevice != nil ? Color.green : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                }
                .disabled(workout.type != .gym && bluetoothManager.connectedDevice == nil)
                .padding(.horizontal)
                
                Spacer()
            }
            .padding(.top)
        }
    }
    
    private func statRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.green)
                .frame(width: 24)
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
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
