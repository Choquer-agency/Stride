import SwiftUI

/// Settings view for baseline fitness assessment management
struct BaselineSettingsView: View {
    @ObservedObject var baselineManager: BaselineAssessmentManager
    @ObservedObject var workoutManager: WorkoutManager
    
    @State private var showAssessmentView = false
    @State private var showFeedbackSheet = false
    @State private var selectedFeedback: PaceFeedback.FeedbackRating = .justRight
    @State private var feedbackNotes: String = ""
    @State private var showVDOTInfo = false
    
    
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let assessment = baselineManager.currentAssessment {
                    // Current Assessment Section
                    currentAssessmentSection(assessment: assessment)
                    
                    // Training Paces Card
                    TrainingPacesCard(
                        paces: assessment.trainingPaces,
                        vdot: assessment.vdot,
                        assessmentContext: "from your \(assessment.method.displayName.lowercased())"
                    )
                    
                    // Feedback Section
                    feedbackSection(assessment: assessment)
                    
                    // Retake Assessment Button
                    Button(action: {
                        showAssessmentView = true
                    }) {
                        Label("Retake Baseline Test", systemImage: "arrow.clockwise")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(.systemGray6))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                    }
                    
                    // Assessment History
                    assessmentHistorySection()
                    
                } else {
                    // No Assessment State
                    noAssessmentSection()
                }
                
                // Info Section
                infoSection()
            }
            .padding()
        }
        .navigationTitle("Baseline Assessment")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAssessmentView) {
            BaselineAssessmentView(
                baselineManager: baselineManager,
                workoutManager: workoutManager,
                goalDistance: nil
            )
        }
        .sheet(isPresented: $showFeedbackSheet) {
            feedbackSheetContent()
        }
        .sheet(isPresented: $showVDOTInfo) {
            VDOTInfoSheet()
        }
    }
    
    // MARK: - Current Assessment Section
    
    private func currentAssessmentSection(assessment: BaselineAssessment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Current Fitness")
                    .font(.system(size: 20, weight: .bold))
                
                Spacer()
                
                Button(action: {
                    showVDOTInfo = true
                }) {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.secondary)
                }
            }
            
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("VDOT")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Text("\(Int(assessment.vdot))")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.stridePrimary)
                    }
                    
                    Text(assessment.method.displayName)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    
                    Text(assessment.assessmentDate, style: .date)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if let performance = assessment.testPerformanceDescription {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(performance)
                            .font(.system(size: 14, weight: .medium))
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
    
    // MARK: - Feedback Section
    
    private func feedbackSection(assessment: BaselineAssessment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How do these paces feel?")
                .font(.system(size: 16, weight: .semibold))
            
            HStack(spacing: 12) {
                feedbackButton(rating: .tooEasy, icon: "hare", label: "Too Easy")
                feedbackButton(rating: .justRight, icon: "checkmark.circle", label: "Just Right")
                feedbackButton(rating: .tooHard, icon: "tortoise", label: "Too Hard")
            }
            
            Text("Your feedback helps us improve your training plan")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
    
    private func feedbackButton(rating: PaceFeedback.FeedbackRating, icon: String, label: String) -> some View {
        Button(action: {
            selectedFeedback = rating
            showFeedbackSheet = true
        }) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(.primary)
                
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Assessment History Section
    
    private func assessmentHistorySection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Assessment History")
                .font(.system(size: 16, weight: .semibold))
            
            let assessments = baselineManager.getAllAssessments().prefix(5)
            
            if assessments.isEmpty {
                Text("No assessment history yet")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(assessments), id: \.id) { assessment in
                        assessmentHistoryRow(assessment: assessment)
                        
                        if assessment.id != assessments.last?.id {
                            Divider()
                        }
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(12)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
    
    private func assessmentHistoryRow(assessment: BaselineAssessment) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(assessment.assessmentDate, style: .date)
                    .font(.system(size: 14, weight: .medium))
                
                Text(assessment.method.displayName)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("VDOT \(Int(assessment.vdot))")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.stridePrimary)
        }
        .padding()
    }
    
    // MARK: - No Assessment Section
    
    private func noAssessmentSection() -> some View {
        VStack(spacing: 20) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Baseline Assessment")
                .font(.system(size: 20, weight: .semibold))
            
            Text("Complete a baseline assessment to get personalized training paces and accurate race predictions.")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: {
                showAssessmentView = true
            }) {
                Text("Start Assessment")
                    .font(.system(size: 18, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(Color.stridePrimary)
                    .foregroundColor(.strideBlack)
                    .cornerRadius(100)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(maxHeight: .infinity)
    }
    
    // MARK: - Info Section
    
    private func infoSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About Baseline Assessment")
                .font(.system(size: 16, weight: .semibold))
            
            Text("Your baseline fitness assessment determines your current running fitness level (VDOT). This allows Stride to calculate personalized training paces that optimize your improvement while preventing overtraining.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            Text("We recommend retaking your assessment every 8-12 weeks to track progress and update your training paces.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
    
    // MARK: - Feedback Sheet
    
    private func feedbackSheetContent() -> some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("How do these paces feel?")
                    .font(.system(size: 20, weight: .semibold))
                    .padding(.top)
                
                Text("Your rating: \(selectedFeedback.displayName)")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Additional notes (optional)")
                        .font(.system(size: 14, weight: .medium))
                    
                    TextEditor(text: $feedbackNotes)
                        .frame(height: 120)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
                .padding(.horizontal)
                
                Spacer()
                
                Button(action: {
                    submitFeedback()
                }) {
                    Text("Submit Feedback")
                        .font(.system(size: 18, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(Color.stridePrimary)
                        .foregroundColor(.strideBlack)
                        .cornerRadius(100)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Pace Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        showFeedbackSheet = false
                        feedbackNotes = ""
                    }
                }
            }
        }
    }
    
    private func submitFeedback() {
        Task {
            do {
                let notes = feedbackNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                try await baselineManager.savePaceFeedback(
                    rating: selectedFeedback,
                    notes: notes.isEmpty ? nil : notes
                )
                
                showFeedbackSheet = false
                feedbackNotes = ""
            } catch {
                print("Error saving feedback: \(error)")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let storageManager = StorageManager()
    let hrZonesManager = HeartRateZonesManager()
    let baselineManager = BaselineAssessmentManager(
        storageManager: storageManager,
        hrZonesManager: hrZonesManager
    )
    let workoutManager = WorkoutManager(storageManager: storageManager)
    
    return NavigationStack {
        BaselineSettingsView(
            baselineManager: baselineManager,
            workoutManager: workoutManager
        )
    }
}
