import Foundation
import SwiftUI
import os.log

private let adjLog = Logger(subsystem: "com.stride.app", category: "PlanAdjustment")

/// Backing view model for `AdjustmentReviewSheet`.
///
/// In Phase 3 v1 the actual plan structure lives only in iOS SwiftData
/// (TrainingPlan/Week/Workout). The backend tracks PROPOSED/ACCEPTED/REJECTED
/// state but does not mutate the plan. So `accept()` here:
///   1. Applies the structured_diff to the local plan via the closure caller passes in
///   2. Marks the row accepted server-side via /api/coach/plan/accept-adjustment
///
/// `reject()` is a single API call — no local plan mutation required.
@MainActor
final class PlanAdjustmentViewModel: ObservableObject {
    @Published private(set) var adjustment: PlanAdjustmentDTO?
    @Published private(set) var isLoading = false
    @Published private(set) var actionInFlight = false
    @Published var error: String?
    @Published private(set) var resolved: Resolution?

    enum Resolution { case accepted, rejected }

    private let adjustmentId: UUID

    init(adjustmentId: UUID) {
        self.adjustmentId = adjustmentId
    }

    /// Refresh from /api/coach/plan/pending-adjustments (server doesn't expose
    /// a single-row GET in v2 — we filter the pending list).
    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let pending = try await APIService.shared.pendingAdjustments()
            self.adjustment = pending.first(where: { $0.id == adjustmentId })
            if self.adjustment == nil {
                self.error = "Adjustment not found or already resolved."
            }
        } catch {
            self.error = "Couldn't load adjustment."
            adjLog.error("load failed: \(error.localizedDescription)")
        }
    }

    /// Accept. The optional `applyToLocalPlan` closure runs first — caller
    /// applies the structured_diff to the local SwiftData TrainingPlan there.
    /// If the closure throws, we abort and surface the error rather than
    /// marking the row accepted server-side.
    func accept(applyToLocalPlan: (() throws -> Void)? = nil) async {
        actionInFlight = true
        defer { actionInFlight = false }

        do {
            try applyToLocalPlan?()
        } catch {
            self.error = "Couldn't apply the change locally — \(error.localizedDescription)"
            return
        }

        do {
            try await APIService.shared.acceptAdjustment(id: adjustmentId)
            resolved = .accepted
        } catch {
            self.error = "Saved locally but couldn't sync. Try again."
            adjLog.error("accept API failed: \(error.localizedDescription)")
        }
    }

    func reject(reason: String? = nil) async {
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            try await APIService.shared.rejectAdjustment(id: adjustmentId, reason: reason)
            resolved = .rejected
        } catch {
            self.error = "Couldn't reject. Try again."
            adjLog.error("reject API failed: \(error.localizedDescription)")
        }
    }

    var workoutEdits: [WorkoutEdit] {
        adjustment?.structuredDiff.workoutEdits ?? []
    }

    var summary: String {
        adjustment?.summaryText ?? ""
    }

    var expiresIn: String? {
        guard let expires = adjustment?.expiresAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: expires, relativeTo: Date())
    }
}
