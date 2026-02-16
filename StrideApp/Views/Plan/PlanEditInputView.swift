import SwiftUI
import SwiftData

struct PlanEditInputView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PlanEditViewModel

    let plan: TrainingPlan
    let initialInstructions: String?

    init(plan: TrainingPlan, initialInstructions: String? = nil) {
        self.plan = plan
        self.initialInstructions = initialInstructions
        _viewModel = StateObject(wrappedValue: PlanEditViewModel(plan: plan, initialInstructions: initialInstructions))
    }

    var body: some View {
        Group {
            if viewModel.isGenerating || viewModel.isComplete {
                PlanGenerationView(
                    streamingContent: viewModel.streamingContent,
                    isComplete: viewModel.isComplete,
                    onViewPlan: { dismiss() },
                    isEditMode: true
                )
            } else {
                editInputContent
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { }
        } message: {
            Text(viewModel.error ?? "Something went wrong")
        }
    }

    // MARK: - Edit Input Content
    private var editInputContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                }

                Spacer()

                StrideLogoView(height: 28)

                Spacer()

                // Invisible spacer for centering
                Color.clear.frame(width: 32, height: 32)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 20)

            // Title
            Text("EDIT YOUR PLAN")
                .font(.barlowCondensed(size: 28, weight: .bold))
                .padding(.bottom, 4)

            Text("Describe what you'd like to change")
                .font(.inter(size: 14))
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)

            Divider()
                .padding(.horizontal, 20)

            // Plan info badge
            HStack(spacing: 8) {
                Image(systemName: "figure.run")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.stridePrimary)

                Text(plan.raceName ?? plan.raceType.displayName)
                    .font(.inter(size: 13, weight: .medium))

                if let goalTime = plan.goalTime {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(goalTime)
                        .font(.barlowCondensed(size: 14, weight: .medium))
                }
            }
            .foregroundStyle(.primary.opacity(0.8))
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(Color(.tertiarySystemBackground))
            .clipShape(Capsule())
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Text editor
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $viewModel.editInstructions)
                    .font(.inter(size: 15))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(minHeight: 140)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topLeading) {
                        if viewModel.editInstructions.isEmpty {
                            Text("e.g. \"Remove Tuesday runs and add more distance to Saturday long runs\" or \"Reduce total weekly volume by 20%\"")
                                .font(.inter(size: 15))
                                .foregroundStyle(.tertiary)
                                .padding(16)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .padding(.horizontal, 20)

            Spacer()

            // Submit button
            GeometryReader { geometry in
                let buttonWidth = geometry.size.width * 191.0 / 402.0

                HStack {
                    Spacer()
                    Button {
                        Task {
                            await viewModel.submitEdit(context: modelContext)
                        }
                    } label: {
                        Text("Update Plan")
                            .font(.inter(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: buttonWidth)
                            .padding(.vertical, 18)
                            .background(viewModel.canSubmit ? Color.stridePrimary : Color.gray.opacity(0.4))
                            .clipShape(Capsule())
                    }
                    .disabled(!viewModel.canSubmit)
                    Spacer()
                }
            }
            .frame(height: 56)
            .padding(.bottom, 40)
        }
        .background(Color(.systemBackground))
    }
}
