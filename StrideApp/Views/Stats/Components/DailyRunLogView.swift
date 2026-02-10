import SwiftUI

struct DailyRunLogView: View {
    let workouts: [Workout]
    
    /// Completed running workouts, sorted most recent first
    private var completedRuns: [Workout] {
        workouts
            .filter { $0.isCompleted && $0.workoutType != .rest && $0.workoutType != .gym && $0.workoutType != .crossTraining }
            .sorted { $0.date > $1.date }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("Run Log")
                .font(.inter(size: 18, weight: .semibold))
            
            if completedRuns.isEmpty {
                Text("No runs logged yet")
                    .font(.inter(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(completedRuns.prefix(10)), id: \.id) { run in
                        RunLogRow(workout: run)
                        
                        if run.id != completedRuns.prefix(10).last?.id {
                            Divider()
                                .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(hex: "F9F9F9"))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Single Run Row
private struct RunLogRow: View {
    let workout: Workout
    
    private var paceText: String {
        // Prefer actual pace from treadmill data
        if let actualPace = workout.actualPaceDisplay {
            return actualPace
        }
        if let pace = workout.paceDescription {
            return pace
        }
        // Calculate pace from effective distance and duration
        if let km = workout.effectiveDistanceKm, let minutes = workout.effectiveDurationMinutes, km > 0 {
            let paceMinutes = Double(minutes) / km
            let mins = Int(paceMinutes)
            let secs = Int((paceMinutes - Double(mins)) * 60)
            return String(format: "%d:%02d /km", mins, secs)
        }
        return "—"
    }
    
    private var timeText: String {
        // Prefer actual duration
        if let actualSec = workout.actualDurationSeconds {
            let totalSec = Int(actualSec)
            let h = totalSec / 3600
            let m = (totalSec % 3600) / 60
            let s = totalSec % 60
            if h > 0 {
                return String(format: "%d:%02d:%02d", h, m, s)
            }
            return String(format: "%d:%02d", m, s)
        }
        return workout.durationDisplay ?? "—"
    }
    
    private var distanceText: String {
        if let km = workout.effectiveDistanceKm {
            if km == floor(km) {
                return "\(Int(km)) km"
            }
            return String(format: "%.1f km", km)
        }
        return "—"
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Date
            Text(workout.formattedDate)
                .font(.inter(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            
            Spacer()
            
            // Distance
            Text(distanceText)
                .font(.barlowCondensed(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 60, alignment: .trailing)
            
            Spacer()
            
            // Pace
            Text(paceText)
                .font(.barlowCondensed(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 80, alignment: .trailing)
            
            Spacer()
            
            // Time
            Text(timeText)
                .font(.barlowCondensed(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    DailyRunLogView(workouts: [])
        .padding()
}
