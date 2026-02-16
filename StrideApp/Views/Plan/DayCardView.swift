import SwiftUI

struct DayCardView: View {
    let date: Date
    let workouts: [Workout]
    let onWorkoutTap: (Workout) -> Void
    let onWorkoutComplete: (Workout) -> Void
    
    @State private var isAnimatingCompletion: Bool = false
    @State private var checkmarkScale: CGFloat = 0
    @State private var checkmarkOpacity: Double = 0
    @State private var checkmarkPosition: CheckmarkPosition = .right
    @State private var checkmarkPulse: Bool = false
    @State private var previousCompletionState: Bool = false
    
    enum CheckmarkPosition {
        case center
        case right
    }
    
    private var isRestDay: Bool {
        workouts.count == 1 && workouts.first?.workoutType == .rest
    }
    
    private var allWorkoutsCompleted: Bool {
        workouts.allSatisfy { $0.isCompleted }
    }
    
    private var hasCompletedWorkout: Bool {
        workouts.contains { $0.isCompleted }
    }
    
    private var primaryWorkout: Workout? {
        workouts.first
    }
    
    private var isCompleting: Bool {
        isAnimatingCompletion && (primaryWorkout?.isCompleted ?? false)
    }
    
    private var dayOfMonth: String {
        String(Calendar.current.component(.day, from: date))
    }
    
    private var shortDayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
    
