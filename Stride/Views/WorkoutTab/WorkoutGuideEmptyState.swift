import SwiftUI

/// Empty state for workout guide when no workout is scheduled or it's a rest day
struct WorkoutGuideEmptyState: View {
    let isRestDay: Bool
    let onViewPlan: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Icon
            if isRestDay {
                Image(systemName: "bed.double.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.purple)
            } else {
                Image(BrandAssets.logo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .foregroundColor(BrandAssets.brandPrimary)
            }
            
            // Message
            VStack(spacing: 8) {
                Text(isRestDay ? "Rest day — recovery is part of training" : "No workout scheduled for today")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                
                Text(isRestDay 
                    ? "Your body builds fitness during rest. Enjoy the day off!"
                    : "Visit the Plan tab to create your training schedule")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            // Action button (only for non-rest days)
            if !isRestDay {
                Button(action: onViewPlan) {
                    HStack {
                        Image(systemName: "calendar")
                        Text("View Training Plan")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)
            }
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - Preview

#Preview("No Workout") {
    WorkoutGuideEmptyState(isRestDay: false, onViewPlan: {})
}

#Preview("Rest Day") {
    WorkoutGuideEmptyState(isRestDay: true, onViewPlan: {})
}
