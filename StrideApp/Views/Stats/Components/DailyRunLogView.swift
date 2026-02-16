import SwiftUI

struct DailyRunLogView: View {
    let runLogs: [RunLog]

    /// Completed runs, sorted most recent first
    private var recentRuns: [RunLog] {
        runLogs.sorted { $0.completedAt > $1.completedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("Run Log")
                .font(.inter(size: 18, weight: .semibold))

            if recentRuns.isEmpty {
                Text("No runs logged yet")
                    .font(.inter(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentRuns.prefix(10)), id: \.id) { run in
                        RunLogRow(runLog: run)

                        if run.id != recentRuns.prefix(10).last?.id {
                            Divider()
                                .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(hex: "F9F9F9"))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Single Run Row
private struct RunLogRow: View {
    let runLog: RunLog

    private var paceText: String {
        runLog.actualPaceDisplay ?? "—"
    }

    private var timeText: String {
        runLog.durationDisplay
    }

    private var distanceText: String {
        runLog.distanceDisplay
    }

    var body: some View {
        HStack(spacing: 0) {
            // Date
            Text(runLog.formattedDate)
                .font(.inter(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            Spacer()

            // Distance
            Text(distanceText)
                .font(.barlowCondensed(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 60, alignment: .trailing)

            Spacer()

            // Pace
            Text(paceText)
                .font(.barlowCondensed(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 80, alignment: .trailing)

            Spacer()

            // Time
            Text(timeText)
                .font(.barlowCondensed(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    DailyRunLogView(runLogs: [])
        .padding()
}