    private var shortMonthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: date)
    }
    
    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
    
    var body: some View {
        if isRestDay {
            // Rest day card - not tappable
            restDayCardContent
        } else if workouts.count == 1 {
            // Single workout card
            Button(action: { onWorkoutTap(workouts[0]) }) {
                singleWorkoutCardContent(workout: workouts[0])
            }
            .buttonStyle(CardPressButtonStyle(baseBackground: Color(hex: "F9F9F9")))
            .onAppear {
                previousCompletionState = workouts[0].isCompleted
            }
            .onChange(of: workouts[0].isCompleted) { oldValue, newValue in
                if newValue && !oldValue && !isAnimatingCompletion {
                    triggerCompletionAnimation()
                }
                previousCompletionState = newValue
            }
        } else {
            // Multiple workouts card - each row independently tappable
            multiWorkoutCardContent
                .onAppear {
                    previousCompletionState = allWorkoutsCompleted
                }
                .onChange(of: allWorkoutsCompleted) { oldValue, newValue in
                    if newValue && !oldValue && !isAnimatingCompletion {
                        triggerCompletionAnimation()
                    }
                    previousCompletionState = newValue
                }
        }
    }
    
    private func triggerCompletionAnimation() {
        // Reset animation states
        isAnimatingCompletion = true
        checkmarkScale = 0
        checkmarkOpacity = 0
        checkmarkPosition = .center
        checkmarkPulse = false
        
        // Phase 1: Red overlay appears, checkmark pulses in center (0.4s)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            checkmarkScale = 1.0
            checkmarkOpacity = 1.0
        }
        
        // Start pulse animation
        withAnimation(.easeInOut(duration: 0.3).repeatCount(2, autoreverses: true)) {
            checkmarkPulse = true
        }
        
        // Phase 2: Checkmark slides to right (0.6s delay, 0.3s duration) - 20% longer
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                checkmarkPosition = .right
                checkmarkPulse = false
            }
        }
        
        // Phase 3: Fade to completed state (0.9s delay, 0.4s duration)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.easeOut(duration: 0.4)) {
                isAnimatingCompletion = false
            }
        }
    }
    
    // MARK: - Rest Day Card
    private var restDayCardContent: some View {
        HStack(spacing: 12) {
            // Date Column
            dateColumn
            
            // Heart Icon
            ZStack {
                Circle()
                    .fill(Color(hex: "8A0063").opacity(0.15))
                    .frame(width: 36, height: 36)
                
                HeartIconView(size: 16)
            }
            
            // Rest Day Label
            Text("Rest Day")
                .font(.inter(size: 15, weight: .medium))
                .foregroundColor(.primary)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(hex: "FFF6F6"))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    // MARK: - Single Workout Card
    private func singleWorkoutCardContent(workout: Workout) -> some View {
        ZStack {
            // Card content
            HStack(spacing: 12) {
                // Date Column
                dateColumn
                    .opacity(workout.isCompleted && !isCompleting ? 0.5 : 1.0)

                // Workout Icon
                workoutIcon(for: workout)
                    .opacity(workout.isCompleted && !isCompleting ? 0.5 : 1.0)

                // Workout Details
                HStack(spacing: 8) {
                    Text(workout.title)
                        .font(.inter(size: 15, weight: .medium))
                        .foregroundColor(workout.isCompleted ? .secondary : .primary)

                    if let distance = workout.distanceDisplay {
                        Text(distance)
                            .font(.inter(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    if let pace = workout.paceDescription {
                        if workout.distanceDisplay != nil {
                            Text("•")
                                .font(.inter(size: 12))
                                .foregroundStyle(.secondary)
                        }

                        Text(pace)
                            .font(.inter(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }
                .opacity(workout.isCompleted && !isCompleting ? 0.5 : 1.0)

                Spacer()

                // Check icon or Chevron (right position)
                if workout.isCompleted && !isCompleting {
                    CheckmarkCircleView(isCompleted: true, size: 20)
                } else if !workout.isCompleted {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.stridePrimary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(workout.isCompleted && !isCompleting ? Color(hex: "F9F9F9").opacity(0.5) : Color(hex: "F9F9F9"))
            
            // Red overlay during animation
            if isCompleting {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.stridePrimary)
                    .transition(.opacity)
            }
            
            // Animated checkmark (center or right position)
            if workout.isCompleted && isCompleting {
                GeometryReader { geometry in
                    CheckmarkCircleView(isCompleted: true, size: 20)
                        .scaleEffect(checkmarkPulse ? 1.15 : checkmarkScale)
                        .opacity(checkmarkOpacity)
                        .frame(width: 20, height: 20)
                        .position(
                            x: checkmarkPosition == .center ? geometry.size.width / 2 : geometry.size.width - 28,
                            y: geometry.size.height / 2
                        )
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }
    
    
    // MARK: - Multi Workout Card
    private var multiWorkoutCardContent: some View {
        ZStack {
            // Card content
            HStack(alignment: .top, spacing: 12) {
                // Date Column (shared across all rows)
                dateColumn
                    .opacity(allWorkoutsCompleted && !isCompleting ? 0.5 : 1.0)
                    .padding(.top, 4)

                // Workouts Stack - each row is independently tappable
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(workouts.enumerated()), id: \.element.id) { index, workout in
                        Button(action: { onWorkoutTap(workout) }) {
                            HStack(spacing: 12) {
                                // Workout Icon
                                workoutIcon(for: workout)
                                    .opacity(workout.isCompleted && !isCompleting ? 0.5 : 1.0)

                                // Workout Details
                                HStack(spacing: 8) {
                                    Text(workout.title)
                                        .font(.inter(size: 15, weight: .medium))
                                        .foregroundColor(workout.isCompleted ? .secondary : .primary)

                                    if let distance = workout.distanceDisplay {
                                        Text(distance)
                                            .font(.inter(size: 12, weight: .regular))
                                            .foregroundStyle(.secondary)
                                    } else if let duration = workout.durationDisplay {
                                        Text(duration)
                                            .font(.inter(size: 12, weight: .regular))
                                            .foregroundStyle(.secondary)
                                    }

                                    if let pace = workout.paceDescription {
                                        if workout.distanceDisplay != nil || workout.durationDisplay != nil {
                                            Text("•")
                                                .font(.inter(size: 12))
                                                .foregroundStyle(.secondary)
                                        }

                                        Text(pace)
                                            .font(.inter(size: 12, weight: .regular))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .opacity(workout.isCompleted && !isCompleting ? 0.5 : 1.0)

                                Spacer()

                                // Per-row check icon or chevron
                                if workout.isCompleted && !isCompleting {
                                    CheckmarkCircleView(isCompleted: true, size: 20)
                                } else if !workout.isCompleted {
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(Color.stridePrimary)
                                }
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        
                        // Divider between rows (not after last)
                        if index < workouts.count - 1 {
                            Divider()
                                .padding(.leading, 48)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(allWorkoutsCompleted && !isCompleting ? Color(hex: "F9F9F9").opacity(0.5) : Color(hex: "F9F9F9"))
            
            // Red overlay during animation
            if isCompleting {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.stridePrimary)
                    .transition(.opacity)
            }
            
            // Animated checkmark (center or right position)
            if allWorkoutsCompleted && isCompleting {
                GeometryReader { geometry in
                    CheckmarkCircleView(isCompleted: true, size: 20)
                        .scaleEffect(checkmarkPulse ? 1.15 : checkmarkScale)
                        .opacity(checkmarkOpacity)
                        .frame(width: 20, height: 20)
                        .position(
                            x: checkmarkPosition == .center ? geometry.size.width / 2 : geometry.size.width - 28,
                            y: geometry.size.height / 2
                        )
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    
    // MARK: - Date Column
    private var dateColumn: some View {
        VStack(spacing: 0) {
            Text(shortDayName)
                .font(.inter(size: 10, weight: .semibold))
                .foregroundStyle(isToday ? Color.stridePrimary : .secondary)
            
            Text(dayOfMonth)
                .font(.barlowCondensed(size: 24, weight: isToday ? .bold : .medium))
                .foregroundStyle(isToday ? Color.stridePrimary : .primary)
            
            Text(shortMonthName)
                .font(.inter(size: 10, weight: .semibold))
                .foregroundStyle(isToday ? Color.stridePrimary : .secondary)
        }
        .frame(width: 40)
        .background(
            Group {
                if isToday {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.stridePrimary.opacity(0.1))
                        .padding(.horizontal, -4)
                        .padding(.vertical, -4)
                }
            }
        )
    }
    
    // MARK: - Workout Icon
    @ViewBuilder
    private func workoutIcon(for workout: Workout) -> some View {
        if workout.workoutType == .gym || workout.workoutType == .crossTraining {
            // Gym/CrossTraining uses Workout (kettlebell) icon
            ZStack {
                Circle()
                    .fill(Color(hex: "CF0000").opacity(0.15))
                    .frame(width: 36, height: 36)
                
                WorkoutIconView(size: 14)
            }
        } else {
            // Running workouts use the running icon
            ZStack {
                Circle()
                    .fill(workout.typeColor.opacity(0.2))
                    .frame(width: 36, height: 36)
                
                Image(systemName: workout.workoutType.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(workout.typeColor)
            }
        }
    }
    
    // MARK: - Card Background
    private func cardBackground(for workout: Workout) -> Color {
        return Color(hex: "F9F9F9")
    }
}

// MARK: - Card Press Button Style
struct CardPressButtonStyle: ButtonStyle {
    let baseBackground: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(configuration.isPressed ? Color(.systemGray6) : Color.clear)
            )
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    VStack(spacing: 8) {
        // Rest Day
        DayCardView(
            date: Date(),
            workouts: [
                Workout(
                    date: Date(),
                    workoutType: .rest,
                    title: "Rest Day"
                )
            ],
            onWorkoutTap: { _ in },
            onWorkoutComplete: { _ in }
        )
        
        // Single workout
        DayCardView(
            date: Date().addingTimeInterval(86400),
            workouts: [
                Workout(
                    date: Date().addingTimeInterval(86400),
                    workoutType: .easyRun,
                    title: "Easy Run",
                    distanceKm: 10,
                    paceDescription: "5:15/km"
                )
            ],
            onWorkoutTap: { _ in },
            onWorkoutComplete: { _ in }
        )
        
        // Two workouts
        DayCardView(
            date: Date().addingTimeInterval(86400 * 2),
            workouts: [
                Workout(
                    date: Date().addingTimeInterval(86400 * 2),
                    workoutType: .easyRun,
                    title: "Easy Run",
                    distanceKm: 10,
                    paceDescription: "5:15/km"
                ),
                Workout(
                    date: Date().addingTimeInterval(86400 * 2 + 3600),
                    workoutType: .gym,
                    title: "Workout",
                    durationMinutes: 30
                )
            ],
            onWorkoutTap: { _ in },
            onWorkoutComplete: { _ in }
        )
    }
    .padding()
    .background(Color(.secondarySystemBackground))
}
