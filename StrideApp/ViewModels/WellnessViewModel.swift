import Foundation
import SwiftUI
import os.log

private let wellnessLog = Logger(subsystem: "com.stride.app", category: "Wellness")

/// Backing view model for WellnessCheckinView, PreRunCheckView, and the
/// Run-tab morning card. Owns today's state + submit + concern surfacing.
@MainActor
final class WellnessViewModel: ObservableObject {
    @Published private(set) var today: WellnessTodayDTO?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isSubmitting: Bool = false
    @Published var error: String?

    /// Set after a submit when the entry was concerning. iOS uses this to
    /// optionally route to WellnessConcernView (when `is_serious` is true the
    /// backend will also push, but the in-app card surfaces immediately).
    @Published private(set) var lastConcerningCheckinId: UUID?
    @Published private(set) var lastSerious: Bool = false

    func refreshToday() async {
        isLoading = true
        defer { isLoading = false }
        do {
            self.today = try await APIService.shared.getWellnessToday()
        } catch {
            wellnessLog.error("getWellnessToday failed: \(error.localizedDescription)")
            self.error = "Couldn't load today's wellness."
        }
    }

    func submitMorning(
        sleepQuality: Int,
        soreness: Int,
        motivation: Int,
        stress: Int,
        sorenessAreas: [String],
        notes: String?
    ) async -> Bool {
        return await submit(
            entryMethod: "morning",
            sleepQuality: sleepQuality,
            soreness: soreness,
            motivation: motivation,
            stress: stress,
            energy: nil,
            sorenessAreas: sorenessAreas,
            notes: notes
        )
    }

    func submitPreRun(
        sleepQuality: Int,
        energy: Int,
        soreness: Int
    ) async -> Bool {
        return await submit(
            entryMethod: "pre_run",
            sleepQuality: sleepQuality,
            soreness: soreness,
            motivation: nil,
            stress: nil,
            energy: energy,
            sorenessAreas: nil,
            notes: nil
        )
    }

    private func submit(
        entryMethod: String,
        sleepQuality: Int?,
        soreness: Int?,
        motivation: Int?,
        stress: Int?,
        energy: Int?,
        sorenessAreas: [String]?,
        notes: String?
    ) async -> Bool {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let resp = try await APIService.shared.submitWellnessCheckin(
                entryMethod: entryMethod,
                sleepQuality: sleepQuality,
                soreness: soreness,
                motivation: motivation,
                stress: stress,
                energy: energy,
                sorenessAreas: sorenessAreas,
                notes: notes
            )
            if resp.isConcerning {
                lastConcerningCheckinId = resp.id
                lastSerious = resp.isSerious
            } else {
                lastConcerningCheckinId = nil
                lastSerious = false
            }
            await refreshToday()
            return true
        } catch {
            wellnessLog.error("submit failed: \(error.localizedDescription)")
            self.error = "Couldn't submit check-in."
            return false
        }
    }

    var morningDoneToday: Bool {
        today?.morning != nil
    }

    var needsMorning: Bool {
        today?.needsMorning ?? true
    }

    var needsPreRun: Bool {
        today?.needsPreRun ?? true
    }
}
