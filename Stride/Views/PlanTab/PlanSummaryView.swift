import SwiftUI

/// Summary view shown immediately after plan generation
/// Provides high-level orientation and builds confidence before diving into details
struct PlanSummaryView: View {
    @ObservedObject var planManager: TrainingPlanManager
    @ObservedObject var goalManager: GoalManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var isHydrating = false
    @State private var hydrationError: String?
    
    let onViewPlan: () -> Void
    let onViewWorkout: () -> Void
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Hero Confirmation
                    heroSection
                    
                    // Goal Feasibility Warning (if applicable)
                    if let plan = planManager.activePlan,
                       let feasibility = plan.goalFeasibility,
                       !feasibility.isRealistic {
                        goalFeasibilityWarningSection(feasibility: feasibility)
                    }
                    
                    // Explainability Section (How This Plan Was Built)
                    if let plan = planManager.activePlan,
                       let context = plan.generationContext,
                       let goal = goalManager.activeGoal {
                        PlanExplainabilitySection(
                            context: context,
                            goalName: goal.displayName
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    // Journey Overview
                    if let plan = planManager.activePlan {
                        journeyOverviewSection(plan: plan)
                        
                        // Phase Breakdown
                        phaseBreakdownSection(plan: plan)
                        
                        // Volume Progression
                        volumeProgressionSection(plan: plan)
                        
                        // Race Week Callout
                        raceWeekCalloutSection(plan: plan)
                        
                        // Coach Message
                        coachMessageSection(plan: plan)
                        
                        // Action Buttons
                        actionButtonsSection
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle("Your Training Plan")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    // MARK: - Hero Section
    
    private var heroSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 70))
                .foregroundColor(.green)
            
            Text("Plan Created!")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Here's how we'll get you to race day")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }
    
    // MARK: - Journey Overview
    
    private func journeyOverviewSection(plan: TrainingPlan) -> some View {
        // Use skeleton data for totals if plan isn't hydrated yet
        let skeleton = planManager.activeSkeleton
        let totalKm: Double
        let estimatedWorkouts: Int
        
        if let skeleton = skeleton, planManager.needsHydration {
            // Calculate from skeleton
            totalKm = skeleton.weeklyTargets.reduce(0) { $0 + $1.totalKm }
            estimatedWorkouts = skeleton.weeklyTargets.reduce(0) { $0 + $1.runDays + $1.gymDays }
        } else {
            // Use actual plan data
            totalKm = plan.totalPlannedKm
            estimatedWorkouts = plan.totalWorkoutsCount
        }
        
        return VStack(alignment: .leading, spacing: 12) {
            Text("Your Journey")
                .font(.title3)
                .fontWeight(.semibold)
            
            HStack(spacing: 20) {
                overviewStat(
                    value: "\(plan.totalWeeks)",
                    label: "Weeks",
                    icon: "calendar"
                )
                
                overviewStat(
                    value: "\(plan.phases.count)",
                    label: "Phases",
                    icon: "chart.line.uptrend.xyaxis"
                )
                
                overviewStat(
                    value: "~\(estimatedWorkouts)",
                    label: "Workouts",
                    icon: "figure.run"
                )
                
                overviewStat(
                    value: String(format: "%.0f km", totalKm),
                    label: "Total",
                    icon: "map"
                )
            }
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
    
    private func overviewStat(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.green)
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Phase Breakdown
    
    private func phaseBreakdownSection(plan: TrainingPlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Training Phases")
                .font(.title3)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                ForEach(plan.phases, id: \.name) { phase in
                    phaseCard(phase: phase, plan: plan)
                }
            }
        }
    }
    
    private func phaseCard(phase: TrainingPhase, plan: TrainingPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(phase.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("Weeks \(phase.weekRange.lowerBound)-\(phase.weekRange.upperBound)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(phase.focus)
                .font(.subheadline)
                .foregroundColor(.green)
            
            // Calculate volume range for this phase
            let phaseWeeks = plan.weeks.filter { phase.weekRange.contains($0.weekNumber) }
            if !phaseWeeks.isEmpty {
                let minKm = phaseWeeks.map { $0.targetWeeklyKm }.min() ?? 0
                let maxKm = phaseWeeks.map { $0.targetWeeklyKm }.max() ?? 0
                
                Text(String(format: "%.0f-%.0f km/week", minKm, maxKm))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Volume Progression
    
    private func volumeProgressionSection(plan: TrainingPlan) -> some View {
        // Use skeleton data for volumes if available
        let skeleton = planManager.activeSkeleton
        let allWeeklyKms: [Double]
        
        if let skeleton = skeleton, planManager.needsHydration {
            allWeeklyKms = skeleton.weeklyTargets.map { $0.totalKm }
        } else {
            allWeeklyKms = plan.weeks.map { $0.targetWeeklyKm }
        }
        
        let minVolume = allWeeklyKms.min() ?? 0
        let maxVolume = allWeeklyKms.max() ?? 0
        let avgVolume = allWeeklyKms.isEmpty ? 0 : allWeeklyKms.reduce(0, +) / Double(allWeeklyKms.count)
        
        return VStack(alignment: .leading, spacing: 12) {
            Text("Volume Progression")
                .font(.title3)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "arrow.up.right")
                        .foregroundColor(.green)
                    Text("Starting Volume")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.0f km/week", minVolume))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Image(systemName: "arrow.up")
                        .foregroundColor(.green)
                    Text("Peak Volume")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.0f km/week", maxVolume))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Image(systemName: "chart.bar")
                        .foregroundColor(.green)
                    Text("Average Volume")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.0f km/week", avgVolume))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Race Week Callout
    
    private func raceWeekCalloutSection(plan: TrainingPlan) -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "flag.checkered")
                    .font(.title2)
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Race Week")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if let goal = goalManager.activeGoal {
                        Text(formatDate(goal.eventDate))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(daysUntilRace(plan.eventDate))")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                    Text("days")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Find taper phase
            if let taperPhase = plan.phases.first(where: { $0.name.contains("Taper") }) {
                Text("\(taperPhase.focus) • Week \(taperPhase.weekRange.lowerBound)-\(taperPhase.weekRange.upperBound)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.15), Color.orange.opacity(0.05)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(12)
    }
    
    // MARK: - Coach Message
    
    private func coachMessageSection(plan: TrainingPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "message.fill")
                    .foregroundColor(.green)
                Text("Your Coach")
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            
            // Use skeleton's coach message if available, otherwise generate one
            let message = planManager.activeSkeleton?.coachMessage ?? generateCoachMessage(plan: plan)
            Text(message)
                .font(.body)
                .foregroundColor(.primary)
                .lineSpacing(4)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func generateCoachMessage(plan: TrainingPlan) -> String {
        let weeks = plan.totalWeeks
        
        // Fallback messages if skeleton not available
        if weeks <= 8 {
            return "This is an efficient \(weeks)-week plan focused on sharpening your fitness for race day. We'll balance quality work with adequate recovery to arrive at the start line fresh and ready."
        } else if weeks >= 16 {
            return "This comprehensive \(weeks)-week plan gives us time to build a rock-solid foundation. We'll start with base building, gradually layer in intensity, and peak at just the right time. Trust the process - consistency over these weeks will transform your fitness."
        } else {
            return "This plan is built around your goal and current fitness. We'll start by building a strong aerobic base, then gradually increase intensity as race day approaches."
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            // Primary: View Full Plan (triggers hydration if needed)
            Button(action: handleViewFullPlan) {
                HStack {
                    if isHydrating {
                        ProgressView()
                            .tint(.white)
                        Text("Loading Workouts...")
                            .fontWeight(.semibold)
                    } else {
                        Image(systemName: "calendar")
                        Text("View Full Plan")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isHydrating ? Color.gray : Color.green)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isHydrating)
            
            // Hydration error message
            if let error = hydrationError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
            
            // Secondary: Today's Workout (if available and plan is hydrated)
            if !planManager.needsHydration && planManager.todaysWorkout != nil {
                Button(action: {
                    dismiss()
                    onViewWorkout()
                }) {
                    HStack {
                        Image(systemName: "list.bullet.clipboard")
                        Text("Today's Workout")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
                }
            }
        }
    }
    
    // MARK: - Hydration Action
    
    private func handleViewFullPlan() {
        // If plan needs hydration, trigger it first
        guard planManager.needsHydration else {
            // Already hydrated, just navigate
            dismiss()
            onViewPlan()
            return
        }
        
        guard let goal = goalManager.activeGoal else {
            dismiss()
            onViewPlan()
            return
        }
        
        isHydrating = true
        hydrationError = nil
        
        Task {
            do {
                let baseline = planManager.loadLatestBaselineAssessment()
                let preferences = planManager.loadPreferences()
                
                try await planManager.hydratePlanWithDailySchedule(
                    goal: goal,
                    baseline: baseline,
                    preferences: preferences
                )
                
                await MainActor.run {
                    isHydrating = false
                    dismiss()
                    onViewPlan()
                }
            } catch {
                await MainActor.run {
                    isHydrating = false
                    hydrationError = "Failed to load workouts: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Goal Feasibility Warning
    
    private func goalFeasibilityWarningSection(feasibility: GoalFeasibility) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Warning Banner
            HStack(spacing: 12) {
                Image(systemName: feasibility.rating == .unrealistic ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .font(.title2)
                    .foregroundColor(feasibility.rating == .unrealistic ? .red : .orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Goal is \(feasibility.rating.displayName)")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(feasibility.reasoning)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(feasibility.rating == .unrealistic ? Color.red.opacity(0.1) : Color.orange.opacity(0.1))
            )
            
            // Recommended Adjustment
            if let recommendedTime = feasibility.recommendedTargetTime {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recommended Goal")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        if let goal = goalManager.activeGoal {
                            VStack(alignment: .leading) {
                                Text("Current: \(goal.formattedTargetTime ?? "")")
                                    .font(.body)
                                    .strikethrough()
                                Text("Recommended: \(formatTime(recommendedTime))")
                                    .font(.body)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.green)
                            }
                        }
                        
                        Spacer()
                    }
                    
                    HStack(spacing: 12) {
                        Button("Accept Adjusted Goal") {
                            acceptAdjustedGoal(recommendedTime: recommendedTime)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        
                        Button("Keep Original Goal") {
                            // Just dismiss, proceed with warning visible
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
    }
    
    private func acceptAdjustedGoal(recommendedTime: TimeInterval) {
        Task {
            do {
                // Update goal with recommended time
                try await goalManager.updateGoalTargetTime(recommendedTime)
                
                // Regenerate plan
                if let goal = goalManager.activeGoal {
                    let baseline = planManager.loadLatestBaselineAssessment()
                    let preferences = planManager.loadPreferences()
                    try await planManager.generatePlan(
                        for: goal,
                        baseline: baseline,
                        preferences: preferences
                    )
                }
            } catch {
                print("❌ Failed to regenerate with adjusted goal: \(error)")
            }
        }
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    // MARK: - Helpers
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }
    
    private func daysUntilRace(_ eventDate: Date) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: eventDate)
        return max(0, components.day ?? 0)
    }
}

// MARK: - Preview

#Preview {
    PlanSummaryView(
        planManager: TrainingPlanManager(storageManager: StorageManager()),
        goalManager: GoalManager(storageManager: StorageManager()),
        onViewPlan: {},
        onViewWorkout: {}
    )
}
