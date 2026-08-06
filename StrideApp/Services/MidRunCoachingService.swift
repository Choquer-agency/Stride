import Foundation
import os.log

private let coachLog = Logger(subsystem: "com.stride.app", category: "MidRunCoach")

// MARK: - Performance Trend

enum PerformanceTrend {
    case surging    // recent pace > 5% faster than baseline
    case holding    // within ±5% of baseline
    case fading     // recent pace > 5% slower than baseline
}

// MARK: - MidRunCoachingService

/// Intelligent mid-run coaching engine that provides:
/// - Performance-aware last-1km and last-200m announcements
/// - Terrain coaching on out-and-back routes (hill warnings/cleared)
/// - Enhanced halfway messages with performance context
///
/// Receives data from RunViewModel on every GPS update and delegates
/// audio playback to VoiceCoachService.
final class MidRunCoachingService {
    private let voiceCoach: VoiceCoachService

    // MARK: - Out-and-Back State

    private var turnaroundDetected = false
    private var turnaroundIndex: Int?
    private var lastTurnaroundCheckDistance: Double = 0

    // MARK: - Hill Coaching State

    /// The hill we most recently warned about (to track "cleared")
    private var activeHill: Hill?
    private var activeHillEndDistanceKm: Double?
    /// Distance (km) at which we last announced a hill warning
    private var lastHillWarningDistanceKm: Double?
    private var lastHillAnnouncementTime: Date = .distantPast
    private let hillDebounceInterval: TimeInterval = 60.0

    // MARK: - Distance Milestone State

    private var hasAnnouncedLastKm = false
    private var hasAnnouncedFinalPush = false
    private var hasAnnouncedEnhancedHalfway = false

    // MARK: - Global Debounce

    private var lastAnnouncementTime: Date = .distantPast
    private let globalDebounceInterval: TimeInterval = 15.0

    /// Track when the last km split fired to avoid collision
    private var lastKmSplitTime: Date = .distantPast

    // MARK: - Init

    init(voiceCoach: VoiceCoachService) {
        self.voiceCoach = voiceCoach
    }

    // MARK: - Main Update

    /// Called from RunViewModel.handleRunSample() on every GPS/data update.
    func update(
        routePoints: [RoutePoint]?,
        currentDistanceKm: Double,
        targetDistanceKm: Double?,
        elapsedTime: TimeInterval,
        smoothedPaceSecPerKm: Double?,
        kmSplits: [KilometerSplit],
        isGPSRun: Bool
    ) {
        // Terrain coaching: GPS outdoor runs only
        if isGPSRun, let points = routePoints, points.count >= 30 {
            updateTerrainCoaching(
                routePoints: points,
                currentDistanceKm: currentDistanceKm,
                targetDistanceKm: targetDistanceKm
            )
        }

        // Performance trend
        let trend = computePerformanceTrend(kmSplits: kmSplits)

        // Enhanced halfway (append performance context to existing halfway)
        if let target = targetDistanceKm, target > 0, !hasAnnouncedEnhancedHalfway {
            if currentDistanceKm >= target / 2.0 {
                hasAnnouncedEnhancedHalfway = true
                if let t = trend, canAnnounce() {
                    // Small delay so it plays after the existing halfway announcement
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                        self?.voiceCoach.announceEnhancedHalfway(trend: t)
                        self?.recordAnnouncement()
                    }
                }
            }
        }

