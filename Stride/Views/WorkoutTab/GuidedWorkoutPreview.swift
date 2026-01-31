import SwiftUI

/// Pre-workout overview showing all intervals before starting
struct GuidedWorkoutPreview: View {
    let workout: PlannedWorkout
    @ObservedObject var workoutManager: WorkoutManager
    @ObservedObject var bluetoothManager: BluetoothManager
    
    @State private var showingConnectionWarning = false
    
    var body: some View {
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
                
                // Total stats
                HStack(spacing: 24) {
                    statBadge(
                        icon: "ruler",
                        value: String(format: "%.1f km", workout.totalDistanceKm),
                        label: "Distance"
                    )
                    
                    if workout.estimatedDurationSeconds > 0 {
                        let minutes = Int(workout.estimatedDurationSeconds / 60)
                        statBadge(
                            icon: "clock",
                            value: "\(minutes) min",
                            label: "Duration"
                        )
                    }
                    
                    if let intervals = workout.intervals {
                        statBadge(
                            icon: "list.number",
                            value: "\(intervals.count)",
                            label: "Intervals"
                        )
                    }
                }
                .padding(.horizontal)
                
                // Intervals list
                if let intervals = workout.intervals {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Workout Structure")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(intervals.sorted(by: { $0.order < $1.order })) { interval in
                            intervalPreviewCard(interval)
                        }
                    }
                    .padding(.top)
                }
                
                // Connection warning (only for run workouts)
                if workout.type != .gym && bluetoothManager.connectedDevice == nil {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Connect your treadmill to start")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                
                // Start button
                Button(action: startWorkout) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start Workout")
                            .fontWeight(.bold)
                    }
                    .font(.title2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(workout.type == .gym || bluetoothManager.connectedDevice != nil ? Color.stridePrimary : Color.gray)
                    .foregroundColor(.strideBlack)
                    .cornerRadius(16)
                }
                .disabled(workout.type != .gym && bluetoothManager.connectedDevice == nil)
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .padding(.top)
        }
    }
    
    // MARK: - Interval Preview Card
    
    private func intervalPreviewCard(_ interval: PlannedWorkout.Interval) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Order badge
            Text("\(interval.order)")
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(colorForIntervalType(interval.type))
                .cornerRadius(8)
            
            // Details
            VStack(alignment: .leading, spacing: 6) {
                Text(interval.type.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(interval.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 16) {
                    if let distance = interval.distanceKm {
                        Label(String(format: "%.1f km", distance), systemImage: "ruler")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let pace = interval.targetPaceSecondsPerKm {
                        Label(pace.toPaceString(), systemImage: "speedometer")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let duration = interval.durationSeconds {
                        let minutes = Int(duration / 60)
                        let seconds = Int(duration) % 60
                        let timeString = seconds > 0 ? "\(minutes):\(String(format: "%02d", seconds))" : "\(minutes)m"
                        Label(timeString, systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    // MARK: - Stat Badge
    
    private func statBadge(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.stridePrimary)
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Actions
    
    private func startWorkout() {
        // Only check connection for run workouts
        if workout.type != .gym {
            guard bluetoothManager.connectedDevice != nil else {
                showingConnectionWarning = true
                return
            }
        }
        
        workoutManager.startGuidedWorkout(plannedWorkout: workout)
        
        // Start first interval
        if let intervals = workout.intervals, !intervals.isEmpty {
            workoutManager.startInterval(index: 0)
        }
    }
    
    // MARK: - Helpers
    
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
    
    private func colorForIntervalType(_ type: PlannedWorkout.Interval.IntervalType) -> Color {
        switch type {
        case .warmup: return .blue
        case .work: return .red
        case .recovery: return .green
        case .cooldown: return .cyan
        }
    }
}
