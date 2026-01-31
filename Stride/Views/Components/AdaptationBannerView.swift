import SwiftUI

/// Banner view displaying weekly adaptation coach message
struct AdaptationBannerView: View {
    let record: AdaptationRecord
    let onDismiss: () -> Void
    let onTap: () -> Void
    
    @State private var isExpanded: Bool = false
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main banner content
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
                onTap()
            }) {
                HStack(spacing: 12) {
                    // Icon based on severity
                    severityIcon
                        .font(.system(size: 24))
                        .foregroundColor(severityColor)
                        .frame(width: 40, height: 40)
                        .background(severityColor.opacity(0.1))
                        .clipShape(Circle())
                    
                    // Message content
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.coachTitle)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text(record.coachSummary)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.secondary)
                            .lineLimit(isExpanded ? nil : 2)
                    }
                    
                    Spacer()
                    
                    // Chevron
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(16)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Expanded details
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                        .padding(.horizontal, 16)
                    
                    // Details list
                    ForEach(record.coachDetails, id: \.self) { detail in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.secondary)
                            
                            Text(detail)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    // Metrics summary
                    if record.adjustmentCount > 0 {
                        HStack(spacing: 16) {
                            if record.hasVolumeChange, let volumeChange = record.volumeChangePercent {
                                MetricPill(
                                    label: "Volume",
                                    value: String(format: "%+.0f%%", volumeChange),
                                    color: volumeChange < 0 ? .orange : .green
                                )
                            }
                            
                            if record.hasIntensityChange, let intensityChange = record.intensityChangePercent {
                                MetricPill(
                                    label: "Intensity",
                                    value: String(format: "%+.0f%%", intensityChange),
                                    color: intensityChange < 0 ? .orange : .green
                                )
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                    }
                    
                    // Dismiss button
                    Button(action: onDismiss) {
                        Text("Got it")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.stridePrimary)
                            .cornerRadius(8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .padding(.top, 8)
                }
            }
        }
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: Color.strideBlack.opacity(0.1), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    // MARK: - Computed Properties
    
    private var severityIcon: Image {
        switch record.messageSeverity {
        case "positive":
            return Image(systemName: "checkmark.circle.fill")
        case "neutral":
            return Image(systemName: "info.circle.fill")
        case "caution":
            return Image(systemName: "exclamationmark.triangle.fill")
        case "warning":
            return Image(systemName: "exclamationmark.circle.fill")
        default:
            return Image(systemName: "info.circle.fill")
        }
    }
    
    private var severityColor: Color {
        switch record.messageSeverity {
        case "positive":
            return .green
        case "neutral":
            return .blue
        case "caution":
            return .orange
        case "warning":
            return .red
        default:
            return .blue
        }
    }
}

// MARK: - Supporting Views

struct MetricPill: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }
}

// MARK: - Preview

#if DEBUG
struct AdaptationBannerView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            // Positive example
            AdaptationBannerView(
                record: createSampleRecord(severity: "positive"),
                onDismiss: {},
                onTap: {}
            )
            
            // Warning example
            AdaptationBannerView(
                record: createSampleRecord(severity: "warning"),
                onDismiss: {},
                onTap: {}
            )
            
            Spacer()
        }
        .padding(.top, 20)
        .background(Color(.systemBackground))
    }
    
    static func createSampleRecord(severity: String) -> AdaptationRecord {
        let analysisResult = AnalysisResult(
            weekStartDate: Date().addingTimeInterval(-7 * 24 * 3600),
            weekEndDate: Date(),
            plannedWorkouts: [],
            completedWorkouts: [],
            completionRate: 0.9,
            avgPaceVariance: -2.0,
            avgHRDrift: 3.5,
            avgRPE: 7.0,
            avgFatigue: 3.0,
            injuryCount: 0,
            paceConsistency: .excellent,
            fatigueStatus: .moderate,
            injuryStatus: .none,
            overallStatus: severity == "positive" ? .excellent : .needsRest
        )
        
        let adaptation = AdaptationPlan(
            createdAt: Date(),
            analysisResult: analysisResult,
            adjustments: [],
            coachMessage: AdaptationPlan.CoachMessage(
                title: severity == "positive" ? "Great Week! Small Progression" : "Recovery Week Ahead",
                summary: severity == "positive" ? 
                    "Excellent performance last week. Your plan includes a small 5% volume increase." :
                    "Your body needs more recovery. Volume reduced by 15%.",
                details: [
                    "✅ 90% completion rate",
                    "Strong pace consistency",
                    severity == "positive" ? "Ready for progression" : "High fatigue detected"
                ],
                severity: severity == "positive" ? .positive : .warning
            )
        )
        
        var record = AdaptationRecord(adaptationPlan: adaptation)
        record.viewed = false
        record.dismissed = false
        return record
    }
}
#endif
