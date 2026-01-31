import SwiftUI

/// Special workout view for baseline fitness tests
struct BaselineTestWorkoutView: View {
    @ObservedObject var workoutManager: WorkoutManager
    @ObservedObject var baselineManager: BaselineAssessmentManager
    @Environment(\.dismiss) private var dismiss
    
    let goalDistance: Double?
    
    @State private var showResults = false
    @State private var calculatedAssessment: BaselineAssessment?
    
    
    
    var body: some View {
        ZStack {
            if showResults, let assessment = calculatedAssessment {
                // Results view
                resultsView(assessment: assessment)
            } else if workoutManager.isRecording {
                // Live test view
                testProgressView
            } else if let session = workoutManager.currentSession {
                // Test completed, calculating
                calculatingView(session: session)
            }
        }
        .navigationTitle("Baseline Test")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }
    
    // MARK: - Test Progress View
    
    private var testProgressView: some View {
        let progress = workoutManager.liveStats.totalDistanceMeters / 1000.0 / workoutManager.baselineTestTargetKm
        
        return ScrollView {
            VStack(spacing: 32) {
                // Instructions
                VStack(spacing: 12) {
                    Text("Run at your best sustainable effort")
                        .font(.system(size: 20, weight: .semibold))
                        .multilineTextAlignment(.center)
                    
                    Text("The test will automatically finish at \(String(format: "%.0f", workoutManager.baselineTestTargetKm)) km")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                
                // Progress bar
                VStack(spacing: 12) {
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(height: 12)
                            .cornerRadius(6)
                        
                        Rectangle()
                            .fill(Color.stridePrimary)
                            .frame(width: max(0, CGFloat(progress) * UIScreen.main.bounds.width * 0.85), height: 12)
                            .cornerRadius(6)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Text("\(String(format: "%.2f", workoutManager.liveStats.totalDistanceMeters / 1000.0)) / \(String(format: "%.0f", workoutManager.baselineTestTargetKm)) km")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 32)
                
                // Time
                VStack(spacing: 4) {
                    Text(workoutManager.liveStats.durationSeconds.toFullTimeString())
                        .font(.system(size: 56, weight: .bold))
                    Text("Time")
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(.secondary)
                }
                
                // Current Pace
                VStack(spacing: 4) {
                    Text(workoutManager.liveStats.currentPaceSecPerKm.toPaceString())
                        .font(.system(size: 72, weight: .medium))
                    Text("Current Pace (/km)")
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(.secondary)
                }
                
                // Encouragement messages based on progress
                if progress >= 0.75 {
                    Text("Almost there! Keep pushing!")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.stridePrimary)
                        .padding()
                        .background(Color.stridePrimary.opacity(0.1))
                        .cornerRadius(12)
                } else if progress >= 0.5 {
                    Text("Halfway done! Maintain your effort")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.orange)
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(12)
                } else if progress >= 0.25 {
                    Text("Great start! Stay consistent")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.blue)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                }
                
                Spacer()
                
                // Control buttons
                HStack(spacing: 20) {
                    Button(action: {
                        if workoutManager.isPaused {
                            workoutManager.resumeWorkout()
                        } else {
                            workoutManager.pauseWorkout()
                        }
                    }) {
                        Text(workoutManager.isPaused ? "Resume" : "Pause")
                            .font(.system(size: 18, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(Color.stridePrimary)
                            .foregroundColor(.strideBlack)
                            .cornerRadius(100)
                    }
                    
                    Button(action: {
                        workoutManager.stopWorkout()
                    }) {
                        Text("Finish")
                            .font(.system(size: 18, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(Color.strideBlack)
                            .foregroundColor(.stridePrimary)
                            .cornerRadius(100)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }
    
    // MARK: - Calculating View
    
    private func calculatingView(session: WorkoutSession) -> some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Calculating your fitness level...")
                .font(.system(size: 20, weight: .semibold))
            
            Text("\(String(format: "%.2f", session.totalDistanceKm)) km in \(session.durationSeconds.toTimeString())")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
        }
        .onAppear {
            calculateBaseline(session: session)
        }
    }
    
    // MARK: - Results View
    
    private func resultsView(assessment: BaselineAssessment) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Success header
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.stridePrimary)
                    
                    Text("Great work!")
                        .font(.system(size: 28, weight: .bold))
                    
                    Text("Your fitness level: VDOT \(Int(assessment.vdot))")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.stridePrimary)
                    
                    if let performance = assessment.testPerformanceDescription {
                        Text(performance)
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 40)
                
                // Training paces card
                TrainingPacesCard(
                    paces: assessment.trainingPaces,
                    vdot: assessment.vdot,
                    assessmentContext: "from your baseline test"
                )
                
                // Continue button
                Button(action: {
                    workoutManager.clearCurrentSession()
                    dismiss()
                }) {
                    Text("Save and Continue")
                        .font(.system(size: 18, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(Color.stridePrimary)
                        .foregroundColor(.strideBlack)
                        .cornerRadius(100)
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
    }
    
    // MARK: - Calculate Baseline
    
    private func calculateBaseline(session: WorkoutSession) {
        Task {
            do {
                let assessment = try await baselineManager.createFromTestWorkout(
                    session: session,
                    goalDistance: goalDistance
                )
                
                calculatedAssessment = assessment
                showResults = true
            } catch {
                print("Error calculating baseline: \(error)")
                // If error, just dismiss back
                workoutManager.clearCurrentSession()
                dismiss()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let storageManager = StorageManager()
    let hrZonesManager = HeartRateZonesManager()
    let workoutManager = WorkoutManager(storageManager: storageManager)
    let baselineManager = BaselineAssessmentManager(
        storageManager: storageManager,
        hrZonesManager: hrZonesManager
    )
    
    workoutManager.startBaselineTest(targetDistanceKm: 5.0)
    
    return NavigationStack {
        BaselineTestWorkoutView(
            workoutManager: workoutManager,
            baselineManager: baselineManager,
            goalDistance: 21.0975
        )
    }
}
