import SwiftUI

/// View for generating a new training plan
struct PlanGenerationView: View {
    @ObservedObject var planManager: TrainingPlanManager
    @ObservedObject var goalManager: GoalManager
    @ObservedObject var storageManager: StorageManager
    
    @State private var preferences: TrainingPreferences = .default
    @State private var showGoalSetup = false
    @State private var showBaselinePrompt = false
    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var showError = false
    @State private var showSummary = false
    @State private var navigateToWorkout = false
    
    @Binding var selectedTab: Int
    
    init(
        planManager: TrainingPlanManager,
        goalManager: GoalManager,
        storageManager: StorageManager,
        selectedTab: Binding<Int>
    ) {
        self.planManager = planManager
        self.goalManager = goalManager
        self.storageManager = storageManager
        self._selectedTab = selectedTab
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection
                    
                    // API Key Status Warning
                    if !planManager.aiCoachEnabled {
                        apiKeyWarningSection
                    }
                    
                    // Prerequisites Check
                    prerequisitesSection
                    
                    // Preferences Configuration
                    if goalManager.hasActiveGoal {
                        preferencesSection
                        
                        // Availability Section
                        availabilitySection
                        
                        // Plan Preview
                        planPreviewSection
                        
                        // Generate Button
                        generateButton
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle("Training Plan")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showSummary) {
                PlanSummaryView(
                    planManager: planManager,
                    goalManager: goalManager,
                    onViewPlan: {
                        showSummary = false
                        planManager.dismissPlanSummary()
                    },
                    onViewWorkout: {
                        showSummary = false
                        planManager.dismissPlanSummary()
                        // Switch to Workout tab
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            selectedTab = 1
                        }
                    }
                )
            }
            .sheet(isPresented: $showGoalSetup) {
                GoalSetupView(mode: .create, goalManager: goalManager)
            }
            .alert("Generation Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(generationError ?? "An error occurred")
            }
            .alert("Baseline Assessment Recommended", isPresented: $showBaselinePrompt) {
                Button("Skip for Now") {
                    startGeneration()
                }
                Button("Set Up Baseline") {
                    // Navigate to baseline setup
                    showBaselinePrompt = false
                }
            } message: {
                Text("A baseline assessment helps create a personalized plan with accurate paces. You can skip this and add it later.")
            }
            .onChange(of: planManager.showPlanSummary) { oldValue, newValue in
                if newValue {
                    showSummary = true
                }
            }
        }
    }
    
    // MARK: - API Key Warning Section
    
    private var apiKeyWarningSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Planning Disabled")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("Add your OpenAI API key in Settings to enable AI-powered training plans")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 50))
                .foregroundColor(.green)
            
            Text("Generate Training Plan")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Create a personalized week-by-week training schedule from today until your event date")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .padding(.vertical, 20)
    }
    
    // MARK: - Prerequisites Section
    
    private var prerequisitesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Prerequisites")
                .font(.headline)
            
            // Goal Check
            prerequisiteRow(
                icon: "target",
                title: "Active Goal",
                status: goalManager.hasActiveGoal ? .complete : .required,
                action: { showGoalSetup = true }
            )
            
            // Baseline Check
            let hasBaseline = storageManager.loadLatestBaselineAssessment() != nil
            prerequisiteRow(
                icon: "figure.run.circle",
                title: "Baseline Assessment",
                status: hasBaseline ? .complete : .recommended,
                action: { showBaselinePrompt = true }
            )
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func prerequisiteRow(
        icon: String,
        title: String,
        status: PrerequisiteStatus,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(status.color)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(status.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if status != .complete {
                Button(action: action) {
                    Text(status == .required ? "Set Up" : "Add")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(status.color)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
    }
    
    enum PrerequisiteStatus {
        case complete
        case required
        case recommended
        
        var color: Color {
            switch self {
            case .complete: return .green
            case .required: return .orange
            case .recommended: return .blue
            }
        }
        
        var message: String {
            switch self {
            case .complete: return "Ready"
            case .required: return "Required to generate plan"
            case .recommended: return "Recommended for better pacing"
            }
        }
    }
    
    // MARK: - Preferences Section
    
    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Training Preferences")
                .font(.headline)
            
            // Run Days
            VStack(alignment: .leading, spacing: 8) {
                Text("Run days per week")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Picker("Run days", selection: $preferences.weeklyRunDays) {
                    ForEach(2...6, id: \.self) { days in
                        Text("\(days) days").tag(days)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            // Gym Days
            VStack(alignment: .leading, spacing: 8) {
                Text("Strength/gym days per week")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Picker("Gym days", selection: $preferences.weeklyGymDays) {
                    ForEach(0...4, id: \.self) { days in
                        Text("\(days) days").tag(days)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            // Long Run Day
            VStack(alignment: .leading, spacing: 8) {
                Text("Preferred long run day")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Picker("Long run day", selection: $preferences.preferredLongRunDay) {
                    ForEach(0...6, id: \.self) { day in
                        Text(TrainingPreferences.dayName(for: day)).tag(day)
                    }
                }
                .pickerStyle(.menu)
            }
            
            // Summary
            Text(preferences.summary)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Availability Section
    
    private var availabilitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Training Days")
                    .font(.headline)
                
                Spacer()
                
                NavigationLink(destination: AvailabilitySettingsView(storageManager: storageManager)) {
                    Text("Customize")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            // Quick week selector
            HStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { dayIndex in
                    quickDayButton(for: dayIndex)
                }
            }
            
            // Summary
            let avail = preferences.getEffectiveAvailability()
            Text(avail.summary)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
            
            // Warning if no training days
            if avail.totalAvailableDays == 0 {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("At least one training day is required")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func quickDayButton(for dayIndex: Int) -> some View {
        let avail = preferences.getEffectiveAvailability()
        let state = avail.stateForDay(dayIndex)
        
        return Button(action: {
            var newAvail = avail
            let nextState = newAvail.nextState(for: state)
            newAvail.setState(nextState, forDay: dayIndex)
            preferences.availability = newAvail
        }) {
            VStack(spacing: 4) {
                quickStateIcon(for: state)
                    .font(.callout)
                    .foregroundColor(quickStateColor(for: state))
                
                Text(TrainingAvailability.shortDayName(for: dayIndex))
                    .font(.caption2)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(quickStateBackground(for: state))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func quickStateIcon(for state: DayState) -> some View {
        Group {
            switch state {
            case .available:
                Image(systemName: "checkmark.circle.fill")
            case .rest:
                Image(systemName: "moon.fill")
            case .unavailable:
                Image(systemName: "circle")
            }
        }
    }
    
    private func quickStateColor(for state: DayState) -> Color {
        switch state {
        case .available: return .green
        case .rest: return .orange
        case .unavailable: return .gray
        }
    }
    
    private func quickStateBackground(for state: DayState) -> Color {
        switch state {
        case .available: return Color.green.opacity(0.1)
        case .rest: return Color.orange.opacity(0.1)
        case .unavailable: return Color(.systemGray5)
        }
    }
    
    // MARK: - Plan Preview Section
    
    private var planPreviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Plan Preview")
                .font(.headline)
            
            if let goal = goalManager.activeGoal {
                VStack(spacing: 12) {
                    previewRow(icon: "calendar", label: "Duration", value: "\(goal.weeksRemaining) weeks")
                    previewRow(icon: "flag.checkered", label: "Event", value: goal.displayName)
                    
                    if let targetTime = goal.formattedTargetTime {
                        previewRow(icon: "target", label: "Target", value: targetTime)
                    } else {
                        previewRow(icon: "heart.fill", label: "Focus", value: "Finish strong & healthy")
                    }
                    
                    if let distance = goal.distanceKm {
                        previewRow(icon: "ruler", label: "Distance", value: String(format: "%.1f km", distance))
                    }
                    
                    Divider()
                    
                    // Phases Preview
                    let phases = getPhases(weeks: goal.weeksRemaining)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Training Phases:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ForEach(phases, id: \.name) { phase in
                            HStack {
                                Text(phase.name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("Week \(phase.weekRange.lowerBound)-\(phase.weekRange.upperBound)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func previewRow(icon: String, label: String, value: String) -> some View {
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
    
    // MARK: - Generate Button
    
    private var generateButton: some View {
        Button(action: handleGenerate) {
            HStack {
                if isGenerating {
                    ProgressView()
                        .tint(.white)
                    Text("Generating...")
                } else {
                    Image(systemName: "sparkles")
                    Text("Generate Training Plan")
                }
            }
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .padding()
            .background(goalManager.hasActiveGoal && !isGenerating ? Color.green : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(!goalManager.hasActiveGoal || isGenerating)
    }
    
    // MARK: - Actions
    
    private func handleGenerate() {
        guard let goal = goalManager.activeGoal else {
            showGoalSetup = true
            return
        }
        
        let baseline = storageManager.loadLatestBaselineAssessment()
        
        if baseline == nil && !showBaselinePrompt {
            showBaselinePrompt = true
            return
        }
        
        startGeneration()
    }
    
    private func startGeneration() {
        guard let goal = goalManager.activeGoal else { 
            print("❌ No active goal found")
            return 
        }
        
        // Validate goal has required data
        guard goal.weeksRemaining > 0 else {
            generationError = "Event date must be in the future"
            showError = true
            return
        }
        
        isGenerating = true
        generationError = nil
        
        let baseline = storageManager.loadLatestBaselineAssessment()
        
        print("⚡ Starting SKELETON generation for goal: \(goal.displayName)")
        print("⚡ Weeks available: \(goal.weeksRemaining)")
        print("⚡ Has baseline: \(baseline != nil)")
        
        Task {
            do {
                // Use skeleton-first flow for fast summary display
                _ = try await planManager.generatePlanSkeleton(
                    for: goal,
                    baseline: baseline,
                    preferences: preferences
                )
                
                print("✅ Skeleton generation successful - summary will appear")
                
                await MainActor.run {
                    isGenerating = false
                    // showPlanSummary is set by planManager
                }
            } catch {
                print("❌ Skeleton generation failed: \(error)")
                
                await MainActor.run {
                    isGenerating = false
                    generationError = error.localizedDescription
                    showError = true
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    /// Calculate training phases based on week count only (no full plan generation)
    /// This is a lightweight preview that doesn't trigger exercise selection or AI calls
    private func getPhases(weeks: Int) -> [TrainingPhase] {
        guard weeks > 0 else {
            return [TrainingPhase.baseBuilding(weeks: 1...1)]
        }
        
        // Simple periodization based on available weeks
        // This mirrors the logic in TrainingPlanGenerator.determinePeriodization
        // but without generating a full plan
        
        if weeks <= 4 {
            // Very short: Base + Taper only
            let baseEnd = max(1, weeks - 1)
            return [
                TrainingPhase.baseBuilding(weeks: 1...baseEnd),
                TrainingPhase.taper(weeks: weeks...weeks)
            ]
        } else if weeks <= 8 {
            // Short: Base, Build, Taper
            let baseEnd = weeks / 2
            let buildEnd = weeks - 1
            return [
                TrainingPhase.baseBuilding(weeks: 1...baseEnd),
                TrainingPhase.buildUp(weeks: (baseEnd + 1)...buildEnd),
                TrainingPhase.taper(weeks: weeks...weeks)
            ]
        } else if weeks <= 12 {
            // Medium: Base, Build, Peak, Taper
            let baseEnd = Int(Double(weeks) * 0.35)
            let buildEnd = Int(Double(weeks) * 0.65)
            let peakEnd = weeks - 2
            return [
                TrainingPhase.baseBuilding(weeks: 1...baseEnd),
                TrainingPhase.buildUp(weeks: (baseEnd + 1)...buildEnd),
                TrainingPhase.peakTraining(weeks: (buildEnd + 1)...peakEnd),
                TrainingPhase.taper(weeks: (peakEnd + 1)...weeks)
            ]
        } else {
            // Long: Standard 4-phase periodization
            let baseEnd = Int(Double(weeks) * 0.30)
            let buildEnd = Int(Double(weeks) * 0.60)
            let peakEnd = Int(Double(weeks) * 0.85)
            return [
                TrainingPhase.baseBuilding(weeks: 1...baseEnd),
                TrainingPhase.buildUp(weeks: (baseEnd + 1)...buildEnd),
                TrainingPhase.peakTraining(weeks: (buildEnd + 1)...peakEnd),
                TrainingPhase.taper(weeks: (peakEnd + 1)...weeks)
            ]
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var selectedTab = 0
    
    return PlanGenerationView(
        planManager: TrainingPlanManager(storageManager: StorageManager()),
        goalManager: GoalManager(storageManager: StorageManager()),
        storageManager: StorageManager(),
        selectedTab: $selectedTab
    )
}
