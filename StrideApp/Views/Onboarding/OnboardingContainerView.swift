import SwiftUI
import SwiftData

struct OnboardingContainerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = OnboardingViewModel()
    
    var body: some View {
        ZStack {
            // Background
            Color(.systemBackground)
                .ignoresSafeArea()
            
            if viewModel.isGeneratingPlan || viewModel.isComplete {
                // Full-screen plan generation view
                PlanGenerationView(
                    streamingContent: viewModel.streamingContent,
                    isComplete: viewModel.isComplete,
                    onViewPlan: {
                        dismiss()
                    }
                )
            } else {
                VStack(spacing: 0) {
                    // Header - centered Stride logo
                    headerView
                    
                    // Progress Indicator
                    OnboardingProgressIndicator(
                        currentStep: viewModel.currentStep,
                        totalSteps: viewModel.totalSteps,
                        showConflictStep: viewModel.hasConflicts
                    )
                    .padding(.vertical, 20)
                    
                    Divider()
                    
                    // Content
                    TabView(selection: $viewModel.currentStep) {
                        GoalStepView(data: $viewModel.data)
                            .tag(1)
                        
                        FitnessStepView(data: $viewModel.data)
                            .tag(2)
                        
                        ScheduleStepView(data: $viewModel.data, viewModel: viewModel)
                            .tag(3)
                        
                        HistoryStepView(data: $viewModel.data)
                            .tag(4)
                        
                        if viewModel.hasConflicts {
                            ConflictResolutionView(viewModel: viewModel)
                                .tag(5)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.easeInOut, value: viewModel.currentStep)
                    
                    // Navigation Buttons
                    navigationButtons
                }
                .onTapGesture {
                    dismissKeyboard()
                }
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { viewModel.showError = false }
        } message: {
            Text(viewModel.error ?? "An unknown error occurred")
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            Spacer()
            StrideLogoView(height: 32)
            Spacer()
        }
        .padding(.top, 16)
        .padding(.bottom, 4)
    }
    
    // MARK: - Navigation Buttons
    private var navigationButtons: some View {
        HStack(spacing: 16) {
            if viewModel.canGoBack {
                Button(action: {
                    dismissKeyboard()
                    viewModel.previousStep()
                }) {
                    Text("Back")
                        .font(.inter(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Capsule())
                }
                .disabled(viewModel.isLoading)
            }
            
            Button(action: {
                dismissKeyboard()
                if viewModel.currentStep == 4 || viewModel.currentStep == 5 {
                    if viewModel.currentStep == 5 {
                        Task {
                            await viewModel.generatePlan(context: modelContext)
                        }
                    } else {
                        // Step 4: Analyze conflicts (and possibly generate plan if no conflicts)
                        viewModel.nextStep(context: modelContext)
                    }
                } else {
                    viewModel.nextStep()
                }
            }) {
                Text(buttonLabel)
                    .font(.inter(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        viewModel.canGoNext && !viewModel.isLoading
                            ? Color.stridePrimary
                            : Color.stridePrimary.opacity(0.4)
                    )
                    .clipShape(Capsule())
            }
            .disabled(!viewModel.canGoNext || viewModel.isLoading)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 34)
    }
    
    private var buttonLabel: String {
        switch viewModel.currentStep {
        case 4: return "Generate Plan"
        case 5: return "Generate Plan"
        default: return "Continue"
        }
    }
    
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

#Preview {
    OnboardingContainerView()
        .modelContainer(for: TrainingPlan.self, inMemory: true)
}
