import Foundation
import SwiftData

/// Manages the post-run AI coaching flow:
/// 1. Calls Claude API to generate personalized spoken summary
/// 2. Plays the response via ElevenLabs TTS (with disk cache)
@MainActor
final class PostRunCoachViewModel: ObservableObject {
    @Published var coachText: String = ""
    @Published var isGenerating = false
    @Published var isPlaying = false
    @Published var error: String?

    private let tts = ElevenLabsTTSService()
    private let api = APIService.shared

    /// Generate and speak the post-run coaching summary.
    func generateCoaching(
        result: RunResult,
        nextWorkout: (type: String, distanceKm: Double?, pace: String?, notes: String?)? = nil,
        athleteName: String = "runner",
        goalRace: String? = nil,
        trainingBlock: String? = nil,
        planWeek: Int? = nil,
        totalPlanWeeks: Int? = nil
    ) {
        isGenerating = true
        coachText = ""
        error = nil

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        // Build splits data
        let splits = result.kmSplits.map { split in
            PostRunSplitData(
                kilometer: split.kilometer,
                pace: split.pace,
                time: split.time,
                isFastest: split.isFastest
            )
        }

        // Calculate pace consistency (coefficient of variation)
        let paceConsistency = calculatePaceConsistency(splits: result.kmSplits)

        // Check for negative split
        let negativeSplit = checkNegativeSplit(splits: result.kmSplits)

        // Build tomorrow's workout notes
        var tomorrowNotes: String?
        if let week = planWeek, let total = totalPlanWeeks {
            tomorrowNotes = "Week \(week) of \(total)"
        }
        if let notes = nextWorkout?.notes {
            tomorrowNotes = [tomorrowNotes, notes].compactMap { $0 }.joined(separator: ". ")
        }

        // Determine what prerecorded alerts were delivered
        let splitCount = result.kmSplits.count
        var alertsSummary = "Kilometer splits 1 through \(splitCount) with pace and total time"
        if result.kmSplits.contains(where: { $0.isFastest }) {
            alertsSummary += ", fastest split callout"
        }

        let request = PostRunCoachRequest(
            runDate: dateFormatter.string(from: Date()),
            runType: result.plannedWorkoutType?.rawValue ?? "easy run",
            totalDistanceKm: result.distanceKm,
            totalTime: result.durationDisplay,
            avgPace: result.avgPaceDisplay,
            kmSplits: splits,
            paceConsistencyPct: paceConsistency,
            negativeSplit: negativeSplit,
            avgHr: nil,
            maxHr: nil,
            avgCadence: nil,
            elevationGain: result.elevationGainMeters,
            prFlag: false,
            prDetail: nil,
            weeklyDistanceKm: nil,
            weeklyGoalKm: nil,
            streakDays: nil,
            monthlyDistanceKm: nil,
            lastSimilarRunPace: nil,
            lastSimilarRunDate: nil,
            trend: nil,
            tomorrowType: nextWorkout?.type,
            tomorrowDistanceKm: nextWorkout?.distanceKm,
            tomorrowTargetPace: nextWorkout?.pace,
            tomorrowNotes: tomorrowNotes,
            athleteName: athleteName,
            habitsToReinforce: "always forgets to stretch",
            trainingBlock: trainingBlock,
            goalRace: goalRace,
            prerecordedAlertsDelivered: alertsSummary
        )

        Task {
            await api.postRunCoach(
                request: request,
                onChunk: { [weak self] chunk in
                    self?.coachText += chunk
                },
                onComplete: { [weak self] fullText in
                    guard let self else { return }
                    self.isGenerating = false
                    // Play the full coaching summary via TTS
                    self.isPlaying = true
                    self.tts.speak(fullText)
                    // TTS will finish asynchronously — mark playing done after estimated time
                    let estimatedDuration = Double(fullText.count) / 15.0 // ~15 chars/sec speech
                    DispatchQueue.main.asyncAfter(deadline: .now() + estimatedDuration) {
                        self.isPlaying = false
                    }
                },
                onError: { [weak self] err in
                    self?.isGenerating = false
                    self?.error = err.localizedDescription
                }
            )
        }
    }

    func stopPlayback() {
        tts.stopSpeaking()
        isPlaying = false
    }

    // MARK: - Helpers

    private func calculatePaceConsistency(splits: [KilometerSplit]) -> Double? {
        guard splits.count >= 2 else { return nil }

        let paces = splits.compactMap { parsePaceToSeconds($0.pace) }
        guard paces.count >= 2 else { return nil }

        let mean = paces.reduce(0, +) / Double(paces.count)
        guard mean > 0 else { return nil }

        let variance = paces.reduce(0) { $0 + pow($1 - mean, 2) } / Double(paces.count)
        let stdDev = sqrt(variance)
        return (stdDev / mean) * 100.0 // Coefficient of variation as percentage
    }

    private func checkNegativeSplit(splits: [KilometerSplit]) -> Bool {
        guard splits.count >= 2 else { return false }

        let midpoint = splits.count / 2
        let firstHalf = splits[0..<midpoint].compactMap { parsePaceToSeconds($0.pace) }
        let secondHalf = splits[midpoint...].compactMap { parsePaceToSeconds($0.pace) }

        guard !firstHalf.isEmpty, !secondHalf.isEmpty else { return false }

        let avgFirst = firstHalf.reduce(0, +) / Double(firstHalf.count)
        let avgSecond = secondHalf.reduce(0, +) / Double(secondHalf.count)

        return avgSecond < avgFirst // Faster second half = negative split
    }

    private func parsePaceToSeconds(_ pace: String) -> Double? {
        let parts = pace.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }
}
