import SwiftUI

/// Calendar view showing the full training plan week by week
struct PlanCalendarView: View {
    @ObservedObject var planManager: TrainingPlanManager
    @StateObject private var adaptationManager: WeeklyAdaptationManager
    @State private var selectedWorkout: PlannedWorkout?
    @State private var showDeleteConfirmation = false
    @State private var showExplainability = false
    @State private var expandedWeeks: Set<UUID> = []
    
    private let storageManager: StorageManager
    
    init(planManager: TrainingPlanManager, storageManager: StorageManager) {
        self.planManager = planManager
        self.storageManager = storageManager
        _adaptationManager = StateObject(wrappedValue: WeeklyAdaptationManager(
            storageManager: storageManager,
            trainingPlanManager: planManager
        ))
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if let plan = planManager.activePlan {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Adaptation Banner (if present)
                            if adaptationManager.showBanner,
                               let record = adaptationManager.latestAdaptation,
                               !record.dismissed {
                                AdaptationBannerView(
                                    record: record,
                                    onDismiss: {
                                        adaptationManager.dismissBanner()
                                    },
                                    onTap: {
                                        adaptationManager.markAdaptationViewed()
                                    }
                                )
                            }
                            
                            // Plan Header
                            planHeaderCard(plan)
                            
                            // Current Phase Badge
                            if let phase = plan.currentPhase {
                                phaseCard(phase)
                            }
                            
                            // Weeks List
                            ForEach(plan.weeks) { week in
                                weekCard(week)
                            }
                            
                            // Race Day Card
                            raceDayCard(plan)
                            
                            Spacer(minLength: 20)
                        }
                        .padding()
                    }
                } else {
                    emptyState
                }
            }
            .navigationTitle("Training Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if planManager.hasActivePlan {
                    // Info button for explainability
                    ToolbarItem(placement: .navigationBarLeading) {
                        if let plan = planManager.activePlan, plan.generationContext != nil {
                            Button(action: {
                                showExplainability = true
                            }) {
                                Image(systemName: "info.circle")
                            }
                        }
                    }
                    
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            #if DEBUG
                            Button(action: {
                                Task {
                                    do {
                                        try await adaptationManager.triggerManualAdaptation()
                                    } catch {
                                        print("Manual adaptation failed: \(error)")
                                    }
                                }
                            }) {
                                Label("Run Adaptation (Debug)", systemImage: "arrow.triangle.2.circlepath")
                            }
                            
                            Divider()
                            #endif
                            
                            Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                                Label("Delete Plan", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .sheet(item: $selectedWorkout) { workout in
                NavigationStack {
                    PlannedWorkoutDetailView(workout: workout, planManager: planManager)
                }
            }
            .sheet(isPresented: $showExplainability) {
                if let plan = planManager.activePlan,
                   let context = plan.generationContext,
                   let goal = storageManager.loadGoal(id: plan.goalId) {
                    NavigationStack {
                        ScrollView {
                            VStack(spacing: 20) {
                                PlanExplainabilitySection(
                                    context: context,
                                    goalName: goal.displayName
                                )
                            }
                            .padding()
                        }
                        .navigationTitle("Plan Details")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    showExplainability = false
                                }
                            }
                        }
                    }
                }
            }
            .alert("Delete Training Plan", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    do {
                        try planManager.deletePlan()
                    } catch {
                        print("Error deleting plan: \(error)")
                    }
                }
            } message: {
                Text("Are you sure you want to delete your training plan? This cannot be undone.")
            }
            .onAppear {
                // Initialize expanded weeks: expand past and current, collapse future
                if let plan = planManager.activePlan {
                    expandedWeeks = Set(plan.weeks.filter { $0.isPast || $0.isCurrent }.map { $0.id })
                }
                
                // Check if adaptation should run when view appears
                Task {
                    await adaptationManager.checkAndRunIfNeeded()
                }
            }
        }
    }
    
    // MARK: - Plan Header Card
    
    private func planHeaderCard(_ plan: TrainingPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(plan.totalWeeks)-Week Training Plan")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(plan.generationMethod.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Event Countdown
                if let goal = planManager.activePlan {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(daysUntil(goal.eventDate))")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.green)
                        Text("days to go")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Divider()
            
            // Stats Row
            HStack(spacing: 20) {
                customStatBadge(image: Image(BrandAssets.logo), label: "\(plan.weeklyRunDays) runs/week")
                customStatBadge(image: Image(BrandAssets.strengthIcon), label: "\(plan.weeklyGymDays) gym/week")
                statBadge(icon: "checkmark.circle", label: "\(plan.completedWorkoutsCount)/\(plan.totalWorkoutsCount)")
            }
            
            // Progress Bar
            ProgressView(value: plan.completionPercentage, total: 100)
                .tint(.green)
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.green.opacity(0.1), Color.green.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
    }
    
    private func statBadge(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(.green)
                .font(.caption)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func customStatBadge(image: Image, label: String) -> some View {
        HStack(spacing: 6) {
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 12, height: 12)
                .foregroundColor(.green)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func daysUntil(_ date: Date) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: date)
        return max(0, components.day ?? 0)
    }
    
    // MARK: - Phase Card
    
    private func phaseCard(_ phase: TrainingPhase) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Current Phase")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Week \(phase.weekRange.lowerBound)-\(phase.weekRange.upperBound)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(phase.name)
                .font(.headline)
            
            Text(phase.focus)
                .font(.subheadline)
                .foregroundColor(.green)
            
            Text(phase.description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Race Day Card
    
    private func raceDayCard(_ plan: TrainingPlan) -> some View {
        guard let goal = storageManager.loadGoal(id: plan.goalId) else {
            return AnyView(EmptyView())
        }
        
        return AnyView(
            VStack(alignment: .leading, spacing: 16) {
                // Header with flag icon
                HStack(spacing: 12) {
                    Image(systemName: "flag.checkered.2.crossed")
                        .font(.system(size: 36))
                        .foregroundColor(.green)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Race Day")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(formatRaceDate(plan.eventDate))
                            .font(.headline)
                            .foregroundColor(.green)
                    }
                    
                    Spacer()
                }
                
                Divider()
                
                // Race Details
                VStack(alignment: .leading, spacing: 12) {
                    // Distance
                    if let distanceKm = goal.distanceKm {
                        HStack {
                            Image(BrandAssets.logo)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 28, height: 28)
                                .foregroundColor(.green)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Distance")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.1f km", distanceKm))
                                    .font(.headline)
                            }
                            
                            Spacer()
                        }
                    }
                    
                    // Goal Type and Target
                    HStack {
                        Image(systemName: goal.type.requiresTargetTime ? "timer" : "checkmark.circle")
                            .foregroundColor(.green)
                            .font(.title3)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Goal")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if let targetTime = goal.formattedTargetTime {
                                Text(targetTime)
                                    .font(.headline)
                            } else {
                                Text("Complete the Distance")
                                    .font(.headline)
                            }
                        }
                        
                        Spacer()
                    }
                    
                    // Event Name (if available)
                    if let title = goal.title, !title.isEmpty {
                        HStack {
                            Image(systemName: "trophy")
                                .foregroundColor(.green)
                                .font(.title3)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Event")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(title)
                                    .font(.headline)
                            }
                            
                            Spacer()
                        }
                    }
                }
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [Color.green.opacity(0.15), Color.green.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.green.opacity(0.3), lineWidth: 2)
            )
        )
    }
    
    // MARK: - Week Card
    
    private func weekCard(_ week: WeekPlan) -> some View {
        let isExpanded = expandedWeeks.contains(week.id)
        
        return VStack(alignment: .leading, spacing: 12) {
            // Week Header (Interactive)
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    if isExpanded {
                        expandedWeeks.remove(week.id)
                    } else {
                        expandedWeeks.insert(week.id)
                    }
                }
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Week \(week.weekNumber)")
                            .font(.headline)
                        Text(formatWeekRange(start: week.startDate, end: week.endDate))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Week Status Badge
                    if week.isPast {
                        statusBadge(text: "Completed", color: .green)
                    } else if week.isCurrent {
                        statusBadge(text: "Current", color: .stridePrimary)
                    } else {
                        statusBadge(text: "Upcoming", color: .gray)
                    }
                    
                    // Chevron indicator
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 8)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // Collapsible Content
            if isExpanded {
                // Phase and Volume
                HStack {
                    Text(week.phase.name)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(6)
                    
                    Spacer()
                    
                    Text(String(format: "%.1f km target", week.targetWeeklyKm))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // Workouts
                VStack(spacing: 8) {
                    ForEach(week.workouts) { workout in
                        workoutRow(workout)
                    }
                }
            }
        }
        .padding()
        .background(week.isCurrent ? Color.blue.opacity(0.05) : Color(.systemGray6))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(week.isCurrent ? Color.blue : Color.clear, lineWidth: 2)
        )
    }
    
    private func statusBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(8)
    }
    
    // MARK: - Workout Row
    
    private func workoutRow(_ workout: PlannedWorkout) -> some View {
        Group {
            if workout.type == .rest {
                // Rest day - non-interactive, styled differently
                restDayRow(workout)
            } else {
                // Regular workout - interactive
                interactiveWorkoutRow(workout)
            }
        }
    }
    
    private func restDayRow(_ workout: PlannedWorkout) -> some View {
        HStack(spacing: 12) {
            // Day
            VStack(spacing: 2) {
                Text(dayOfWeek(workout.date))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(dayNumber(workout.date))
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .frame(width: 40)
            
            // Moon icon
            Image(systemName: "moon.fill")
                .font(.title3)
                .foregroundColor(.orange)
                .frame(width: 24, height: 24)
            
            // Rest day details
            VStack(alignment: .leading, spacing: 2) {
                Text("Rest Day")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Text("Recovery helps adaptation")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // No chevron - not interactive
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private func interactiveWorkoutRow(_ workout: PlannedWorkout) -> some View {
        Button(action: { selectedWorkout = workout }) {
            HStack(spacing: 12) {
                // Day
                VStack(spacing: 2) {
                    Text(dayOfWeek(workout.date))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(dayNumber(workout.date))
                        .font(.headline)
                }
                .frame(width: 40)
                
                // Workout Type Icon
                workout.type.brandIcon
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .foregroundColor(workout.type.brandColor)
                
                // Workout Details
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(workout.summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Completion Status
                if workout.completed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color(.systemBackground))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Training Plan")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Generate a training plan to see your weekly schedule")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
    
    // MARK: - Helpers
    
    private func formatWeekRange(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
    
    private func formatRaceDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }
    
    private func dayOfWeek(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
    
    private func dayNumber(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
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
}

// MARK: - Preview

#Preview {
    PlanCalendarView(
        planManager: TrainingPlanManager(storageManager: StorageManager()),
        storageManager: StorageManager()
    )
}
