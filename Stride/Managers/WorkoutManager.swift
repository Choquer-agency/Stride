import Foundation
import Combine

/// Live stats for displaying during workout
struct LiveStats {
    var currentPaceSecPerKm: Double = 0
    var currentSpeedKmh: Double = 0
    var totalDistanceMeters: Double = 0
    var durationSeconds: Double = 0
    var lastKmCrossed: Int = 0
    var cadenceSpm: Double? = nil
    var heartRate: Int? = nil
    var paceDriftPercent: Double? = nil
    var baselinePace: Double? = nil
    var currentRollingPace: Double? = nil
}

/// Manages workout recording and live stats
class WorkoutManager: ObservableObject {
    @Published var isRecording: Bool = false
    @Published var isPaused: Bool = false
    @Published var currentSession: WorkoutSession?
    @Published var liveStats: LiveStats = LiveStats()
    @Published var recentSplitNotification: Split? = nil
    @Published var isTestMode: Bool = false
    @Published var isAwaitingCompletion: Bool = false // True when stopped but not yet finalized
    @Published var isBaselineTest: Bool = false // True when running a baseline fitness test
    @Published var baselineTestTargetKm: Double = 0 // Target distance for baseline test
    @Published var plannedWorkout: PlannedWorkout? = nil // Planned workout for guided mode
    @Published var intervalProgress: IntervalProgress? = nil // Progress tracker for guided workouts
    
    private var timer: Timer?
    private var lastKmCrossed: Int = 0
    private var lastKmTimestamp: Date?
    private var pausedAt: Date?
    private var totalPausedDuration: TimeInterval = 0
    let storageManager: StorageManager // Made public for WorkoutSummaryView
    
    // Pace drift tracking - memory efficient with incremental calculations
    private var baselineStartTime: Date?
    private var baselinePaceSum: Double = 0
    private var baselinePaceCount: Int = 0
    private var rollingPaceSum: Double = 0
    private var rollingPaceCount: Int = 0
    private var rollingWindowStart: Date?
    private var baselineDuration: TimeInterval = 300 // 5 minutes (adjusted for test mode)
    private var rollingWindowDuration: TimeInterval = 120 // 2 minutes (adjusted for test mode)
    
    // Background mode tracking
    private var isInBackground: Bool = false
    private var timerUpdateInterval: TimeInterval = 0.1
    
    // Test mode properties
    private var testSimulationTimer: Timer?
    private var testCurrentSpeed: Double = 0.0
    private var testCurrentDistance: Double = 0.0
    
    // Pace smoothing to prevent wild fluctuations from noisy treadmill data
    private var paceSmoother = PaceSmoother()
    
    // Sample buffering to reduce processing overhead
    private var sampleBuffer: [ParsedTreadmillSample] = []
    private let sampleBufferSize = 3 // Process every 3 samples
    private var sampleCount: Int = 0
    
    init(storageManager: StorageManager) {
        self.storageManager = storageManager
    }
    
    // MARK: - Public Methods
    
    /// Start a new workout session
    func startWorkout() {
        guard !isRecording else { return }
        
        var session = WorkoutSession(startTime: Date())
        
        // Link to planned workout if available
        if let plannedWorkout = plannedWorkout {
            session.plannedWorkoutId = plannedWorkout.id
        }
        
        currentSession = session
        isRecording = true
        isPaused = false
        lastKmCrossed = 0
        lastKmTimestamp = session.startTime
        pausedAt = nil
        totalPausedDuration = 0
        liveStats = LiveStats()
        recentSplitNotification = nil
        
        // Reset pace smoother for new workout
        paceSmoother.reset()
        
        // Reset pace drift tracking with normal durations
        baselineStartTime = session.startTime
        baselinePaceSum = 0
        baselinePaceCount = 0
        rollingPaceSum = 0
        rollingPaceCount = 0
        rollingWindowStart = nil
        baselineDuration = 300 // 5 minutes for real workout
        rollingWindowDuration = 120 // 2 minutes for real workout
        
        // Start timer to update duration with RunLoop for background reliability
        let newTimer = Timer(timeInterval: timerUpdateInterval, repeats: true) { [weak self] _ in
            self?.updateDuration()
        }
        timer = newTimer
        RunLoop.main.add(newTimer, forMode: .common)
        
        print("Workout started at \(session.startTime)")
    }
    
