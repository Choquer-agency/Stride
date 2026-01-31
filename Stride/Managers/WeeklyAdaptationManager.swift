import Foundation
import Combine

/// Manages weekly plan adaptation process
@MainActor
class WeeklyAdaptationManager: ObservableObject {
    @Published private(set) var latestAdaptation: AdaptationRecord?
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var error: Error?
    @Published var showBanner: Bool = false
    
    private let storageManager: StorageManager
    private let trainingPlanManager: TrainingPlanManager
    private let analyzer: WeeklyAnalyzer
    private let adapter: PlanAdapter
    
    init(storageManager: StorageManager, trainingPlanManager: TrainingPlanManager) {
        self.storageManager = storageManager
        self.trainingPlanManager = trainingPlanManager
        self.analyzer = WeeklyAnalyzer(storageManager: storageManager)
        self.adapter = PlanAdapter()
        
        // Load latest adaptation on init
        loadLatestAdaptation()
    }
    
    // MARK: - Public Methods
    
    /// Run the weekly adaptation process
    func runWeeklyAdaptation() async throws {
        guard !isProcessing else {
            print("⚠️ Adaptation already in progress")
            return
        }
        
        isProcessing = true
        error = nil
        
        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }
        
        do {
            print("📊 Starting weekly adaptation analysis...")
            
            // Get current training plan
            guard let plan = trainingPlanManager.activePlan else {
                throw AdaptationError.noPlan
            }
            
            // Run analysis
            let analysis = analyzer.analyzeWeek(plan: plan)
            print("📊 Analysis complete: \(analysis.completionRate * 100)% completion, \(analysis.overallStatus)")
            
            // Generate adaptation
            let adaptationPlan = adapter.generateAdaptation(from: analysis, for: plan)
            print("📊 Generated adaptation with \(adaptationPlan.adjustments.count) adjustments")
            
            // Apply adaptation to plan
            if !adaptationPlan.adjustments.isEmpty {
                try trainingPlanManager.applyWeeklyAdaptation(adaptationPlan)
                print("✅ Adaptation applied to training plan")
            } else {
                print("ℹ️ No adjustments needed")
            }
            
            // Create and save adaptation record
            var record = AdaptationRecord(adaptationPlan: adaptationPlan)
            record.viewed = false
            record.dismissed = false
            
            try storageManager.saveAdaptationRecord(record)
            print("✅ Adaptation record saved")
            
            // Update UI
            latestAdaptation = record
            showBanner = true
            
            print("✅ Weekly adaptation complete: \(adaptationPlan.coachMessage.title)")
            
        } catch {
            self.error = error
            print("❌ Weekly adaptation failed: \(error)")
            throw error
        }
    }
    
    /// Manually trigger adaptation (for testing)
    func triggerManualAdaptation() async throws {
        print("🔧 Manual adaptation triggered")
        try await runWeeklyAdaptation()
    }
    
    /// Check if adaptation should run based on date
    func shouldRunAdaptation(referenceDate: Date = Date()) -> Bool {
        let calendar = Calendar.current
        
        // Check if today is Sunday
        let weekday = calendar.component(.weekday, from: referenceDate)
        let isSunday = (weekday == 1) // Sunday is 1 in Calendar
        
        guard isSunday else {
            return false
        }
        
        // Check if we've already run adaptation this week
        if let latest = latestAdaptation {
            let latestDate = calendar.startOfDay(for: latest.timestamp)
            let today = calendar.startOfDay(for: referenceDate)
            
            // If adaptation was already run today, don't run again
            if calendar.isDate(latestDate, inSameDayAs: today) {
                return false
            }
        }
        
        return true
    }
    
    /// Mark the latest adaptation as viewed
    func markAdaptationViewed() {
        guard var record = latestAdaptation else { return }
        record.viewed = true
        
        do {
            try storageManager.updateAdaptationRecord(record)
            latestAdaptation = record
            print("✅ Adaptation marked as viewed")
        } catch {
            print("❌ Failed to update adaptation record: \(error)")
        }
    }
    
    /// Dismiss the adaptation banner
    func dismissBanner() {
        guard var record = latestAdaptation else { return }
        record.dismissed = true
        showBanner = false
        
        do {
            try storageManager.updateAdaptationRecord(record)
            latestAdaptation = record
            print("✅ Adaptation banner dismissed")
        } catch {
            print("❌ Failed to update adaptation record: \(error)")
        }
    }
    
    /// Load the latest adaptation from storage
    func loadLatestAdaptation() {
        if let latest = storageManager.loadLatestAdaptation() {
            latestAdaptation = latest
            // Show banner if not dismissed and created within last 7 days
            if !latest.dismissed {
                let daysSinceAdaptation = Calendar.current.dateComponents([.day], from: latest.timestamp, to: Date()).day ?? 0
                showBanner = daysSinceAdaptation < 7
            }
        }
    }
    
    /// Get adaptation history
    func getAdaptationHistory() -> [AdaptationRecord] {
        return storageManager.loadAdaptationHistory()
    }
    
    // MARK: - Background Task Support
    
    /// Check and run adaptation if needed (called from background task or app launch)
    func checkAndRunIfNeeded() async {
        guard shouldRunAdaptation() else {
            print("ℹ️ Adaptation not needed at this time")
            return
        }
        
        do {
            try await runWeeklyAdaptation()
        } catch {
            print("❌ Background adaptation failed: \(error)")
        }
    }
}

// MARK: - Error Types

enum AdaptationError: LocalizedError {
    case noPlan
    case analysisFailed
    case adaptationFailed
    case noWorkouts
    
    var errorDescription: String? {
        switch self {
        case .noPlan:
            return "No active training plan found"
        case .analysisFailed:
            return "Failed to analyze workout data"
        case .adaptationFailed:
            return "Failed to adapt training plan"
        case .noWorkouts:
            return "No workouts to analyze"
        }
    }
}
