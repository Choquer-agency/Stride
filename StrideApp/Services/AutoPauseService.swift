import Foundation
import os.log

private let autoPauseLog = Logger(subsystem: "com.stride.app", category: "AutoPause")

/// Monitors running speed and triggers auto-pause/resume for outdoor runs.
/// Pauses when speed drops below threshold for sustained duration, resumes when moving again.
final class AutoPauseService {
    var onAutoPause: (() -> Void)?
    var onAutoResume: (() -> Void)?

    private(set) var isAutoPaused: Bool = false
    var isEnabled: Bool = true

    // Thresholds
    private let pauseSpeedThreshold: Double = 0.5  // m/s — below this = stopped
    private let resumeSpeedThreshold: Double = 1.0 // m/s — above this = moving again
    private let pauseDelay: TimeInterval = 3.0     // seconds below threshold before pausing
    private let resumeDelay: TimeInterval = 2.0    // seconds above threshold before resuming

    // Tracking
    private var belowThresholdSince: Date?
    private var aboveThresholdSince: Date?

    func processSample(speedMps: Double) {
        guard isEnabled else { return }

        if !isAutoPaused {
            // Currently running — check if we should pause
            if speedMps < pauseSpeedThreshold {
                if belowThresholdSince == nil {
                    belowThresholdSince = Date()
                } else if let since = belowThresholdSince,
                          Date().timeIntervalSince(since) >= pauseDelay {
                    // Sustained stop — auto-pause
                    isAutoPaused = true
                    belowThresholdSince = nil
                    aboveThresholdSince = nil
                    autoPauseLog.info("Auto-paused: speed below \(self.pauseSpeedThreshold) m/s for \(self.pauseDelay)s")
                    onAutoPause?()
                }
            } else {
                // Moving — reset pause timer
                belowThresholdSince = nil
            }
        } else {
            // Currently paused — check if we should resume
            if speedMps > resumeSpeedThreshold {
                if aboveThresholdSince == nil {
                    aboveThresholdSince = Date()
                } else if let since = aboveThresholdSince,
                          Date().timeIntervalSince(since) >= resumeDelay {
                    // Sustained movement — auto-resume
                    isAutoPaused = false
                    aboveThresholdSince = nil
                    belowThresholdSince = nil
                    autoPauseLog.info("Auto-resumed: speed above \(self.resumeSpeedThreshold) m/s for \(self.resumeDelay)s")
                    onAutoResume?()
                }
            } else {
                // Still stopped — reset resume timer
                aboveThresholdSince = nil
            }
        }
    }

    func reset() {
        isAutoPaused = false
        belowThresholdSince = nil
        aboveThresholdSince = nil
    }
}
