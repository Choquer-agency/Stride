import Foundation
import AVFoundation
import os.log

private let voiceLog = Logger(subsystem: "com.stride.app", category: "VoiceCoach")

/// Voice coaching service that announces splits, pace changes, encouragement, and run state.
/// Uses pre-recorded bundled audio for static phrases and ElevenLabs API (with disk cache) for dynamic values.
final class VoiceCoachService {
    private let tts = ElevenLabsTTSService.shared
    private var settings: VoiceCoachSettings

    // Debounce: prevent rapid-fire pace zone alerts
    private var lastPaceZoneAnnouncement: Date = .distantPast
    private let paceZoneDebounceInterval: TimeInterval = 30.0
    private var lastAnnouncedPaceZone: PaceZone?

    // Halfway tracking
    private var hasAnnouncedHalfway = false

    // Time checkpoint tracking
    private var hasAnnounced30Min = false
    private var hasAnnounced60Min = false

    // Encouragement tracking
    private var lastEncouragementTime: Date = .distantPast
    private let encouragementInterval: TimeInterval = 300.0 // 5 minutes between encouragements
    private var encouragementIndex = 0

    // Countdown tracking
    private var hasPlayedCountdown = false

    init() {
        self.settings = VoiceCoachSettings.load()
    }

    // MARK: - Voice Configuration

    func setVoiceId(_ id: String) {
        tts.voiceId = id
    }

    // MARK: - Settings

    func reloadSettings() {
        settings = VoiceCoachSettings.load()
    }

    // MARK: - 1. PRE-RUN Announcements

    /// Play countdown before run starts: "Starting in three... two... one... let's go."
    func announceCountdown() {
        guard settings.isEnabled, settings.announceCountdown else { return }
        guard !hasPlayedCountdown else { return }
        hasPlayedCountdown = true
        tts.speakSequence([.bundled("countdown_2", fallbackText: "Starting in three... two... one... let's go.")])
    }

    /// Announce workout type intro (e.g., "This is a tempo run.")
    func announceWorkoutType(_ type: WorkoutType) {
        guard settings.isEnabled, settings.announceWorkoutPreview else { return }

        let clipName: String?
        switch type {
        case .recovery:     clipName = "type_recovery"
        case .longRun:      clipName = "type_long_run"
        case .intervals:    clipName = "type_interval"
        case .tempoRun:     clipName = "type_tempo"
        case .easyRun:      clipName = "type_recovery"
        default:            clipName = nil
        }

        if let name = clipName {
            tts.speakSequence([.bundled(name)])
        }
    }

    /// Announce workout preview with target distance.
    func announceWorkoutPreview(workoutName: String, targetDistanceKm: Double?) {
        guard settings.isEnabled, settings.announceWorkoutPreview else { return }

        var clips: [AudioClip] = [.bundled("todays_workout"), .text(workoutName)]

        if let dist = targetDistanceKm, dist > 0 {
            let distInt = Int(dist)
            clips.append(.bundled("target_distance_today"))
            if distInt > 0 && distInt <= 60 {
                clips.append(.bundled("num_\(distInt)"))
            } else {
                clips.append(.text("\(distInt)"))
            }
            clips.append(.bundled("kilometers"))
        }

        tts.speakSequence(clips)
    }

    // MARK: - 2. MID-RUN Announcements

    /// Announce a completed kilometer/mile split using bundled + cached clips.
    /// Progressive detail:
    ///   - KM 1: km + pace + total time
    ///   - KM 2+: km + pace + average pace + total time
    func announceKmSplit(kilometer: Int, paceSecPerKm: Double, totalElapsedTime: TimeInterval, avgPaceSecPerKm: Double? = nil) {
        guard settings.isEnabled, settings.announceKmSplits else { return }

        let unitPrefix = settings.paceUnit == .km ? "km" : "mile"
        let unitName = settings.paceUnit == .km ? "Kilometer" : "Mile"

        // 100% bundled clips — zero API calls
        // No "per kilometer" on split pace — it's implied
        var clips: [AudioClip] = [
            .bundled("\(unitPrefix)_\(kilometer)", fallbackText: "\(unitName) \(kilometer)."),
            .bundled("pace", fallbackText: "Pace:"),
        ]
        clips.append(contentsOf: paceClips(secondsPerKm: paceSecPerKm, includeUnit: false))

        // KM 2+: add average pace (also without "per kilometer")
        if kilometer >= 2, let avgPace = avgPaceSecPerKm {
            clips.append(.bundled("average_pace", fallbackText: "Average pace so far:"))
            clips.append(contentsOf: paceClips(secondsPerKm: avgPace, includeUnit: false))
        }

        clips.append(.bundled("total_time", fallbackText: "Total time:"))
        clips.append(contentsOf: timeClips(totalElapsedTime))

        tts.speakSequence(clips)
    }

