import SwiftUI

struct MilestonesView: View {
    let longestRunEver: Double
    let highestWeeklyMileage: Double
    let fastest5K: MilestoneRecord?
    let fastest10K: MilestoneRecord?
    let fastest21K: MilestoneRecord?
    let fastest42K: MilestoneRecord?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("Milestones")
                .font(.inter(size: 18, weight: .semibold))
            
            // Milestone cards
            VStack(spacing: 12) {
                // Race PBs (always shown, TBD if no data)
                MilestoneCard(
                    icon: "flame.fill",
                    title: "Fastest 5K",
                    value: fastest5K?.timeString ?? "TBD",
                    subtitle: fastest5K?.formattedDate,
                    color: .stridePrimary
                )
                
                MilestoneCard(
                    icon: "flame.fill",
                    title: "Fastest 10K",
                    value: fastest10K?.timeString ?? "TBD",
                    subtitle: fastest10K?.formattedDate,
                    color: .stridePrimary
                )
                
                MilestoneCard(
                    icon: "flame.fill",
                    title: "Fastest 21K",
                    value: fastest21K?.timeString ?? "TBD",
                    subtitle: fastest21K?.formattedDate,
                    color: .stridePrimary
                )
                
                MilestoneCard(
                    icon: "flame.fill",
                    title: "Fastest 42K",
                    value: fastest42K?.timeString ?? "TBD",
                    subtitle: fastest42K?.formattedDate,
                    color: .stridePrimary
                )
                
                // Distance milestones (always shown, TBD if no data)
                MilestoneCard(
                    icon: "figure.run.circle.fill",
                    title: "Longest Run Ever",
                    value: longestRunEver > 0 ? "\(Int(longestRunEver)) km" : "TBD",
                    color: .stridePrimary
                )
                
                MilestoneCard(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Highest Weekly Mileage",
                    value: highestWeeklyMileage > 0 ? "\(Int(highestWeeklyMileage)) km" : "TBD",
                    color: .stridePrimary
                )
                
            }
        }
        .padding(16)
        .background(Color(hex: "F9F9F9"))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct MilestoneCard: View {
    let icon: String
    let title: String
    let value: String
    var subtitle: String? = nil
    let color: Color
    
    private var isTBD: Bool {
        value == "TBD"
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(color.opacity(isTBD ? 0.08 : 0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isTBD ? color.opacity(0.4) : color)
            }
            
            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.inter(size: 13, weight: .medium))
                    .foregroundStyle(isTBD ? .tertiary : .secondary)
                
                HStack(spacing: 6) {
                    Text(value)
                        .font(.barlowCondensed(size: 18, weight: .medium))
                        .foregroundStyle(isTBD ? .tertiary : .primary)
                    
                    if let subtitle = subtitle {
                        Text("·")
                            .font(.inter(size: 13, weight: .medium))
                            .foregroundStyle(.tertiary)
                        
                        Text(subtitle)
                            .font(.inter(size: 13, weight: .regular))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    MilestonesView(
        longestRunEver: 38,
        highestWeeklyMileage: 72,
        fastest5K: MilestoneRecord(timeString: "22:15", date: Date()),
        fastest10K: MilestoneRecord(timeString: "47:30", date: Date()),
        fastest21K: MilestoneRecord(timeString: "1:45:00", date: Date()),
        fastest42K: nil
    )
    .padding()
}
