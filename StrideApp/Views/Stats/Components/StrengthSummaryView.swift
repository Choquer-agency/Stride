import SwiftUI

struct StrengthSummaryView: View {
    let sessionsThisWeek: Int
    let sessionsTotal: Int
    let weeksWithSession: (completed: Int, total: Int)
    let isOnTrack: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("Strength Training")
                .font(.inter(size: 18, weight: .semibold))
            
            // Metrics grid
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("This Week")
                        .font(.inter(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("\(sessionsThisWeek)")
                        .font(.barlowCondensed(size: 24, weight: .medium))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("This Cycle")
                        .font(.inter(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("\(sessionsTotal)")
                        .font(.barlowCondensed(size: 24, weight: .medium))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weeks with ≥1")
                        .font(.inter(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("\(weeksWithSession.completed) of \(weeksWithSession.total)")
                        .font(.barlowCondensed(size: 20, weight: .medium))
                }
                
                Spacer()
            }
            
            // Binary signal indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(isOnTrack ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                
                Text(isOnTrack ? "On track" : "Needs attention")
                    .font(.inter(size: 13, weight: .medium))
                    .foregroundStyle(isOnTrack ? Color.green : Color.orange)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(Color(hex: "F9F9F9"))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    StrengthSummaryView(
        sessionsThisWeek: 2,
        sessionsTotal: 16,
        weeksWithSession: (completed: 8, total: 12),
        isOnTrack: true
    )
    .padding()
}
