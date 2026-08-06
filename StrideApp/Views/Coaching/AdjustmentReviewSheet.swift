import SwiftUI

/// Side-by-side PLANNED → PROPOSED diff sheet. Surfaced from
/// `stride://coach/adjustment/{id}` push deep links.
///
/// Phase 3 v1: applies the diff to the local SwiftData plan via the
/// `applyToLocalPlan` closure passed in by the caller (typically PlanView,
/// which knows about the local TrainingPlan). The backend just tracks state.
struct AdjustmentReviewSheet: View {
    let adjustmentId: UUID
    /// Optional plan-mutator closure. If absent, accept just marks server-side.
    var applyToLocalPlan: ((PlanAdjustmentDTO) throws -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PlanAdjustmentViewModel

    @State private var showingRejectReason = false
    @State private var rejectReasonText = ""

    init(adjustmentId: UUID, applyToLocalPlan: ((PlanAdjustmentDTO) throws -> Void)? = nil) {
        self.adjustmentId = adjustmentId
        self.applyToLocalPlan = applyToLocalPlan
        _viewModel = StateObject(wrappedValue: PlanAdjustmentViewModel(adjustmentId: adjustmentId))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.resolved != nil {
                    resolvedState
                } else if viewModel.isLoading && viewModel.adjustment == nil {
                    ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.adjustment == nil {
                    notFoundState
                } else {
                    contentScroll
                }
            }
            .navigationTitle("Coach proposes a change")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(viewModel.resolved != nil ? "Done" : "Close") { dismiss() }
                }
            }
        }
        .task { await viewModel.load() }
        .alert("Tell coach why", isPresented: $showingRejectReason) {
            TextField("Optional", text: $rejectReasonText)
            Button("Reject", role: .destructive) {
                Task {
                    await viewModel.reject(reason: rejectReasonText.isEmpty ? nil : rejectReasonText)
                    rejectReasonText = ""
                }
            }
            Button("Cancel", role: .cancel) { rejectReasonText = "" }
        }
    }

    // MARK: - Content

    private var contentScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                expiryBanner
                summarySection
                if !viewModel.workoutEdits.isEmpty {
                    workoutEditsSection
                } else {
                    rawDiffFallback
                }
                if let err = viewModel.error {
                    Text(err).foregroundStyle(.red).font(.callout)
                }
                actionButtons
                CoachFeedbackRow(eventId: adjustmentId, loopName: "post_run_check")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
    }

    // MARK: - Sections

    private var expiryBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
            Text(viewModel.expiresIn.map { "Expires \($0)" } ?? "Pending")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(.secondary)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("From your coach")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(viewModel.summary)
                .font(.body)
                .lineSpacing(4)
        }
    }

    private var workoutEditsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Proposed changes")
                .font(.headline)
            ForEach(viewModel.workoutEdits) { edit in
                workoutDiffCard(edit)
            }
        }
    }

    private func workoutDiffCard(_ edit: WorkoutEdit) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(edit.date)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(alignment: .top, spacing: 12) {
                workoutCard(snapshot: edit.from, label: "Planned", isFrom: true)
                Image(systemName: "arrow.right")
                    .foregroundStyle(Color.stridePrimary)
                    .font(.title3)
                    .padding(.top, 24)
                workoutCard(snapshot: edit.to, label: "Proposed", isFrom: false)
            }
        }
        .padding(14)
        .background(Color.gray.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func workoutCard(snapshot: WorkoutSnapshot?, label: String, isFrom: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            if let snap = snapshot {
                Text(snap.title ?? snap.type ?? "Workout")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                if let dist = snap.distanceKm {
                    Text("\(dist, specifier: "%.1f") km")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let pace = snap.pace {
                    Text(pace).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(isFrom ? "Currently empty" : "Removed")
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(isFrom ? Color.gray.opacity(0.10) : Color.stridePrimary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var rawDiffFallback: some View {
        // Coach proposed something we can't render as a clean workout diff.
        // Show the summary prominently instead.
        VStack(alignment: .leading, spacing: 8) {
            Text("Detailed proposal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(viewModel.summary)
                .font(.body)
        }
        .padding(14)
        .background(Color.gray.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                showingRejectReason = true
            } label: {
                Text("Reject")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.actionInFlight)

            Button {
                Task {
                    await viewModel.accept(applyToLocalPlan: localApplyClosure)
                }
            } label: {
                if viewModel.actionInFlight {
                    ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 14)
                } else {
                    Text("Accept")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
            }
            .background(Color.stridePrimary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(viewModel.actionInFlight)
        }
    }

    private var localApplyClosure: (() throws -> Void)? {
        guard let apply = applyToLocalPlan, let adj = viewModel.adjustment else { return nil }
        return { try apply(adj) }
    }

    // MARK: - Final states

    private var resolvedState: some View {
        VStack(spacing: 16) {
            Image(systemName: viewModel.resolved == .accepted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(viewModel.resolved == .accepted ? Color.green : Color.gray)
            Text(viewModel.resolved == .accepted ? "Applied" : "Noted")
                .font(.title2.weight(.semibold))
            Text(viewModel.resolved == .accepted
                 ? "Coach noted the change. Your plan is updated."
                 : "Coach won't suggest the same kind of change for a few days.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var notFoundState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray").font(.system(size: 40)).foregroundStyle(.tertiary)
            Text("Not pending")
                .font(.headline)
            Text("This adjustment has already been resolved or expired.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
