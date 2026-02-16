import Foundation
import SwiftUI

@MainActor
class PerformanceAnalysisViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var streamingContent: String = ""
    @Published var isGenerating = false
    @Published var isComplete = false
    @Published var error: String?
    @Published var showError = false
    @Published var suggestedEditInstruction: String?

    // MARK: - Dependencies
    let plan: TrainingPlan
    private let apiService = APIService.shared

    // MARK: - Initialization
    init(plan: TrainingPlan) {
        self.plan = plan
    }

    // MARK: - Validation
    var hasEnoughData: Bool {
        plan.completedWorkouts >= 3
    }

    // MARK: - Start Analysis
    func startAnalysis() async {
        guard !isGenerating else { return }

        isGenerating = true
        streamingContent = ""
        error = nil
        isComplete = false
        suggestedEditInstruction = nil

        let request = APIService.buildAnalysisRequest(from: plan)

        await apiService.analyzePerformance(
            request: request,
            onChunk: { [weak self] chunk in
                self?.streamingContent += chunk
            },
            onComplete: { [weak self] fullContent in
                guard let self = self else { return }
                self.extractSuggestedAdjustment(from: fullContent)
                self.isGenerating = false
                self.isComplete = true
            },
            onError: { [weak self] error in
                self?.error = error.localizedDescription
                self?.showError = true
                self?.isGenerating = false
            }
        )
    }

    // MARK: - Extract Suggested Adjustment
    private func extractSuggestedAdjustment(from content: String) {
        let marker = "SUGGESTED PLAN ADJUSTMENT:"
        guard let range = content.range(of: marker) else { return }

        let afterMarker = content[range.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if it's "None" (no adjustment needed)
        if afterMarker.lowercased().hasPrefix("none") {
            suggestedEditInstruction = nil
        } else if !afterMarker.isEmpty {
            suggestedEditInstruction = afterMarker
        }
    }
}
