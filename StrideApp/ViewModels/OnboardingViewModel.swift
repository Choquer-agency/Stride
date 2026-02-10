import Foundation
import SwiftUI
import SwiftData

@MainActor
class OnboardingViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var currentStep: Int = 1
    @Published var data = OnboardingData()
    @Published var isLoading = false
    @Published var loadingMessage = ""
    @Published var streamingContent = ""
    @Published var error: String?
    @Published var showError = false
    
    // Conflict Resolution
    @Published var conflictAnalysis: ConflictAnalysisResponse?
    @Published var hasConflicts = false
    @Published var selectedMode: PlanMode?
    
    // Generated Plan
    @Published var generatedPlan: TrainingPlan?
    @Published var isComplete = false
    @Published var isGeneratingPlan = false
    
    // MARK: - Constants
    let totalSteps = 5
    
    // MARK: - Dependencies
    private let apiService = APIService.shared
    
    // MARK: - Initialization
    init() {
        // Set default dates
        let calendar = Calendar.current
        let today = Date()
        
        // Start date: next Monday
        var nextMonday = today
        while calendar.component(.weekday, from: nextMonday) != 2 {
            nextMonday = calendar.date(byAdding: .day, value: 1, to: nextMonday)!
        }
        data.startDate = nextMonday
        
        // Race date: 12 weeks from start
        data.raceDate = calendar.date(byAdding: .day, value: 84, to: nextMonday)!
    }
    
    // MARK: - Navigation
    var canGoNext: Bool {
        switch currentStep {
        case 1: return data.isStep1Valid
        case 2: return data.isStep2Valid
        case 3: return data.isStep3Valid
        case 4: return data.isStep4Valid
        case 5: return selectedMode != nil
        default: return false
        }
    }
    
    var canGoBack: Bool {
        currentStep > 1
    }
    
    func nextStep(context: ModelContext? = nil) {
        guard canGoNext else { return }
        
        if currentStep == 4 {
            // Analyze conflicts before proceeding
            Task {
                await analyzeConflicts(context: context)
            }
        } else if currentStep < totalSteps {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                currentStep += 1
            }
        }
    }
    
    func previousStep() {
        guard canGoBack else { return }
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            if currentStep == 5 {
                // Skip back to step 4 if on conflict resolution
                currentStep = 4
                hasConflicts = false
                conflictAnalysis = nil
            } else {
                currentStep -= 1
            }
        }
    }
    
    // MARK: - Conflict Analysis
    func analyzeConflicts(context: ModelContext? = nil) async {
        guard !isLoading else { return }
        
        isLoading = true
        loadingMessage = "Analyzing your profile..."
        error = nil
        
        let request = APIService.buildRequest(from: data)
        
        do {
            let analysis = try await apiService.analyzeConflicts(request: request)
            conflictAnalysis = analysis
            
            if analysis.hasConflicts {
                hasConflicts = true
                data.recommendedGoalTime = analysis.recommendedGoalTime
                isLoading = false
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    currentStep = 5
                }
            } else {
                // No conflicts, generate plan directly
                // Don't set isLoading = false here, generatePlan will handle it
                await generatePlanInternal(context: context)
            }
            
        } catch {
            self.error = error.localizedDescription
            showError = true
            isLoading = false
        }
    }
    
    func selectPlanMode(_ mode: PlanMode) {
        selectedMode = mode
        data.planMode = mode
    }
    
    // MARK: - Plan Generation
    func generatePlan(context: ModelContext? = nil) async {
        guard !isLoading else { return }
        
        isLoading = true
        await generatePlanInternal(context: context)
    }
    
    /// Internal plan generation - called either from generatePlan or analyzeConflicts
    private func generatePlanInternal(context: ModelContext?) async {
        loadingMessage = "Crafting your personalized training plan..."
        streamingContent = ""
        error = nil
        isGeneratingPlan = true
        
        let request = APIService.buildRequest(from: data)
        
        await apiService.generatePlan(
            request: request,
            onChunk: { [weak self] chunk in
                self?.streamingContent += chunk
            },
            onComplete: { [weak self] fullContent in
                guard let self = self else { return }
                self.processGeneratedPlan(content: fullContent, context: context)
            },
            onError: { [weak self] error in
                self?.error = error.localizedDescription
                self?.showError = true
                self?.isLoading = false
            }
        )
    }
    
    private func processGeneratedPlan(content: String, context: ModelContext?) {
        // DEBUG: Log raw API content
        PlanLogger.logRawContent(content)
        
        // Parse the content into structured data
        let parsedWeeks = PlanParser.parse(
            content: content,
            startDate: data.startDate,
            raceDate: data.raceDate
        )
        
        // DEBUG: Log parsed weeks before conversion to SwiftData models
        PlanLogger.logParsedWeeks(parsedWeeks, startDate: data.startDate, raceDate: data.raceDate)
        
        // Create the TrainingPlan
        let plan = TrainingPlan(
            raceType: data.raceType,
            raceDate: data.raceDate,
            raceName: data.raceName.isEmpty ? nil : data.raceName,
            goalTime: data.goalTime.isEmpty ? nil : data.goalTime,
            currentWeeklyMileage: data.currentWeeklyMileage,
            longestRecentRun: data.longestRecentRun,
            fitnessLevel: data.fitnessLevel,
            startDate: data.startDate,
            planMode: data.planMode
        )
        
        plan.rawPlanContent = content
        
        // Create weeks and workouts
        for parsedWeek in parsedWeeks {
            let week = Week(weekNumber: parsedWeek.weekNumber, theme: parsedWeek.theme)
            
            for parsedWorkout in parsedWeek.workouts {
                let workout = Workout(
                    date: parsedWorkout.date,
                    workoutType: parsedWorkout.workoutType,
                    title: parsedWorkout.title,
                    details: parsedWorkout.details,
                    distanceKm: parsedWorkout.distanceKm,
                    durationMinutes: parsedWorkout.durationMinutes,
                    paceDescription: parsedWorkout.paceDescription
                )
                week.workouts.append(workout)
            }
            
            plan.weeks.append(week)
        }
        
        // DEBUG: Log final plan with all weeks and workouts
        PlanLogger.logPlan(plan)
        
        // Save to context if provided
        if let context = context {
            context.insert(plan)
            try? context.save()
        }
        
        generatedPlan = plan
        isLoading = false
        isComplete = true
    }
    
    // MARK: - Validation Helpers
    func validateSchedule() -> (isValid: Bool, message: String?) {
        let availableDays = 7 - data.restDays.count
        let totalSessions = data.runningDaysPerWeek + data.gymDaysPerWeek
        
        if totalSessions > availableDays && !data.doubleDaysAllowed {
            let stackingNeeded = totalSessions - availableDays
            return (
                false,
                "You need \(totalSessions) sessions but only have \(availableDays) days. Enable double days to stack \(stackingNeeded) session(s)."
            )
        }
        
        return (true, nil)
    }
}