    /// Start a baseline fitness test workout
    func startBaselineTest(targetDistanceKm: Double) {
        guard !isRecording else { return }
        
        let session = WorkoutSession(startTime: Date())
        currentSession = session
        isRecording = true
        isPaused = false
        isBaselineTest = true
        baselineTestTargetKm = targetDistanceKm
        lastKmCrossed = 0
        lastKmTimestamp = session.startTime
        pausedAt = nil
        totalPausedDuration = 0
        liveStats = LiveStats()
        recentSplitNotification = nil
        
        // Reset pace smoother for new workout
        paceSmoother.reset()
        
        // Reset pace drift tracking (not really needed for baseline test but keep consistent)
        baselineStartTime = session.startTime
        baselinePaceSum = 0
        baselinePaceCount = 0
        rollingPaceSum = 0
        rollingPaceCount = 0
        rollingWindowStart = nil
        baselineDuration = 300
        rollingWindowDuration = 120
        
        // Start timer to update duration
        let newTimer = Timer(timeInterval: timerUpdateInterval, repeats: true) { [weak self] _ in
            self?.updateDuration()
        }
        timer = newTimer
        RunLoop.main.add(newTimer, forMode: .common)
        
        print("Baseline test started at \(session.startTime) - target: \(targetDistanceKm) km")
    }
    
    /// Start a guided workout with a planned workout
    func startGuidedWorkout(plannedWorkout: PlannedWorkout) {
        guard !isRecording else { return }
        
        let session = WorkoutSession(startTime: Date())
        currentSession = session
        isRecording = true
        isPaused = false
        lastKmCrossed = 0
        lastKmTimestamp = session.startTime
        pausedAt = nil
        totalPausedDuration = 0
        liveStats = LiveStats()
        recentSplitNotification = nil
        
        // Set up guided workout
        self.plannedWorkout = plannedWorkout
        self.intervalProgress = IntervalProgress.initial(startDistance: 0, startTime: session.startTime)
        
        // Store planned workout reference in session
        currentSession?.plannedWorkoutId = plannedWorkout.id
        currentSession?.intervalCompletions = []
        
        // Reset pace smoother for new workout
        paceSmoother.reset()
        
        // Reset pace drift tracking
        baselineStartTime = session.startTime
        baselinePaceSum = 0
        baselinePaceCount = 0
        rollingPaceSum = 0
        rollingPaceCount = 0
        rollingWindowStart = nil
        baselineDuration = 300
        rollingWindowDuration = 120
        
        // Start timer to update duration
        let newTimer = Timer(timeInterval: timerUpdateInterval, repeats: true) { [weak self] _ in
            self?.updateDuration()
        }
        timer = newTimer
        RunLoop.main.add(newTimer, forMode: .common)
        
        print("Guided workout started: \(plannedWorkout.title)")
    }
    
    /// Start a specific interval in guided mode
    func startInterval(index: Int) {
        guard let progress = intervalProgress else { return }
        
        let startDistance = liveStats.totalDistanceMeters
        let startTime = Date()
        
        intervalProgress = progress.startInterval(
            index: index,
            startDistance: startDistance,
            startTime: startTime
        )
        
        print("Started interval \(index)")
    }
    
    /// Advance to next interval in guided mode
    func advanceToNextInterval() {
        guard let workout = plannedWorkout,
              let intervals = workout.intervals,
              let progress = intervalProgress else { return }
        
        let currentIndex = progress.currentIntervalIndex
        guard currentIndex < intervals.count else { return }
        
        let currentInterval = intervals[currentIndex]
        let currentDistance = liveStats.totalDistanceMeters
        let currentTime = Date()
        
        // Record completion of current interval
        recordIntervalCompletion(
            interval: currentInterval,
            progress: progress,
            status: .completed
        )
        
        // Check if this was the last interval
        if currentIndex >= intervals.count - 1 {
            // Workout complete
            print("All intervals completed!")
            return
        }
        
        // Advance to next interval
        let nextIndex = currentIndex + 1
        intervalProgress = progress.advanceToNext(
            intervalId: currentInterval.id,
            nextIndex: nextIndex,
            currentDistance: currentDistance,
            currentTime: currentTime
        )
        
        // Auto-start the next interval
        startInterval(index: nextIndex)
    }
    
