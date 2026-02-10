import SwiftUI

struct WeekAccordionView: View {
    let week: Week
    let isExpanded: Bool
    let onToggle: () -> Void
    let onWorkoutTap: (Workout) -> Void
    let onWorkoutComplete: (Workout) -> Void
    
    // Group workouts by date
    private var workoutsByDay: [(date: Date, workouts: [Workout])] {
        let grouped = Dictionary(grouping: week.sortedWorkouts) { workout in
            Calendar.current.startOfDay(for: workout.date)
        }
        
        return grouped.keys.sorted().map { date in
            (date: date, workouts: grouped[date]!.sorted { $0.date < $1.date })
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Week Header
            WeekHeaderView(
                week: week,
                isExpanded: isExpanded,
                onToggle: onToggle
            )
            
            // Workouts (expanded content)
            if isExpanded {
                VStack(spacing: 1) {
                    ForEach(workoutsByDay, id: \.date) { dayData in
                        DayCardView(
                            date: dayData.date,
                            workouts: dayData.workouts,
                            onWorkoutTap: { workout in onWorkoutTap(workout) },
                            onWorkoutComplete: { workout in onWorkoutComplete(workout) }
                        )
                    }
                }
                .padding(.top, 1)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(hex: "F6F6F6"))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(week.isCurrentWeek ? Color.stridePrimary : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Week Header View
struct WeekHeaderView: View {
    let week: Week
    let isExpanded: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 16) {
                // Week Label (WEEK 1)
                Text("WEEK \(week.weekNumber)")
                    .font(.barlowCondensed(size: 16, weight: .medium))
                    .foregroundColor(.stridePrimary)
                    .frame(width: 70, alignment: .leading)
                
                // Date Range with Kilometers
                HStack(spacing: 8) {
                    Text(week.dateRange)
                        .font(.inter(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                    
                    // Total Distance (smaller, grey, next to date range)
                    if week.totalDistance > 0 {
                        Text(String(format: "%.0f km", week.totalDistance))
                            .font(.inter(size: 12, weight: .regular))
                            .foregroundStyle(Color.secondary.opacity(0.8))
                    }
                }
                
                Spacer()
                
                // Progress Ring
                ZStack {
                    Circle()
                        .stroke(Color.stridePrimary, lineWidth: 2)
                        .frame(width: 28, height: 28)
                    
                    Text("\(week.completedWorkouts)")
                        .font(.barlowCondensed(size: 12, weight: .medium))
                }
                
                // Chevron
                Image(systemName: isExpanded ? "chevron.up" : "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 16) {
        WeekAccordionView(
            week: {
                let week = Week(weekNumber: 1, theme: "Base Building")
                return week
            }(),
            isExpanded: true,
            onToggle: {},
            onWorkoutTap: { _ in },
            onWorkoutComplete: { _ in }
        )
        
        WeekAccordionView(
            week: {
                let week = Week(weekNumber: 2, theme: "Build Phase")
                return week
            }(),
            isExpanded: false,
            onToggle: {},
            onWorkoutTap: { _ in },
            onWorkoutComplete: { _ in }
        )
    }
    .padding()
    .background(Color(.systemBackground))
}
