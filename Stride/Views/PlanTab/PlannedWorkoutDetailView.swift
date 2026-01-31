import SwiftUI

/// Detailed view of a planned workout showing intervals and paces
struct PlannedWorkoutDetailView: View {
    let workout: PlannedWorkout
    @ObservedObject var planManager: TrainingPlanManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var showCompletionAlert = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header Card
                headerCard
                
                // Workout Summary
                if workout.isRunWorkout {
                    workoutSummaryCard
                }
                
                // Intervals Section
                if let intervals = workout.intervals, !intervals.isEmpty {
                    intervalsSection(intervals)
                }
                
                // Description
                if let description = workout.description {
                    descriptionCard(description)
                }
                
                // Action Buttons
                actionButtons
                
                Spacer(minLength: 20)
            }
            .padding()
        }
        .navigationTitle(workout.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Workout Complete!", isPresented: $showCompletionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Great job! This workout has been marked as complete.")
        }
    }
    
    // MARK: - Header Card
    
    private var headerCard: some View {
        VStack(spacing: 12) {
            // Icon and Type
            HStack {
                workout.type.brandIcon
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .foregroundColor(workout.type.brandColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.type.displayName)
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text(formatDate(workout.date))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if workout.completed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.green)
                }
            }
            
            Divider()
            
            // Quick Stats
            HStack(spacing: 20) {
                if let distance = workout.targetDistanceKm {
                    statItem(icon: "ruler", label: "Distance", value: String(format: "%.1f km", distance))
                }
                
                if workout.estimatedDurationSeconds > 0 {
                    let minutes = Int(workout.estimatedDurationSeconds / 60)
                    statItem(icon: "clock", label: "Duration", value: "~\(minutes) min")
                }
                
                if let pace = workout.targetPaceSecondsPerKm {
                    statItem(icon: "speedometer", label: "Pace", value: pace.toPaceString())
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func statItem(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(.green)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Workout Summary Card
    
    private var workoutSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workout Summary")
                .font(.headline)
            
            if workout.totalDistanceKm > 0 {
                summaryRow(icon: "figure.run", label: "Total Distance", value: String(format: "%.1f km", workout.totalDistanceKm))
            }
            
            if workout.estimatedDurationSeconds > 0 {
                let hours = Int(workout.estimatedDurationSeconds) / 3600
                let minutes = (Int(workout.estimatedDurationSeconds) % 3600) / 60
                let timeString = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
                summaryRow(icon: "timer", label: "Estimated Time", value: timeString)
            }
            
            if let intervals = workout.intervals {
                summaryRow(icon: "list.number", label: "Segments", value: "\(intervals.count)")
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func summaryRow(icon: String, label: String, value: String) -> some View {
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
    
    // MARK: - Intervals Section
    
    private func intervalsSection(_ intervals: [PlannedWorkout.Interval]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workout Structure")
                .font(.headline)
            
            ForEach(intervals.sorted(by: { $0.order < $1.order })) { interval in
                intervalCard(interval)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func intervalCard(_ interval: PlannedWorkout.Interval) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Order Number
            Text("\(interval.order)")
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(colorForIntervalType(interval.type))
                .cornerRadius(8)
            
            // Interval Details
            VStack(alignment: .leading, spacing: 4) {
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
                        Label("\(minutes)m", systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(color: Color.strideBlack.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Description Card
    
    private func descriptionCard(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Instructions")
                .font(.headline)
            
            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            if !workout.completed && workout.isRunWorkout {
                Button(action: startWorkout) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start Workout")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            }
            
            if workout.completed {
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
    
    private func startWorkout() {
        // This will be integrated with LiveWorkoutView later
        print("🏃 Starting workout: \(workout.title)")
        // For now, just dismiss
        dismiss()
    }
    
    // MARK: - Helpers
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: date)
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
    
    private func colorForIntervalType(_ type: PlannedWorkout.Interval.IntervalType) -> Color {
        switch type {
        case .warmup: return .blue
        case .work: return .red
        case .recovery: return .green
        case .cooldown: return .cyan
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PlannedWorkoutDetailView(
            workout: PlannedWorkout(
                date: Date(),
                type: .intervalWorkout,
                title: "Tuesday Speed Session",
                description: "Focus on form and consistent splits. Stay relaxed during recoveries.",
                targetDistanceKm: 10.0,
                targetPaceSecondsPerKm: 300,
                intervals: [
                    PlannedWorkout.Interval(order: 1, type: .warmup, distanceKm: 2.0, targetPaceSecondsPerKm: 360, description: "Easy warmup"),
                    PlannedWorkout.Interval(order: 2, type: .work, distanceKm: 0.8, targetPaceSecondsPerKm: 280, description: "800m repeat #1"),
                    PlannedWorkout.Interval(order: 3, type: .recovery, distanceKm: 0.4, targetPaceSecondsPerKm: 400, description: "400m recovery"),
                    PlannedWorkout.Interval(order: 4, type: .cooldown, distanceKm: 2.0, targetPaceSecondsPerKm: 360, description: "Easy cooldown")
                ]
            ),
            planManager: TrainingPlanManager(storageManager: StorageManager())
        )
    }
}
