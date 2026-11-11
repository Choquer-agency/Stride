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
        totalPlanWeeks: Int? = nil,
        speak: Bool = true,
        onComplete: ((String) -> Void)? = nil
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
        let phaseExecution = measuredPhaseExecution(result)
        let paceConsistency = phaseExecution == nil ? calculatePaceConsistency(splits: result.kmSplits) : nil

        // Check for negative split
        let negativeSplit = phaseExecution == nil && checkNegativeSplit(splits: result.kmSplits)

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
        var alertsSummary = splitCount > 0
            ? "Kilometer splits 1 through \(splitCount) with pace and total time"
            : "No kilometer split alerts recorded"
        if result.kmSplits.contains(where: { $0.isFastest }) {
            alertsSummary += ", fastest split callout"
        }

        let request = PostRunCoachRequest(
            runDate: dateFormatter.string(from: result.completedAt),
            runType: result.isPlannedRun ? (result.plannedWorkoutType?.rawValue ?? "planned run") : "free run",
            totalDistanceKm: result.distanceKm,
            totalTime: result.durationDisplay,
            avgPace: result.avgPaceDisplay,
            kmSplits: splits,
            plannedWorkoutTitle: result.plannedWorkoutTitle,
            plannedWorkoutDetails: result.plannedWorkoutDetails,
            phaseExecution: phaseExecution,
            paceConsistencyPct: paceConsistency,
            negativeSplit: negativeSplit,
            avgHr: result.avgHeartRate,
            maxHr: result.maxHeartRate,
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
            habitsToReinforce: nil,
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
                    onComplete?(fullText)
                    guard let self else { return }
                    self.isGenerating = false
                    self.coachText = fullText
                    guard speak else { return }
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

    /// Attribute observed speed to the workout's phases, instead of treating
    /// arbitrary kilometer boundaries as separate efforts.
    private func measuredPhaseExecution(_ result: RunResult) -> String? {
        var phases = IntervalWorkoutParser.parse(result.plannedWorkoutDetails)
        if phases.isEmpty {
            phases = IntervalWorkoutParser.progression(result.plannedWorkoutDetails,
                totalKm: result.targetDistanceKm)
        }
        if phases.isEmpty {
            phases = IntervalWorkoutParser.strides(result.plannedWorkoutDetails,
                totalKm: result.targetDistanceKm, easyPace: result.targetPaceDescription)
        }
        let samples = result.speedSamples.sorted { $0.t < $1.t }
        guard !phases.isEmpty else { return nil }
        let missingData = "No reliable phase-level speed samples. Do not judge interval adherence from kilometer splits."
        guard samples.count >= 2 else { return missingData }

        var measured = Array(repeating: (seconds: 0.0, km: 0.0), count: phases.count)
        var index = 0
        var phaseStartTime = 0.0
        var phaseDistance = 0.0
        for pair in zip(samples, samples.dropFirst()) {
            let (a, b) = pair
            let gap = b.t - a.t
            guard gap > 0, gap <= 5, a.kmh > 0, a.kmh < 35 else { continue }
            var time = a.t
            while time < b.t, index < phases.count {
                let phase = phases[index]
                if let duration = phase.durationSec, time - phaseStartTime >= duration - 0.001 {
                    phaseStartTime += duration
                    phaseDistance = 0
                    index += 1
                    continue
                }
                if let distance = phase.distanceKm, phaseDistance >= distance - 0.00001 {
                    phaseStartTime = time
                    phaseDistance = 0
                    index += 1
                    continue
                }
                let remainingTime = phase.durationSec.map { max(0, $0 - (time - phaseStartTime)) } ?? .infinity
                let remainingDistanceTime = phase.distanceKm.map { max(0, ($0 - phaseDistance) * 3600 / a.kmh) } ?? .infinity
                let step = min(b.t - time, remainingTime, remainingDistanceTime)
                guard step > 0.001 else { break }
                measured[index].seconds += step
                let km = a.kmh * step / 3600
                measured[index].km += km
                phaseDistance += km
                time += step
            }
        }
        let lines = phases.enumerated().compactMap { i, phase -> String? in
            let actual = measured[i]
            guard actual.seconds >= 5, actual.km > 0.005 else { return nil }
            let pace = Int((actual.seconds / actual.km).rounded())
            return "- \(phase.displayLabel): target \(phase.paceText)/km; measured \(pace / 60):\(String(format: "%02d", pace % 60))/km over \(Int(actual.seconds.rounded())) seconds"
        }
        return lines.isEmpty ? missingData : lines.joined(separator: "\n")
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
