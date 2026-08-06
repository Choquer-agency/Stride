import Foundation
import SwiftUI
import os.log

private let strengthLog = Logger(subsystem: "com.stride.app", category: "Strength")

/// Backing view model for the strength logging flow.
@MainActor
final class StrengthViewModel: ObservableObject {
    @Published private(set) var library: [StrengthExerciseDTO] = []
    @Published private(set) var sessions: [StrengthSessionListItemDTO] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isSubmitting: Bool = false
    @Published var error: String?

    func loadLibrary() async {
        do {
            self.library = try await APIService.shared.getStrengthLibrary()
        } catch {
            self.error = "Couldn't load exercise library."
        }
    }

    func loadSessions(days: Int = 30) async {
        do {
            self.sessions = try await APIService.shared.getStrengthSessions(days: days)
        } catch {
            // Silent — list just stays empty
        }
    }

    func quickLog(perceivedEffort: Int? = nil) async -> Bool {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await APIService.shared.logQuickStrengthSession(perceivedEffort: perceivedEffort)
            await loadSessions()
            return true
        } catch {
            self.error = "Couldn't log session."
            return false
        }
    }

    func detailedLog(sets: [[String: Any]], duration: Int? = nil, notes: String? = nil) async -> Bool {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await APIService.shared.logDetailedStrengthSession(
                sets: sets,
                durationMinutes: duration,
                notes: notes,
            )
            await loadSessions()
            return true
        } catch {
            self.error = "Couldn't log session."
            return false
        }
    }

    var libraryByCategory: [(category: String, exercises: [StrengthExerciseDTO])] {
        let order = ["posterior_chain", "hip_stability", "single_leg", "core"]
        var groups: [String: [StrengthExerciseDTO]] = [:]
        for ex in library {
            groups[ex.category, default: []].append(ex)
        }
        return order.compactMap { c in groups[c].map { (category: c, exercises: $0) } }
    }
}