    /// Announce a pace zone change (debounced to max once per 30 seconds).
    func announcePaceZoneChange(from oldZone: PaceZone, to newZone: PaceZone) {
        guard settings.isEnabled, settings.announcePaceZone else { return }
        guard newZone != .noTarget else { return }

        let now = Date()
        guard now.timeIntervalSince(lastPaceZoneAnnouncement) >= paceZoneDebounceInterval else { return }
        guard newZone != lastAnnouncedPaceZone else { return }

        lastPaceZoneAnnouncement = now
        lastAnnouncedPaceZone = newZone

        let clip: (name: String, fallback: String)?
        switch newZone {
        case .tooSlow:      clip = ("pace_too_slow", "You're falling behind target pace. Pick it up.")
        case .slightlySlow: clip = ("pace_slightly_slow", "Slightly behind pace. Try to push a bit.")
        case .tooFast:      clip = ("pace_too_fast", "Running too fast. Slow down to conserve energy.")
        case .slightlyFast: clip = nil
        case .onPace:
            if oldZone == .tooSlow || oldZone == .slightlySlow || oldZone == .tooFast {
                clip = ("pace_back_on", "Back on pace. Nice.")
            } else {
                clip = nil
            }
        case .noTarget:     clip = nil
        }

        if let c = clip {
            tts.speakSequence([.bundled(c.name, fallbackText: c.fallback)])
        }
    }

    /// Announce pace alert with specific values (uses API + cache for the values).
    func announcePaceAlert(currentPace: Double, targetPace: Double, isBehind: Bool) {
        guard settings.isEnabled, settings.announcePaceZone else { return }

        // Use bundled pace zone clip + composed pace clips
        var clips: [AudioClip] = []
        if isBehind {
            clips.append(.bundled("pace_slightly_slow", fallbackText: "Slightly behind pace."))
        } else {
            clips.append(.bundled("pace_too_fast", fallbackText: "Running too fast."))
        }
        clips.append(contentsOf: paceClips(secondsPerKm: currentPace))
        tts.speakSequence(clips)
    }

    // MARK: - Progress Milestones

    /// Track which distance milestones have been announced
    private var announcedDistanceMilestones: Set<Int> = []
    /// Track which time milestones have been announced (in minutes)
    private var announcedTimeMilestones: Set<Int> = []

