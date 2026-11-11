import ActivityKit
import SwiftUI
import WidgetKit

private enum RunActivityStyle {
    static let red = Color(red: 1, green: 0.18, blue: 0.12)
    static let blue = Color(red: 0.24, green: 0.62, blue: 1)
    static let muted = Color.white.opacity(0.56)
}

struct StrideRunLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StrideRunAttributes.self) { context in
            lockScreen(context)
                .activityBackgroundTint(Color(red: 0.055, green: 0.06, blue: 0.065))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("STRIDE")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(RunActivityStyle.red)
                        Text(context.state.isPaused ? "PAUSED" : "RUNNING")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(RunActivityStyle.muted)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.timeText)
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(RunActivityStyle.muted)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    expandedMetrics(context.state)
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    Circle().fill(RunActivityStyle.red).frame(width: 5, height: 5)
                    Text(context.state.isPaused ? "Ⅱ" : context.state.paceText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(.white)
                .accessibilityLabel(context.state.isPaused ? "Stride run paused" : "Pace \(context.state.paceText) per kilometer")
            } compactTrailing: {
                HStack(spacing: 1) {
                    Text(context.state.distanceText)
                    if let remaining = context.state.remainingText {
                        Text("/").foregroundStyle(RunActivityStyle.muted)
                        Text(remaining)
                    }
                }
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.white)
                .accessibilityLabel(compactDistanceLabel(context.state))
            } minimal: {
                Text(context.state.isPaused ? "Ⅱ" : context.state.paceText)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(RunActivityStyle.red)
                    .accessibilityLabel(context.state.isPaused ? "Stride paused" : "Stride pace \(context.state.paceText)")
            }
            .widgetURL(URL(string: "stride://run"))
            .keylineTint(RunActivityStyle.red)
        }
    }

    private func compactDistanceLabel(_ state: StrideRunAttributes.ContentState) -> String {
        guard let remaining = state.remainingText else { return "Distance \(state.distanceText) kilometers" }
        return "Distance \(state.distanceText) kilometers, \(remaining) remaining"
    }

    private func metric(_ label: String, value: String, unit: String? = nil,
                        prominent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1)
                .foregroundStyle(RunActivityStyle.muted)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: prominent ? 36 : 25, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let unit {
                    Text(unit)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(RunActivityStyle.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func expandedMetrics(_ state: StrideRunAttributes.ContentState) -> some View {
        HStack(alignment: .bottom, spacing: 14) {
            metric("PACE /KM", value: state.isPaused ? "PAUSED" : state.paceText, prominent: true)
            metric("DISTANCE", value: state.distanceText, unit: "KM")
            metric("TO GO", value: state.remainingText ?? "—", unit: "KM")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    private func lockScreen(_ context: ActivityViewContext<StrideRunAttributes>) -> some View {
        let state = context.state
        return VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 7) {
                    Image(systemName: "figure.run")
                        .foregroundStyle(RunActivityStyle.red)
                    Text("STRIDE")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .tracking(1)
                    Text("/ \(context.attributes.title.uppercased())")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(RunActivityStyle.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                HStack(spacing: 5) {
                    Circle().fill(state.isPaused ? .orange : RunActivityStyle.blue)
                        .frame(width: 6, height: 6)
                    Text(state.isPaused ? "PAUSED" : "LIVE")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(state.isPaused ? .orange : RunActivityStyle.blue)
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                metric("CURRENT PACE /KM", value: state.isPaused ? "—" : state.paceText, prominent: true)
                metric("DISTANCE", value: state.distanceText, unit: "KM")
                if state.targetDistanceKm != nil {
                    metric("REMAINING", value: state.remainingText ?? "—", unit: "KM")
                }
            }

            if let target = state.targetDistanceKm, target > 0 {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.14))
                        Capsule().fill(RunActivityStyle.red)
                            .frame(width: geometry.size.width * min(1, max(0, state.distanceKm / target)))
                    }
                }
                .frame(height: 5)
                .accessibilityLabel("\(Int(min(100, state.distanceKm / target * 100))) percent complete")
            }

            HStack {
                Label(state.timeText, systemImage: "clock")
                Spacer()
                if let heartRate = state.heartRate {
                    Label("\(heartRate) BPM", systemImage: "heart.fill")
                        .foregroundStyle(Color(red: 1, green: 0.50, blue: 0.64))
                }
                Spacer()
                Text(context.attributes.isOutdoor ? "OUTDOOR" : "TREADMILL")
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(RunActivityStyle.muted)
        }
        .foregroundStyle(.white)
        .padding(17)
        .widgetURL(URL(string: "stride://run"))
    }
}
