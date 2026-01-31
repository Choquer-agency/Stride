import SwiftUI

/// Card displaying pace drift percentage with color coding
struct PaceDriftCard: View {
    let paceDriftPercent: Double?
    
    private var driftColor: Color {
        guard let drift = paceDriftPercent else { return .gray }
        let absDrift = abs(drift)
        
        if absDrift < 2.0 {
            return .green
        } else if absDrift < 5.0 {
            return .yellow
        } else {
            return .red
        }
    }
    
    private var driftText: String {
        guard let drift = paceDriftPercent else {
            return "--"
        }
        
        let sign = drift >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", drift))%"
    }
    
    var body: some View {
        VStack(spacing: 4) {
            Text(driftText)
                .font(.system(size: 40, weight: .medium))
                .foregroundColor(driftColor)
            
            Text("Pace drift")
                .font(.system(size: 14, weight: .light))
                .foregroundColor(.secondary)
            
            if paceDriftPercent == nil {
                Text("Establishing...")
                    .font(.system(size: 11, weight: .light))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