    /// Skip the current interval
    func skipCurrentInterval() {
        guard let workout = plannedWorkout,
              let intervals = workout.intervals,
              let progress = intervalProgress else { return }
        
        let currentIndex = progress.currentIntervalIndex
        guard currentIndex < intervals.count else { return }
        
        let currentInterval = intervals[currentIndex]
        let currentDistance = liveStats.totalDistanceMeters
        let currentTime = Date()
        
        // Record skip
        recordIntervalCompletion(
            interval: currentInterval,
            progress: progress,
            status: .skipped
        )
        
        // Check if this was the last interval
        if currentIndex >= intervals.count - 1 {
            print("Last interval skipped, workout ending")
            return
        }
        
        // Skip to next interval
        let nextIndex = currentIndex + 1
        intervalProgress = progress.skipInterval(
            intervalId: currentInterval.id,
            nextIndex: nextIndex,
            currentDistance: currentDistance,
            currentTime: currentTime
        )
        
        // Auto-start the next interval
        startInterval(index: nextIndex)
    }
    
    /// Record completion of an interval
    private func recordIntervalCompletion(
        interval: PlannedWorkout.Interval,
        progress: IntervalProgress,
        status: IntervalCompletionState
    ) {
        let completion = IntervalCompletion(
            intervalId: interval.id,
            startTime: progress.intervalStartTime,
            endTime: status != .skipped ? Date() : nil,
            targetPaceSecondsPerKm: interval.targetPaceSecondsPerKm,
            actualAvgPaceSecondsPerKm: status != .skipped ? calculateIntervalAvgPace(progress: progress) : nil,
            distanceMeters: progress.distanceInCurrentInterval,
            status: status
        )
        
        currentSession?.intervalCompletions?.append(completion)
    }
    
    /// Calculate average pace for the current interval
    private func calculateIntervalAvgPace(progress: IntervalProgress) -> Double? {
        guard let session = currentSession else { return nil }
        
        // Get samples from current interval
        let intervalSamples = session.recentSamples.filter {
            $0.timestamp >= progress.intervalStartTime
        }
        
        guard !intervalSamples.isEmpty else { return nil }
        
        let validPaces = intervalSamples.filter { $0.speedMps > 0.1 }.map { $0.paceSecPerKm }
        guard !validPaces.isEmpty else { return nil }
        
        return validPaces.reduce(0, +) / Double(validPaces.count)
    }
    
    /// Update interval progress with current workout data
    private func updateIntervalProgress(distance: Double, time: Date) {
        guard let progress = intervalProgress else { return }
        intervalProgress = progress.updateProgress(currentDistance: distance, currentTime: time)
    }
    
    /// Add a new sample from parsed FTMS data
    func addSample(_ parsed: ParsedTreadmillSample) {
        guard isRecording, !isPaused, currentSession != nil else { return }
        
        // Convert to workout sample
        guard let sample = parsed.toWorkoutSample() else {
            print("Could not convert parsed sample to workout sample")
            return
        }
        
        // Add to sample buffer for batch processing
        sampleBuffer.append(parsed)
        sampleCount += 1
        
        // Always add to recentSamples and check for splits (critical data)
        currentSession?.recentSamples.append(sample)
        
        // Trim to last 300 samples ONLY when we exceed the limit (batch removal)
        if let count = currentSession?.recentSamples.count, count > 350 {
            currentSession?.recentSamples.removeFirst(50)
        }
        
        // Check for km split (important milestone)
        checkForSplit(distance: sample.totalDistanceMeters, timestamp: sample.timestamp)
        
        // Update interval progress if in guided mode
        if intervalProgress != nil {
            updateIntervalProgress(distance: sample.totalDistanceMeters, time: sample.timestamp)
        }
        
        // Process buffered samples every N samples to reduce UI update frequency
        if sampleCount >= sampleBufferSize {
            processSampleBatch()
        }
    }
    