    /// Check and announce all progress milestones. Call this on every data update.
    /// Handles: distance halfway, "X km to go", time halfway, time checkpoints.
    func checkProgressMilestones(
        currentDistanceKm: Double,
        elapsedTime: TimeInterval,
        targetDistanceKm: Double?,
        targetDurationMinutes: Int?
    ) {
        guard settings.isEnabled, settings.announceHalfway else { return }

        // ── Distance-based milestones ──
        if let target = targetDistanceKm, target > 0 {
            let remaining = target - currentDistanceKm

            // Halfway
            if !hasAnnouncedHalfway && currentDistanceKm >= target / 2.0 {
                hasAnnouncedHalfway = true
                let doneKm = Int(currentDistanceKm.rounded())
                let toGoKm = Int(remaining.rounded())

                var clips: [AudioClip] = [
                    .bundled("encourage_halfway", fallbackText: "Halfway home."),
                ]
                // "10k down, 10k to go"
                if doneKm > 0 && doneKm <= 60 {
                    clips.append(.bundled("num_\(doneKm)"))
                    clips.append(.bundled("kilometers"))
                }
                if toGoKm > 0 && toGoKm <= 60 {
                    clips.append(.bundled("num_\(toGoKm)"))
                    clips.append(.bundled("kilometers_to_go", fallbackText: "kilometers to go."))
                }
                clips.append(.bundled("time_label", fallbackText: "Time:"))
                clips.append(contentsOf: timeClips(elapsedTime))
                tts.speakSequence(clips)
            }

            // "Only X km to go" at 75% and 90% (for longer runs 10k+)
            if target >= 10 {
                let seventyFivePct = Int(target * 0.75)
                if !announcedDistanceMilestones.contains(75) && Int(currentDistanceKm) >= seventyFivePct {
                    announcedDistanceMilestones.insert(75)
                    let toGo = Int(remaining.rounded())
                    if toGo > 0 && toGo <= 60 {
                        tts.speakSequence([
                            .bundled("num_\(toGo)"),
                            .bundled("kilometers_to_go", fallbackText: "kilometers to go."),
                            .bundled("encourage_grinding", fallbackText: "Keep grinding — you've got this."),
                        ])
                    }
                }
            }

            if target >= 15 {
                let ninetyPct = Int(target * 0.9)
                if !announcedDistanceMilestones.contains(90) && Int(currentDistanceKm) >= ninetyPct {
                    announcedDistanceMilestones.insert(90)
                    let toGo = Int(remaining.rounded())
                    if toGo > 0 && toGo <= 60 {
                        tts.speakSequence([
                            .bundled("num_\(toGo)"),
                            .bundled("kilometers_to_go", fallbackText: "kilometers to go."),
                            .bundled("encourage_hardest_done", fallbackText: "The hardest part is already behind you."),
                        ])
                    }
                }
            }
        }

        // ── Time-based milestones ──
        let elapsedMinutes = Int(elapsedTime / 60)

        if let targetMins = targetDurationMinutes, targetMins > 0 {
            // Time-based workout halfway
            let halfwayMin = targetMins / 2
            if !announcedTimeMilestones.contains(halfwayMin) && elapsedMinutes >= halfwayMin {
                announcedTimeMilestones.insert(halfwayMin)
                let remainingMins = targetMins - elapsedMinutes
                var clips: [AudioClip] = [
                    .bundled("encourage_halfway", fallbackText: "Halfway home."),
                ]
                if remainingMins > 0 && remainingMins <= 60 {
                    clips.append(.bundled("num_\(remainingMins)"))
                    clips.append(.bundled("minutes_label", fallbackText: "minutes."))
                    clips.append(.bundled("kilometers_to_go", fallbackText: "to go."))
                }
                tts.speakSequence(clips)
            }

            // "Only X minutes to go" at 75% for longer time-based runs (30min+)
            if targetMins >= 30 {
                let seventyFiveMin = targetMins * 3 / 4
                if !announcedTimeMilestones.contains(seventyFiveMin) && elapsedMinutes >= seventyFiveMin {
                    announcedTimeMilestones.insert(seventyFiveMin)
                    let remainingMins = targetMins - elapsedMinutes
                    if remainingMins > 0 && remainingMins <= 60 {
                        tts.speakSequence([
                            .bundled("num_\(remainingMins)"),
                            .bundled("minutes_label", fallbackText: "minutes to go."),
                            .bundled("encourage_grinding", fallbackText: "Keep grinding — you've got this."),
                        ])
                    }
                }
            }
        }

        // ── General time checkpoints (any run) ──
        if !hasAnnounced30Min && elapsedTime >= 1800 && elapsedTime < 1830 {
            hasAnnounced30Min = true
            tts.speakSequence([.bundled("thirty_minutes", fallbackText: "Thirty minutes down.")])
        }
        if !hasAnnounced60Min && elapsedTime >= 3600 && elapsedTime < 3630 {
            hasAnnounced60Min = true
            tts.speakSequence([.bundled("one_hour", fallbackText: "One hour in. Keep it rolling.")])
        }
    }

    /// Play a random encouragement (throttled to once per 5 minutes).
    func announceEncouragement() {
        guard settings.isEnabled, settings.announceEncouragement else { return }

        let now = Date()
        guard now.timeIntervalSince(lastEncouragementTime) >= encouragementInterval else { return }
        lastEncouragementTime = now

        let encouragements = [
            "encourage_locked_in",
            "encourage_own_it",
            "encourage_grinding",
            "encourage_big_effort",
        ]

        let clip = encouragements[encouragementIndex % encouragements.count]
        encouragementIndex += 1
        tts.speakSequence([.bundled(clip)])
    }

