import SwiftUI

struct PaceLaneIndicator: View {
    let currentPace: String
    let paceZone: PaceZone
    let targetPaceMin: Double?   // sec/km (faster boundary)
    let targetPaceMax: Double?   // sec/km (slower boundary)
    let isPlannedRun: Bool

    var body: some View {
        if isPlannedRun, let minPace = targetPaceMin, let maxPace = targetPaceMax {
            plannedRunDisplay(minPace: minPace, maxPace: maxPace)
        } else {
            freeRunDisplay
        }
    }

    // MARK: - Planned Run: Target Pace + Large Pace

    private func plannedRunDisplay(minPace: Double, maxPace: Double) -> some View {
        let minFormatted = Self.formatPace(secondsPerKm: minPace)
        let maxFormatted = Self.formatPace(secondsPerKm: maxPace)

        return VStack(spacing: 0) {
            // Target pace row
            HStack {
                Text("Target: \(minFormatted) - \(maxFormatted) Pace")
                    .font(.inter(size: 16, weight: .semibold))
                    .foregroundColor(.stridePrimary)
                Spacer()
                if !paceZone.statusText.isEmpty {
                    Text(paceZone.statusText)
                        .font(.inter(size: 16, weight: .semibold))
                        .foregroundColor(paceZone.statusColor)
                }
            }
            .padding(.bottom, 8)

            // Large pace number — always primary color
            Text(currentPace)
                .font(.barlowCondensed(size: 120, weight: .medium))
                .foregroundColor(.primary)
                .contentTransition(.numericText())

            // Label
            Text("Pace (/km)")
                .font(.inter(size: 14, weight: .regular))
                .foregroundColor(.secondary)
        }
        .animation(.easeInOut(duration: 0.5), value: paceZone.statusText)
    }

    // MARK: - Free Run: Simple Display

    private var freeRunDisplay: some View {
        VStack(spacing: 8) {
            Text(currentPace)
                .font(.barlowCondensed(size: 120, weight: .medium))
                .foregroundColor(.primary)

            Text("Pace (/km)")
                .font(.inter(size: 14, weight: .regular))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Helpers

    /// Format seconds/km as "M:SS" (no suffix).
    private static func formatPace(secondsPerKm: Double) -> String {
        guard secondsPerKm > 0 && secondsPerKm < 3600 else { return "--:--" }
        let minutes = Int(secondsPerKm) / 60
        let seconds = Int(secondsPerKm) % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

#Preview("Planned — On Pace") {
    PaceLaneIndicator(
        currentPace: "5:45",
        paceZone: .onPace,
        targetPaceMin: 330,
        targetPaceMax: 360,
        isPlannedRun: true
    )
    .padding()
}

#Preview("Planned — Too Slow") {
    PaceLaneIndicator(
        currentPace: "6:37",
        paceZone: .tooSlow,
        targetPaceMin: 330,
        targetPaceMax: 360,
        isPlannedRun: true
    )
    .padding()
}

#Preview("Free Run") {
    PaceLaneIndicator(
        currentPace: "5:30",
        paceZone: .noTarget,
        targetPaceMin: nil,
        targetPaceMax: nil,
        isPlannedRun: false
    )
    .padding()
}