        // Last 1km
        if let target = targetDistanceKm, target >= 2.0 {
            let remaining = target - currentDistanceKm
            if remaining <= 1.0 && remaining > 0.05 && !hasAnnouncedLastKm {
                hasAnnouncedLastKm = true
                if canAnnounce() {
                    voiceCoach.announceLastKm(trend: trend ?? .holding)
                    recordAnnouncement()
                    coachLog.info("Last kilometer announced (trend: \(String(describing: trend)))")
                }
            }

            // Last 200m
            if remaining <= 0.2 && remaining > 0.01 && !hasAnnouncedFinalPush {
                hasAnnouncedFinalPush = true
                if canAnnounce() {
                    voiceCoach.announceFinalPush()
                    recordAnnouncement()
                    coachLog.info("Final push announced")
                }
            }
        }
    }

    /// Notify the service that a km split just fired (for debounce coordination).
    func onKmSplitAnnounced() {
        lastKmSplitTime = Date()
    }

    /// Public accessor for the performance trend so other call sites (e.g., the
    /// finish celebration) can reuse the same fading/holding/surging classification.
    func performanceTrend(kmSplits: [KilometerSplit]) -> PerformanceTrend? {
        computePerformanceTrend(kmSplits: kmSplits)
    }

    // MARK: - Terrain Coaching

    private func updateTerrainCoaching(
        routePoints: [RoutePoint],
        currentDistanceKm: Double,
        targetDistanceKm: Double?
    ) {
        let currentIndex = routePoints.count - 1

        // Only check for turnaround every 100m to save computation
        let currentDistanceM = currentDistanceKm * 1000
        if !turnaroundDetected && currentDistanceM - lastTurnaroundCheckDistance >= 100 {
            lastTurnaroundCheckDistance = currentDistanceM
            if let result = RouteAnalyzer.detectTurnaround(routePoints: routePoints, currentIndex: currentIndex) {
                turnaroundDetected = true
                turnaroundIndex = result.turnaroundIndex
                coachLog.info("Turnaround detected at index \(result.turnaroundIndex), \(result.turnaroundDistance)m from start")
            } else {
                coachLog.debug("Turnaround check at \(currentDistanceM)m: not detected")
            }
        }

        // Hill coaching: only on return leg
        guard turnaroundDetected, let turnIdx = turnaroundIndex else { return }

        let outboundSlice = routePoints[0...turnIdx]
        let currentPoint = routePoints[currentIndex]

        let lookahead = RouteAnalyzer.elevationLookahead(
            outboundPoints: outboundSlice,
            currentPosition: currentPoint,
            lookaheadMeters: 800
        )
        guard !lookahead.isEmpty else {
            coachLog.debug("Lookahead empty at km \(currentDistanceKm) — outbound path too far or no match")
            return
        }

        let hills = RouteAnalyzer.detectHills(in: lookahead)
        coachLog.debug("Lookahead: \(lookahead.count) segments, detected \(hills.count) hills")

        // Check if active hill has been cleared
        if let active = activeHill, let hillEnd = activeHillEndDistanceKm {
            // Use route progress captured when the warning fired. Re-detection can
            // temporarily lose a hill near its crest and used to announce "cleared"
            // before the runner had even reached it.
            if currentDistanceKm >= hillEnd + 0.03 {
                if canAnnounceHill() && canAnnounce() {
                    voiceCoach.announceHillCleared(isUphill: active.isUphill)
                    recordAnnouncement()
                    recordHillAnnouncement()
                    coachLog.info("Hill cleared (\(active.isUphill ? "uphill" : "downhill"))")
                }
                activeHill = nil
                activeHillEndDistanceKm = nil
            }
        }

        // Announce upcoming hill (100-600m ahead — widened from 150-500m so we don't
        // miss hills that fall just outside the original window on the return leg).
        if activeHill == nil, let nextHill = hills.first {
            if nextHill.distanceAhead >= 100 && nextHill.distanceAhead <= 600 {
                if canAnnounceHill() && canAnnounce() {
                    // Round to nearest 100m for the announcement
                    let roundedDistance = Int(round(nextHill.distanceAhead / 100.0)) * 100
                    voiceCoach.announceHillWarning(
                        distanceAheadMeters: roundedDistance,
                        isUphill: nextHill.isUphill
                    )
                    activeHill = nextHill
                    activeHillEndDistanceKm = currentDistanceKm + (nextHill.distanceAhead + nextHill.length) / 1_000
                    lastHillWarningDistanceKm = currentDistanceKm
                    recordAnnouncement()
                    recordHillAnnouncement()
                    coachLog.info("Hill warning: \(nextHill.isUphill ? "uphill" : "downhill") in ~\(roundedDistance)m, grade \(Int(nextHill.avgGrade * 100))%")
                } else {
                    coachLog.debug("Hill detected but suppressed (hillDebounce=\(!self.canAnnounceHill()) globalDebounce=\(!self.canAnnounce()))")
                }
            } else {
                coachLog.debug("Nearest hill \(Int(nextHill.distanceAhead))m ahead — outside warning window")
            }
        }
    }

    // MARK: - Performance Trend

    /// Compare last completed split to average of all prior splits.
    /// Returns nil if fewer than 2 splits completed.
    private func computePerformanceTrend(kmSplits: [KilometerSplit]) -> PerformanceTrend? {
        guard kmSplits.count >= 2 else { return nil }

        // Parse pace strings to seconds
        let paces: [Double] = kmSplits.compactMap { split in
            guard let secs = split.pace.toSeconds else { return nil }
            return Double(secs)
        }
        guard paces.count >= 2 else { return nil }

        let lastPace = paces.last!
        let priorPaces = paces.dropLast()
        let avgPrior = priorPaces.reduce(0, +) / Double(priorPaces.count)

        guard avgPrior > 0 else { return .holding }

        let percentDiff = (lastPace - avgPrior) / avgPrior

        if percentDiff > 0.05 {
            return .fading   // last split >5% slower than average
        } else if percentDiff < -0.05 {
            return .surging  // last split >5% faster than average
        } else {
            return .holding
        }
    }

    // MARK: - Debouncing

    private func canAnnounce() -> Bool {
        let now = Date()
        // Global cooldown
        guard now.timeIntervalSince(lastAnnouncementTime) >= globalDebounceInterval else { return false }
        // Don't fire within 10s of a km split
        guard now.timeIntervalSince(lastKmSplitTime) >= 10 else { return false }
        return true
    }

    private func canAnnounceHill() -> Bool {
        Date().timeIntervalSince(lastHillAnnouncementTime) >= hillDebounceInterval
    }

    private func recordAnnouncement() {
        lastAnnouncementTime = Date()
    }

    private func recordHillAnnouncement() {
        lastHillAnnouncementTime = Date()
    }

    // MARK: - Reset

    func reset() {
        turnaroundDetected = false
        turnaroundIndex = nil
        lastTurnaroundCheckDistance = 0
        activeHill = nil
        activeHillEndDistanceKm = nil
        lastHillWarningDistanceKm = nil
        lastHillAnnouncementTime = .distantPast
        hasAnnouncedLastKm = false
        hasAnnouncedFinalPush = false
        hasAnnouncedEnhancedHalfway = false
        lastAnnouncementTime = .distantPast
        lastKmSplitTime = .distantPast
    }
}