    /// Announce strong start (first km).
    func announceStrongStart() {
        guard settings.isEnabled, settings.announceEncouragement else { return }
        tts.speakSequence([.bundled("encourage_strong_start")])
    }

    /// Announce negative split achievement.
    func announceNegativeSplit() {
        guard settings.isEnabled, settings.announceEncouragement else { return }
        tts.speakSequence([.bundled("encourage_negative_split")])
    }

    /// Announce live personal record (e.g., fastest km during a run).
    func announceNewFastestKm(splitTime: String) {
        guard settings.isEnabled, settings.announceRecords else { return }
        tts.speakSequence([
            .bundled("new_fastest_km"),
            .text(splitTime),
        ])
    }

    // MARK: - Pause / Resume / Stop

    func announcePaused() {
        guard settings.isEnabled, settings.speakPausedResumed else { return }
        tts.speakSequence([.bundled("run_paused", fallbackText: "Run paused.")])
    }

    func announceResumed() {
        guard settings.isEnabled, settings.speakPausedResumed else { return }
        tts.speakSequence([.bundled("run_resumed", fallbackText: "Run resumed.")])
    }

    func announceAutoPauseOn() {
        guard settings.isEnabled, settings.speakPausedResumed else { return }
        tts.speakSequence([.bundled("auto_pause_on", fallbackText: "Auto-pause activated.")])
    }

    func announceAutoPauseOff() {
        guard settings.isEnabled, settings.speakPausedResumed else { return }
        tts.speakSequence([.bundled("auto_pause_off", fallbackText: "Auto-pause deactivated. You're moving again.")])
    }

    func announcePausedReminder() {
        guard settings.isEnabled, settings.speakPausedResumed else { return }
        tts.speakSequence([.bundled("paused_reminder", fallbackText: "Still paused. Tap resume when you're ready.")])
    }

    func announceRunEnded() {
        guard settings.isEnabled else { return }
        tts.speakSequence([.bundled("run_ended", fallbackText: "Run ended.")])
    }

    func announceRunSaved() {
        guard settings.isEnabled else { return }
        tts.speakSequence([.bundled("run_saved", fallbackText: "Run saved.")])
    }

    // MARK: - 3. POST-RUN Announcements

    /// Announce run complete and summary.
    func announceRunSummary(
        distanceKm: Double,
        totalTime: TimeInterval,
        avgPaceSecPerKm: Double,
        bestSplitKm: Int?,
        bestSplitPace: Double?
    ) {
        guard settings.isEnabled, settings.announcePostRunSummary else { return }

        // Distance as bundled number clips (e.g., [num_5] [kilometers])
        let distWhole = Int(distanceKm)
        var distClips: [AudioClip] = []
        if distWhole > 0 && distWhole <= 60 {
            distClips.append(.bundled("num_\(distWhole)"))
        } else {
            distClips.append(.text(String(format: "%.1f", distanceKm)))
        }
        distClips.append(.bundled("kilometers"))

        var clips: [AudioClip] = [
            .bundled("run_complete", fallbackText: "Run complete. Nice work."),
            .bundled("total_distance", fallbackText: "Total distance:"),
        ]
        clips.append(contentsOf: distClips)
        clips.append(.bundled("total_time", fallbackText: "Total time:"))
        clips.append(contentsOf: timeClips(totalTime))
        clips.append(.bundled("average_pace", fallbackText: "Average pace so far:"))
        clips.append(contentsOf: paceClips(secondsPerKm: avgPaceSecPerKm))

        if let km = bestSplitKm, let pace = bestSplitPace {
            clips.append(.bundled("best_split", fallbackText: "Best split:"))
            if km <= 100 {
                clips.append(.bundled("km_\(km)"))
            }
            clips.append(contentsOf: paceClips(secondsPerKm: pace))
        }

        tts.speakSequence(clips)
    }

    /// Announce personal record.
    func announcePersonalRecord(type: PRType, value: String) {
        guard settings.isEnabled, settings.announceRecords else { return }

        switch type {
        case .fastestDistance(let distance):
            tts.speakSequence([
                .bundled("new_pr"),
                .bundled("fastest"),
                .text(distance),
                .text(value),
            ])
        case .longestRun:
            tts.speakSequence([
                .bundled("longest_run"),
                .text(value),
            ])
        case .longestDuration:
            tts.speakSequence([
                .bundled("longest_duration"),
                .text(value),
            ])
        case .monthlyRecord:
            tts.speakSequence([
                .bundled("new_monthly_record"),
                .text(value),
                .bundled("this_month"),
            ])
        }
    }