    /// Process batch of samples to reduce UI updates
    private func processSampleBatch() {
        guard !sampleBuffer.isEmpty else { return }
        
        // Use the most recent sample for UI updates
        if let latestParsed = sampleBuffer.last,
           let latestSample = latestParsed.toWorkoutSample() {
            
            // Update live stats with the latest sample
            updateLiveStats(from: latestSample)
        }
        
        // Clear buffer
        sampleBuffer.removeAll(keepingCapacity: true)
        sampleCount = 0
    }
    
    /// Pause the current workout
    func pauseWorkout() {
        guard isRecording, !isPaused else { return }
        
        isPaused = true
        pausedAt = Date()
        
        // Pause interval progress if in guided mode
        if let progress = intervalProgress {
            intervalProgress = progress.pauseProgress(pauseTime: Date())
        }
        
        // Pause test simulation if in test mode
        if isTestMode {
            testSimulationTimer?.invalidate()
            testSimulationTimer = nil
        }
        
        print("Workout paused at \(Date())")
    }
    
    /// Resume the current workout
    func resumeWorkout() {
        guard isRecording, isPaused else { return }
        
        // Calculate how long we were paused
        if let pauseStart = pausedAt {
            let pauseDuration = Date().timeIntervalSince(pauseStart)
            totalPausedDuration += pauseDuration
            
            // Adjust lastKmTimestamp to account for pause time
            if let lastKmTime = lastKmTimestamp {
                lastKmTimestamp = lastKmTime.addingTimeInterval(pauseDuration)
            }
        }
        
        isPaused = false
        pausedAt = nil
        
        // Resume interval progress if in guided mode
        if let progress = intervalProgress {
            intervalProgress = progress.resumeProgress(resumeTime: Date())
        }
        
        // Resume test simulation if in test mode
        if isTestMode {
            let newTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.generateTestSample()
            }
            testSimulationTimer = newTimer
            RunLoop.main.add(newTimer, forMode: .common)
        }
        
