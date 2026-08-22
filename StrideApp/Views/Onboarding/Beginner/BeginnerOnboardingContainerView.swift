import SwiftUI
import SwiftData
import PostHog

// MARK: - Beginner Onboarding Container ("Create Plan – M")
/// 4-step beginner flow: goal → level → schedule → equipment. No conflict
/// step — generation fires directly after equipment. Pre-seeded with
/// MichellePreset but every answer is editable.
struct BeginnerOnboardingContainerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = OnboardingViewModel(
        flow: .beginner,
        preset: MichellePreset.seededData()
    )

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            if viewModel.isGeneratingPlan || viewModel.isComplete {
                PlanGenerationView(
                    streamingContent: viewModel.streamingContent,
                    isComplete: viewModel.isComplete,
                    onViewPlan: {
                        dismiss()
                    }
                )
            } else {
                VStack(spacing: 0) {
                    headerView

                    OnboardingProgressIndicator(
                        currentStep: viewModel.currentStep,
                        totalSteps: viewModel.totalSteps,
                        showConflictStep: false
                    )
                    .padding(.vertical, 20)

                    Divider()

                    TabView(selection: $viewModel.currentStep) {
                        BeginnerGoalStepView(data: $viewModel.data)
                            .tag(1)

                        BeginnerLevelStepView(data: $viewModel.data)
                            .tag(2)

                        BeginnerScheduleStepView(data: $viewModel.data)
                            .tag(3)

                        BeginnerEquipmentStepView(data: $viewModel.data)
                            .tag(4)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.easeInOut, value: viewModel.currentStep)

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
                let stepNames = [1: "goal", 2: "level", 3: "schedule", 4: "equipment"]
                PostHogSDK.shared.capture("beginner_onboarding_step_completed", properties: [
                    "step": viewModel.currentStep,
                    "step_name": stepNames[viewModel.currentStep] ?? "unknown",
                ])
                viewModel.nextStep(context: modelContext)
            }) {
                Text(viewModel.currentStep == viewModel.totalSteps ? "Generate Plan" : "Continue")
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

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

#Preview {
    BeginnerOnboardingContainerView()
        .modelContainer(for: TrainingPlan.self, inMemory: true)
}