    /// Announce comparison to past runs.
    func announceComparison(isFaster: Bool) {
        guard settings.isEnabled, settings.announcePostRunSummary else { return }
        tts.speakSequence([.bundled(isFaster ? "faster_than_last" : "slower_than_last")])
    }

    /// Announce streak / consistency.
    func announceStreak(runsThisWeek: Int) {
        guard settings.isEnabled, settings.announceRecords else { return }
        var clips: [AudioClip] = [.bundled("thats")]
        if runsThisWeek > 0 && runsThisWeek <= 60 {
            clips.append(.bundled("num_\(runsThisWeek)"))
        } else {
            clips.append(.text("\(runsThisWeek)"))
        }
        clips.append(.bundled("runs_this_week"))
        tts.speakSequence(clips)
    }

    func announceRunningStreak(days: Int) {
        guard settings.isEnabled, settings.announceRecords else { return }
        var clips: [AudioClip] = [.bundled("youre_on_a")]
        if days > 0 && days <= 60 {
            clips.append(.bundled("num_\(days)"))
        } else {
            clips.append(.text("\(days)"))
        }
        clips.append(.bundled("day_running_streak"))
        tts.speakSequence(clips)
    }

    func announceWeeklyGoalHit() {
        guard settings.isEnabled else { return }
        tts.speakSequence([.bundled("weekly_goal_hit")])
    }

    /// Announce workout compliance.
    func announceWorkoutCompliance(_ result: ComplianceResult) {
        guard settings.isEnabled, settings.announcePostRunSummary else { return }

        let clipName: String
        switch result {
        case .nailed:           clipName = "compliance_nailed"
        case .mostOnTarget:     clipName = "compliance_most_on_target"
        case .tempoGood:        clipName = "compliance_tempo_good"
        case .recoveryTooFast:  clipName = "compliance_recovery_fast"
        case .warmupShort:      clipName = "compliance_warmup_short"
        case .cooldownDone:     clipName = "compliance_cooldown"
        }

        tts.speakSequence([.bundled(clipName)])
    }

    /// Announce recovery suggestion.
    func announceRecovery(_ type: RecoveryType) {
        guard settings.isEnabled, settings.announcePostRunSummary else { return }

        let clipName: String
        switch type {
        case .easyDay:      clipName = "recovery_easy_day"
        case .readyForHard: clipName = "recovery_ready"
        case .stretch:      clipName = "recovery_stretch"
        case .hydrate:      clipName = "recovery_hydrate"
        case .earnedIt:     clipName = "recovery_earned_it"
        }

        tts.speakSequence([.bundled(clipName)])
    }

    /// Announce training plan progress.
    func announceTrainingPlanProgress(currentWeek: Int, totalWeeks: Int, weeksToRace: Int?) {
        guard settings.isEnabled, settings.announcePostRunSummary else { return }

        var clips: [AudioClip] = [.bundled("week_label")]
        if currentWeek > 0 && currentWeek <= 60 {
            clips.append(.bundled("num_\(currentWeek)"))
        } else {
            clips.append(.text("\(currentWeek)"))
        }
        clips.append(.bundled("of_your_plan"))

        if let weeks = weeksToRace, weeks > 0 {
            if weeks <= 60 {
                clips.append(.bundled("num_\(weeks)"))
            } else {
                clips.append(.text("\(weeks)"))
            }
            clips.append(.bundled("weeks_to_race"))
        }

        tts.speakSequence(clips)
    }

    // MARK: - Cache Management

    /// Returns the total size of the voice cache in bytes.
    func cacheSize() -> Int {
        tts.cacheSize()
    }

    /// Clears the voice cache.
    func clearCache() {
        tts.clearCache()
    }

    // MARK: - Reset

    func reset() {
        tts.stopSpeaking()
        hasAnnouncedHalfway = false
        hasAnnounced30Min = false
        hasAnnounced60Min = false
        hasPlayedCountdown = false
        lastAnnouncedPaceZone = nil
        lastPaceZoneAnnouncement = .distantPast
        lastEncouragementTime = .distantPast
        encouragementIndex = 0
        announcedDistanceMilestones.removeAll()
        announcedTimeMilestones.removeAll()
        reloadSettings()
    }

