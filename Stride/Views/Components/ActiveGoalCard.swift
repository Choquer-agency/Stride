import SwiftUI

/// Hero card displaying the active training goal
struct ActiveGoalCard: View {
    let goal: Goal
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 16) {
                // Header with title and edit icon
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(goal.displayName)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        if let targetTime = goal.formattedTargetTime {
                            Text("Target: \(targetTime)")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                        } else {
                            Text("Goal: Complete strong & healthy")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "pencil.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.8))
                }
                
                // Countdown section
                VStack(alignment: .leading, spacing: 8) {
                    // Days remaining (large)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(goal.daysRemaining)")
                            .font(.system(size: 56, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text(goal.daysRemaining == 1 ? "Day remaining" : "Days remaining")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    
                    // Weeks remaining (secondary)
                    Text("\(goal.weeksRemaining) \(goal.weeksRemaining == 1 ? "week" : "weeks") remaining")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                    
                    // Race week badge if within 7 days
                    if goal.daysRemaining <= 7 {
                        HStack {
                            Image(systemName: "flag.fill")
                                .font(.caption)
                            Text("Race week!")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(12)
                        .padding(.top, 4)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.stridePrimary,
                        Color.stridePrimary.opacity(0.8)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(20)
            .shadow(color: Color.stridePrimary.opacity(0.3), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// Empty state card prompting user to set a goal
struct SetGoalCTACard: View {
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 16) {
                Image(systemName: "target")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                
                VStack(spacing: 8) {
                    Text("Set a Goal")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Pick a date and a target time —\nStride will build around it.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                Text("Tap to begin")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .padding(.horizontal, 24)
            .background(Color(.systemGray6))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.green.opacity(0.3), lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview("Active Goal Card") {
    VStack(spacing: 20) {
        ActiveGoalCard(
            goal: Goal(
                type: .race,
                targetTime: 5700, // 1:35:00
                eventDate: Calendar.current.date(byAdding: .day, value: 42, to: Date())!,
                title: "BMO Half Marathon",
                raceDistance: .halfMarathon
            ),
            onTap: {}
        )
        
        ActiveGoalCard(
            goal: Goal(
                type: .race,
                targetTime: 1200, // 20:00
                eventDate: Calendar.current.date(byAdding: .day, value: 5, to: Date())!,
                title: "Local 5K",
                raceDistance: .fiveK
            ),
            onTap: {}
        )
        
        SetGoalCTACard(onTap: {})
    }
    .padding()
}