        print("Workout resumed at \(Date())")
    }
    
    /// Stop the current workout (prepare for completion)
    func stopWorkout() {
        guard isRecording, currentSession != nil else { return }
        
        // Process any remaining buffered samples before stopping
        processSampleBatch()
        
        // Stop timer
        timer?.invalidate()
        timer = nil
        
        // Stop test simulation if in test mode
        if isTestMode {
            testSimulationTimer?.invalidate()
            testSimulationTimer = nil
        }
        
        // Finalize session
        currentSession?.endTime = Date()
        isRecording = false
        
        // ✅ DEFENSIVE SAVE: Save immediately to prevent data loss
        // Only save if workout has meaningful data (distance > 0 or duration > 30s)
        if let session = currentSession, shouldSaveSession(session) {
            storageManager.saveWorkout(session)
            print("✅ Defensively saved workout session: \(session.id)")
        }
        
        // For baseline tests, skip completion sheet and go straight to results
        // The BaselineAssessmentView will handle showing results
        if isBaselineTest {
            isAwaitingCompletion = false
            print("Baseline test stopped. Ready for fitness calculation.")
        } else {
            isAwaitingCompletion = true // Mark as awaiting user input for normal workouts
            print("Workout stopped. Ready for completion.")
        }
    }
    
    /// Determine if a session has enough data to be worth saving
    private func shouldSaveSession(_ session: WorkoutSession) -> Bool {
        // Save if: distance > 0 OR duration > 30 seconds
        return session.totalDistanceMeters > 0 || session.durationSeconds > 30
    }
    
    /// Finalize and save the workout (called after user inputs effort/notes)
    /// Safe to call multiple times - upserts by session ID
    func finalizeWorkout() {
        guard let session = currentSession else { return }
        
        // Save/update to storage (idempotent - safe to call multiple times)
        // StorageManager.saveWorkout handles upserts by session ID
        storageManager.saveWorkout(session)
        
        // Clear the awaiting state
        isAwaitingCompletion = false
        
        print("Workout finalized. Duration: \(session.durationSeconds)s, Distance: \(session.totalDistanceMeters)m")
    }
    
    /// Clear current session (after viewing summary)
    func clearCurrentSession() {
        currentSession = nil
        liveStats = LiveStats()
        recentSplitNotification = nil
        isPaused = false
        pausedAt = nil
        totalPausedDuration = 0
        isTestMode = false
        isAwaitingCompletion = false
        isBaselineTest = false
        baselineTestTargetKm = 0
        
        // Clear guided workout data
        plannedWorkout = nil
        intervalProgress = nil
        
        // Reset pace smoother
        paceSmoother.reset()
        
        // Reset sample buffer
        sampleBuffer.removeAll()
        sampleCount = 0
        
        // Reset pace drift tracking
        baselineStartTime = nil
        baselinePaceSum = 0
        baselinePaceCount = 0
        rollingPaceSum = 0
        rollingPaceCount = 0
        rollingWindowStart = nil
    }
    
    // MARK: - Background Mode Management
    
    /// Handle app entering background
    func enterBackground() {
        isInBackground = true
        // Reduce timer frequency for performance in background
        if isRecording && !isPaused {
            adjustTimerFrequency()
        }
        print("WorkoutManager: Entered background mode")
    }
    
    /// Handle app returning to foreground
    func enterForeground() {
        isInBackground = false
        // Restore normal timer frequency
        if isRecording && !isPaused {
            adjustTimerFrequency()
        }
        print("WorkoutManager: Returned to foreground mode")
    }
    
    /// Adjust timer frequency based on workout state
    private func adjustTimerFrequency() {
        // Optimize for long runs - reduce frequency after 8km
        let distanceKm = liveStats.totalDistanceMeters / 1000.0
        
        // Determine optimal interval
        let newInterval: TimeInterval
        if isInBackground {
            newInterval = 0.5 // Less frequent in background
        } else if distanceKm > 8 {
            newInterval = 0.3 // Slightly less frequent for long runs
        } else {
            newInterval = 0.1 // Normal frequency
        }
        
        // Only restart timer if interval changed
        if newInterval != timerUpdateInterval {
            timerUpdateInterval = newInterval
            
            // Restart timer with new interval
            timer?.invalidate()
            let newTimer = Timer(timeInterval: timerUpdateInterval, repeats: true) { [weak self] _ in
                self?.updateDuration()
            }
            timer = newTimer
            RunLoop.main.add(newTimer, forMode: .common)
            
            print("Timer frequency adjusted to \(timerUpdateInterval)s")
        }
    }
    
    /// Update accumulated active time in session
    func updateAccumulatedTime() {
        guard let session = currentSession else { return }
        
        let elapsedTime = Date().timeIntervalSince(session.startTime)
        
        // Calculate current pause duration if paused
        let currentPauseDuration: TimeInterval
        if isPaused, let pauseStart = pausedAt {
            currentPauseDuration = Date().timeIntervalSince(pauseStart)
        } else {
            currentPauseDuration = 0
        }
        
        // Update accumulated active time directly
        currentSession?.accumulatedActiveTime = elapsedTime - totalPausedDuration - currentPauseDuration
    }
    
    // MARK: - Private Methods
    
    private func updateDuration() {
        guard let session = currentSession else { return }
        
        let elapsedTime = Date().timeIntervalSince(session.startTime)
        
        // If paused, add the current pause duration
        let currentPauseDuration: TimeInterval
        if isPaused, let pauseStart = pausedAt {
            currentPauseDuration = Date().timeIntervalSince(pauseStart)
        } else {
            currentPauseDuration = 0
        }
        
        // Subtract total paused time (including current pause if active)
        liveStats.durationSeconds = elapsedTime - totalPausedDuration - currentPauseDuration
        
        // Update accumulated time in session
        updateAccumulatedTime()
        
        // Adjust timer frequency for long runs
        let distanceKm = liveStats.totalDistanceMeters / 1000.0
        if distanceKm > 8 && timerUpdateInterval < 0.3 {
            adjustTimerFrequency()
        }
    }
    
    private func updateLiveStats(from sample: WorkoutSample) {
        // Apply smoothing to reduce wild fluctuations from noisy treadmill data
        let smoothed = paceSmoother.addSample(speedMps: sample.speedMps)
        
        // Use smoothed values for live display (more stable for user)
        liveStats.currentSpeedKmh = smoothed.smoothedSpeed * 3.6
        liveStats.currentPaceSecPerKm = smoothed.smoothedPace
        
        // Always use raw distance from treadmill (we trust the distance sensor)
        liveStats.totalDistanceMeters = sample.totalDistanceMeters
        liveStats.cadenceSpm = sample.cadenceSpm
        liveStats.heartRate = sample.heartRate
        
        // Update pace drift calculations
        updatePaceDrift(from: sample)
    }
    
    private func updatePaceDrift(from sample: WorkoutSample) {
        guard let session = currentSession else { return }
        guard sample.speedMps > 0.1 else { return } // Skip invalid samples
        
        let pace = sample.paceSecPerKm
        let elapsedTime = sample.timestamp.timeIntervalSince(session.startTime) - totalPausedDuration
        
        // Build baseline (first 5 minutes) - incremental calculation
        if elapsedTime <= baselineDuration {
            baselinePaceSum += pace
            baselinePaceCount += 1
            
            // If we've completed the baseline period, calculate average
            if elapsedTime >= baselineDuration && liveStats.baselinePace == nil {
                if baselinePaceCount > 0 {
                    liveStats.baselinePace = baselinePaceSum / Double(baselinePaceCount)
                }
            }
        }
        
        // Maintain rolling window (last 2 minutes) - incremental calculation
        // For simplicity, we recalculate from recent samples since they're already trimmed
        if !session.recentSamples.isEmpty {
            let windowStart = sample.timestamp.addingTimeInterval(-rollingWindowDuration)
            let windowSamples = session.recentSamples.filter { $0.timestamp >= windowStart && $0.speedMps > 0.1 }
            
            if !windowSamples.isEmpty {
                let validPaces = windowSamples.map { $0.paceSecPerKm }
                liveStats.currentRollingPace = validPaces.reduce(0, +) / Double(validPaces.count)
            }
        }
        
        // Calculate drift if we have both baseline and current pace
        if let baseline = liveStats.baselinePace,
           let current = liveStats.currentRollingPace,
           baseline > 0 {
            liveStats.paceDriftPercent = ((current - baseline) / baseline) * 100.0
        }
    }
    
    private func checkForSplit(distance: Double, timestamp: Date) {
        guard currentSession != nil else { return }
        let currentKm = Int(distance / 1000.0)
        
        // Check if we've crossed a km boundary
        if currentKm > lastKmCrossed {
            // We crossed a km boundary
            let now = timestamp
            if let lastTime = lastKmTimestamp {
                let splitTime = now.timeIntervalSince(lastTime)
                
                // Calculate aggregate metrics from samples in the last kilometer
                // Get samples from the last KM (between lastTime and now)
                let kmSamples = currentSession?.recentSamples.filter { 
                    $0.timestamp >= lastTime && $0.timestamp <= now 
                } ?? []
                
                let avgHeartRate: Int? = {
                    let heartRates = kmSamples.compactMap { $0.heartRate }
                    guard !heartRates.isEmpty else { return nil }
                    return heartRates.reduce(0, +) / heartRates.count
                }()
                
                let avgCadence: Double? = {
                    let cadences = kmSamples.compactMap { $0.cadenceSpm }
                    guard !cadences.isEmpty else { return nil }
                    return cadences.reduce(0, +) / Double(cadences.count)
                }()
                
                let avgSpeed: Double? = {
                    let speeds = kmSamples.map { $0.speedMps }
                    guard !speeds.isEmpty else { return nil }
                    return speeds.reduce(0, +) / Double(speeds.count)
                }()
                
                // Create split with all metrics
                let split = Split(
                    kmIndex: currentKm,
                    splitTimeSeconds: splitTime,
                    avgHeartRate: avgHeartRate,
                    avgCadence: avgCadence,
                    avgSpeedMps: avgSpeed
                )
                
                // Add to session
                currentSession?.splits.append(split)
                
                // Show notification
                recentSplitNotification = split
                
                // Auto-finish baseline test when target distance is reached
                if isBaselineTest && Double(currentKm) >= baselineTestTargetKm {
                    print("Baseline test target reached: \(currentKm) km")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?.stopWorkout()
                    }
                }
                
                // Clear notification after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                    self?.recentSplitNotification = nil
                }
                
                print("Split \(currentKm): \(splitTime) seconds (using \(kmSamples.count) samples)")
            }
            
            // Update tracking variables
            lastKmCrossed = currentKm
            lastKmTimestamp = now
            liveStats.lastKmCrossed = currentKm
        }
    }
    
    // MARK: - Test Mode
    
    /// Start a simulated workout for testing UI without physical treadmill
    func startTestWorkout() {
        guard !isRecording else { return }
        
        let session = WorkoutSession(startTime: Date())
        currentSession = session
        isRecording = true
        isPaused = false
        isTestMode = true
        lastKmCrossed = 0
        lastKmTimestamp = session.startTime
        pausedAt = nil
        totalPausedDuration = 0
        liveStats = LiveStats()
        recentSplitNotification = nil
        
        // Reset pace smoother for new workout
        paceSmoother.reset()
        
        // Reset pace drift tracking with shorter durations for test mode
        baselineStartTime = session.startTime
        baselinePaceSum = 0
        baselinePaceCount = 0
        rollingPaceSum = 0
        rollingPaceCount = 0
        rollingWindowStart = nil
        baselineDuration = 30 // 30 seconds for test mode
        rollingWindowDuration = 12 // 12 seconds for test mode
        
        // Initialize test variables
        testCurrentSpeed = 28.0 // Start at 10x speed for faster testing
        testCurrentDistance = 0.0
        
        // Start duration timer with RunLoop for background reliability
        let durationTimer = Timer(timeInterval: timerUpdateInterval, repeats: true) { [weak self] _ in
            self?.updateDuration()
        }
        timer = durationTimer
        RunLoop.main.add(durationTimer, forMode: .common)
        
        // Start test data simulation timer (1 Hz) with RunLoop for background reliability
        let simTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.generateTestSample()
        }
        testSimulationTimer = simTimer
        RunLoop.main.add(simTimer, forMode: .common)
        
        print("Test workout started at \(session.startTime)")
    }
    
    /// Generate a realistic test sample
    private func generateTestSample() {
        guard isRecording, var session = currentSession else { return }
        
        // Gradually increase speed over first 30 seconds, then maintain with variation
        let elapsed = Date().timeIntervalSince(session.startTime)
        
        if elapsed < 30 {
            // Warm up phase - gradually increase from 28 to 35 m/s (10x speed for testing)
            let progress = elapsed / 30.0
            testCurrentSpeed = 28.0 + (7.0 * progress)
        } else if elapsed < 90 {
            // First minute after warmup - steady pace for baseline (35 m/s with minimal variation)
            let baseSpeed = 35.0
            let variation = Double.random(in: 0.98...1.02) // ±2% variation
            testCurrentSpeed = baseSpeed * variation
        } else {
            // After 90 seconds - introduce drift (slow down slightly to show positive drift)
            let baseSpeed = 33.0 // Slower than baseline to show drift
            let variation = Double.random(in: 0.97...1.03)
            testCurrentSpeed = baseSpeed * variation
        }
        
        // Update distance (10x faster accumulation for testing)
        testCurrentDistance += testCurrentSpeed * 1.0 // 1 second interval
        
        // Generate realistic cadence
        let cadence = Double.random(in: 165...175)
        
        // Generate realistic heart rate (145-165 bpm range with natural variation)
        let heartRate = Int.random(in: 145...165)
        
        // Create parsed sample
        let parsed = ParsedTreadmillSample(
            timestamp: Date(),
            rawHex: "TEST",
            flags: 0,
            instantaneousSpeedKmh: testCurrentSpeed * 3.6,
            averageSpeedKmh: nil,
            totalDistanceMeters: testCurrentDistance,
            inclinationPercent: nil,
            rampAngleDegrees: nil,
            positiveElevationGain: nil,
            negativeElevationGain: nil,
            instantaneousPace: nil,
            averagePace: nil,
            totalEnergy: nil,
            energyPerHour: nil,
            energyPerMinute: nil,
            heartRate: heartRate,
            metabolicEquivalent: nil,
            elapsedTime: nil,
            remainingTime: nil
        )
        
        // Add sample through normal flow
        addSample(parsed)
    }
    
    /// Stop test workout
    func stopTestWorkout() {
        isTestMode = false
        testCurrentSpeed = 0.0
        testCurrentDistance = 0.0
        
        // Call regular stop to prepare for completion
        stopWorkout()
        
        print("Test workout stopped")
    }
}