    // MARK: - Clip Composition (all bundled, zero API)

    /// Compose pace as bundled clips: [num_5] [minute_s] [num_22] [second_s] [per_kilometer]
    /// Set `includeUnit` to false to omit "per kilometer" (used in split announcements where it's implied).
    private func paceClips(secondsPerKm: Double, includeUnit: Bool = true) -> [AudioClip] {
        let adjustedPace = secondsPerKm * settings.paceUnit.conversionFactor
        guard adjustedPace > 0, adjustedPace < 3600 else { return [.text("unknown")] }
        let minutes = Int(adjustedPace) / 60
        let seconds = Int(adjustedPace) % 60

        var clips: [AudioClip] = []

        if minutes > 0 && minutes <= 60 {
            clips.append(.bundled("num_\(minutes)"))
            clips.append(.bundled(minutes == 1 ? "minute" : "minute_s"))
        }
        if seconds > 0 && seconds <= 60 {
            clips.append(.bundled("num_\(seconds)"))
            clips.append(.bundled(seconds == 1 ? "second" : "second_s"))
        }
        if minutes == 0 && seconds == 0 {
            clips.append(.bundled("num_1"))
            clips.append(.bundled("second_s"))
        }
        if includeUnit {
            let unitClip = settings.paceUnit == .km ? "per_kilometer" : "per_mile"
            clips.append(.bundled(unitClip))
        }

        return clips
    }

    /// Compose elapsed time as bundled clips: [num_27] [minute_s] [num_15] [second_s]
    private func timeClips(_ totalSeconds: TimeInterval) -> [AudioClip] {
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let seconds = Int(totalSeconds) % 60

        var clips: [AudioClip] = []

        if hours > 0 && hours <= 60 {
            clips.append(.bundled("num_\(hours)"))
            clips.append(.bundled(hours == 1 ? "hour" : "hour_s"))
        }
        if minutes > 0 && minutes <= 60 {
            clips.append(.bundled("num_\(minutes)"))
            clips.append(.bundled(minutes == 1 ? "minute" : "minute_s"))
        }
        if seconds > 0 && seconds <= 60 && hours == 0 {
            // Only speak seconds if under 1 hour (otherwise too long)
            clips.append(.bundled("num_\(seconds)"))
            clips.append(.bundled(seconds == 1 ? "second" : "second_s"))
        }

        if clips.isEmpty {
            clips.append(.bundled("num_1"))
            clips.append(.bundled("second_s"))
        }

        return clips
    }

    // MARK: - Legacy String Formatting (for API-based features like post-run coach)

    func formatPaceForSpeech(secondsPerKm: Double) -> String {
        let adjustedPace = secondsPerKm * settings.paceUnit.conversionFactor
        guard adjustedPace > 0, adjustedPace < 3600 else { return "unknown" }
        let minutes = Int(adjustedPace) / 60
        let seconds = Int(adjustedPace) % 60
        if minutes == 0 {
            return "\(seconds) seconds \(settings.paceUnit.label)"
        } else if seconds == 0 {
            return "\(minutes) minute\(minutes == 1 ? "" : "s") \(settings.paceUnit.label)"
        }
        return "\(minutes) \(String(format: "%02d", seconds)) \(settings.paceUnit.label)"
    }

    func formatTimeForSpeech(_ totalSeconds: TimeInterval) -> String {
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let seconds = Int(totalSeconds) % 60

        if hours > 0 {
            return "\(hours) hour\(hours == 1 ? "" : "s") \(minutes) minutes"
        } else if minutes > 0 {
            return "\(minutes) minute\(minutes == 1 ? "" : "s") \(seconds) seconds"
        } else {
            return "\(seconds) seconds"
        }
    }
}

// MARK: - Supporting Types

enum PRType {
    case fastestDistance(String)
    case longestRun
    case longestDuration
    case monthlyRecord
}

enum ComplianceResult {
    case nailed, mostOnTarget, tempoGood, recoveryTooFast, warmupShort, cooldownDone
}

enum RecoveryType {
    case easyDay, readyForHard, stretch, hydrate, earnedIt
}
