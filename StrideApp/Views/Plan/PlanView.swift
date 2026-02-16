import SwiftUI
import SwiftData
import PostHog

struct PlanView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedWeekNumber: Int
    @State private var selectedWorkout: Workout?
    @State private var lastHapticWeek: Int = 0
    @State private var showDeleteConfirmation = false
    @State private var showEditSheet = false
    @State private var showAnalysisSheet = false
    @State private var prefillEditInstruction: String?

    let plan: TrainingPlan
    let readOnly: Bool

    // MARK: - Init (compute starting week immediately to avoid week-1 flash)
    init(plan: TrainingPlan, readOnly: Bool = false) {
        self.plan = plan
        self.readOnly = readOnly
        
        // Determine the correct starting week: current week > last week (if plan past) > first week
        let initialWeek: Int
        if let currentWeek = plan.currentWeek {
            initialWeek = currentWeek.weekNumber
        } else if plan.startDate < Date(), let lastWeek = plan.sortedWeeks.last {
            // Plan has started but today isn't in any week — show last week (plan is finished)
            initialWeek = lastWeek.weekNumber
        } else if let firstWeek = plan.sortedWeeks.first {
            // Plan hasn't started yet — show first week
            initialWeek = firstWeek.weekNumber
        } else {
            initialWeek = 1
        }
        
        _selectedWeekNumber = State(initialValue: initialWeek)
    }
    
    // MARK: - Computed Properties
    private var completedWorkoutsCount: Int {
        plan.completedWorkouts
    }
    
    private var selectedWeek: Week? {
        plan.sortedWeeks.first { $0.weekNumber == selectedWeekNumber }
    }
    
    private var totalWeeks: Int {
        plan.sortedWeeks.count
    }
    
    /// Whether all active (non-rest) workouts in the selected week are completed
    private var allWorkoutsCompleted: Bool {
        guard let week = selectedWeek else { return false }
        let active = week.workouts.filter { $0.workoutType != .rest }
        guard !active.isEmpty else { return false }
        return active.allSatisfy { $0.isCompleted }
    }
    
    /// Whether there is a next week to navigate to
    private var hasNextWeek: Bool {
        selectedWeekNumber < totalWeeks
    }
    
    // Group workouts by date for the selected week (to handle multiple workouts per day)
    private var workoutsByDay: [(date: Date, workouts: [Workout])] {
        guard let week = selectedWeek else { return [] }
        
        let grouped = Dictionary(grouping: week.sortedWorkouts) { workout in
            Calendar.current.startOfDay(for: workout.date)
        }
        
        return grouped.keys.sorted().map { date in
            (date: date, workouts: grouped[date]!.sorted { $0.date < $1.date })
        }
    }
    
    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // Plan Header
            planHeaderView
                .padding(.horizontal, 16)
                .padding(.top, 30)
            
            // Week Selector
            weekSelectorView
                .padding(.top, 16)
            
            // Day Cards
            ScrollViewReader { dayProxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(workoutsByDay, id: \.date) { dayData in
                            let isToday = Calendar.current.isDateInToday(dayData.date)
                            DayCardView(
                                date: dayData.date,
                                workouts: dayData.workouts,
                                onWorkoutTap: { workout in
                                    selectWorkout(workout)
                                },
                                onWorkoutComplete: { workout in
                                    if !readOnly {
                                        toggleWorkoutCompletion(workout)
                                    }
                                }
                            )
                            .id(dayData.date)
                            .overlay(
                                // Invisible anchor for scrolling to today
                                Group {
                                    if isToday {
                                        Color.clear.anchorPreference(key: TodayAnchorKey.self, value: .top) { $0 }
                                    }
                                }
                            )
                        }
                        
                        // "Go to next week" card — only visible when all workouts are done
                        if allWorkoutsCompleted && hasNextWeek {
                            nextWeekCard
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                }
                .onAppear {
                    // Auto-scroll to today's card if it exists in the current week
                    if let todayDate = workoutsByDay.first(where: { Calendar.current.isDateInToday($0.date) })?.date {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            withAnimation {
                                dayProxy.scrollTo(todayDate, anchor: .top)
                            }
                        }
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .sheet(item: $selectedWorkout) { workout in
            WorkoutDetailView(
                workout: workout,
                onComplete: {
                    toggleWorkoutCompletion(workout)
                }
            )
        }
        .alert("Plan Options", isPresented: $showDeleteConfirmation) {
            Button("Archive Plan") {
                archivePlan()
            }
            Button("Delete Permanently", role: .destructive) {
                deletePlan()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Archive keeps your plan in Previous Plans. Delete removes it permanently.")
        }
        .fullScreenCover(isPresented: $showEditSheet) {
            PlanEditInputView(plan: plan, initialInstructions: prefillEditInstruction)
                .onDisappear {
                    prefillEditInstruction = nil
                }
        }
        .fullScreenCover(isPresented: $showAnalysisSheet) {
            PerformanceAnalysisView(plan: plan) { instruction in
                prefillEditInstruction = instruction
                showEditSheet = true
            }
        }
    }
    
    // MARK: - Plan Header View
    private var planHeaderView: some View {
        VStack(spacing: 16) {
            // Archived banner
            if readOnly {
                HStack(spacing: 6) {
                    Image(systemName: "archivebox.fill")
                        .font(.system(size: 12))
                    Text("Archived Plan")
                        .font(.inter(size: 13, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemBackground))
                .clipShape(Capsule())
            }

            // Top row: Stride Logo + Three-dot menu
            HStack {
                if !readOnly {
                    // Invisible spacer for centering the logo
                    Image(systemName: "ellipsis")
                        .font(.title3)
                        .opacity(0)
                }

                Spacer()

                StrideLogoView(height: 32)

                Spacer()

                if !readOnly {
                    // Three-dot menu
                    Menu {
                        Button(action: {
                            PostHogSDK.shared.capture("plan_edit_started")
                            showEditSheet = true
                        }) {
                            Label("Edit Plan", systemImage: "pencil")
                        }

                        Button(action: {
                            PostHogSDK.shared.capture("performance_analysis_opened")
                            showAnalysisSheet = true
                        }) {
                            Label("Analyze Performance", systemImage: "chart.bar.xaxis")
                        }
                        .disabled(plan.completedWorkouts < 3)

                        Button(role: .destructive, action: {
                            showDeleteConfirmation = true
                        }) {
                            Label("Delete Plan", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.title3)
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                }
            }

            // Stats Row
            HStack(spacing: 32) {
                // Days Until Race
                HStack(spacing: 8) {
                    TimeIconView(size: 20)

                    Text("\(plan.daysUntilRace) Days Until Race")
                        .font(.inter(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                }

                // Completed Sessions
                HStack(spacing: 8) {
                    FlagIconView(size: 20)

                    Text("\(completedWorkoutsCount)/\(plan.totalWorkouts) Completed")
                        .font(.inter(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - Next Week Card
    private var nextWeekCard: some View {
        Button(action: {
            goToNextWeek()
        }) {
            HStack {
                Text("Go to Next Week")
                    .font(.inter(size: 16, weight: .semibold))
                
                Spacer()
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.stridePrimary)
            )
        }
        .padding(.top, 8)
    }
    
    // MARK: - Week Selector View
    private var weekSelectorView: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(1...totalWeeks, id: \.self) { weekNumber in
                        WeekPillView(
                            weekNumber: weekNumber,
                            isSelected: weekNumber == selectedWeekNumber,
                            isRaceWeek: plan.sortedWeeks.first { $0.weekNumber == weekNumber }?.isRaceWeek ?? false
                        )
                        .id(weekNumber)
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: WeekScrollPreferenceKey.self,
                                    value: [WeekScrollData(
                                        weekNumber: weekNumber,
                                        centerX: geometry.frame(in: .named("weekScroll")).midX
                                    )]
                                )
                            }
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedWeekNumber = weekNumber
                            }
                            Haptics.selection()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .coordinateSpace(name: "weekScroll")
            .onPreferenceChange(WeekScrollPreferenceKey.self) { weekData in
                // Find the week closest to center
                let screenCenter = UIScreen.main.bounds.width / 2
                if let closestWeek = weekData.min(by: { abs($0.centerX - screenCenter) < abs($1.centerX - screenCenter) }) {
                    // Only trigger haptic when a new week becomes centered (within 20pt threshold)
                    if abs(closestWeek.centerX - screenCenter) < 20 && closestWeek.weekNumber != lastHapticWeek {
                        Haptics.selection()
                        lastHapticWeek = closestWeek.weekNumber
                    }
                }
            }
            .onAppear {
                lastHapticWeek = selectedWeekNumber
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation {
                        proxy.scrollTo(selectedWeekNumber, anchor: .center)
                    }
                }
            }
            .onChange(of: selectedWeekNumber) { oldValue, newValue in
                withAnimation {
                    proxy.scrollTo(newValue, anchor: .center)
                }
                // Haptic feedback when week changes via tap
                if oldValue != newValue {
                    lastHapticWeek = newValue
                }
            }
        }
    }
    
    // MARK: - Sheet Sizing
    /// Compute presentation detents based on workout content length.
    /// Simple workouts (0-2 detail lines) start at .medium (~50%).
    /// Content-heavy workouts (3-4 lines) start at .fraction(0.65).
    /// Very detailed workouts (5+ lines) start at .fraction(0.78).
    /// All cases allow expanding to .large.
    
    // MARK: - Actions
    private func archivePlan() {
        plan.isArchived = true
        plan.archivedAt = Date()
        plan.archiveReason = .abandoned
        try? modelContext.save()
    }

    private func deletePlan() {
        // Run history lives in RunLog — safe to cascade-delete all plan/week/workout objects
        modelContext.delete(plan)
        try? modelContext.save()
    }
    
    private func goToNextWeek() {
        guard hasNextWeek else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            selectedWeekNumber += 1
        }
        Haptics.selection()
    }
    
    private func selectWorkout(_ workout: Workout) {
        selectedWorkout = workout
    }
    
    private func toggleWorkoutCompletion(_ workout: Workout) {
        workout.toggleCompletion()

        if workout.isCompleted {
            PostHogSDK.shared.capture("workout_marked_complete", properties: [
                "workout_type": workout.workoutTypeRaw ?? "unknown",
            ])
        }

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(workout.isCompleted ? .success : .warning)

        // Save changes
        try? modelContext.save()
    }
}

// MARK: - Today Anchor Key
struct TodayAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGPoint>? = nil
    static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) {
        value = value ?? nextValue()
    }
}

// MARK: - Week Scroll Tracking
struct WeekScrollData: Equatable {
    let weekNumber: Int
    let centerX: CGFloat
}

struct WeekScrollPreferenceKey: PreferenceKey {
    static var defaultValue: [WeekScrollData] = []
    
    static func reduce(value: inout [WeekScrollData], nextValue: () -> [WeekScrollData]) {
        value.append(contentsOf: nextValue())
    }
}

// MARK: - Week Pill View
struct WeekPillView: View {
    let weekNumber: Int
    let isSelected: Bool
    let isRaceWeek: Bool
    
    // Ratio approximately 26:35 (w:h)
    private let pillWidth: CGFloat = 36
    private let pillHeight: CGFloat = 48
    
    var body: some View {
        Text("W\(weekNumber)")
            .font(.inter(size: 13, weight: isSelected ? .bold : .medium))
            .foregroundColor(foregroundColor)
            .frame(width: pillWidth, height: pillHeight)
            .background(
                RoundedRectangle(cornerRadius: pillWidth / 2, style: .continuous)
                    .fill(backgroundColor)
            )
    }
    
    private var foregroundColor: Color {
        if isSelected {
            return .white
        } else if isRaceWeek {
            return .stridePrimary
        } else {
            return .secondary
        }
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return .stridePrimary
        } else {
            return Color(.tertiarySystemBackground)
        }
    }
}

#Preview {
    NavigationStack {
        PlanView(plan: {
            let plan = TrainingPlan(
                raceType: .marathon,
                raceDate: Date().addingTimeInterval(86400 * 84),
                raceName: "Boston Marathon",
                goalTime: "3:30:00",
                currentWeeklyMileage: 50,
                longestRecentRun: 20,
                fitnessLevel: .intermediate,
                startDate: Date()
            )
            return plan
        }())
    }
    .modelContainer(for: TrainingPlan.self, inMemory: true)
}
