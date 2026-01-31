import SwiftUI

/// List of kilometer splits with visual pace bars
struct SplitsListView: View {
    let splits: [Split]
    
    
    
    var fastestSplit: Split? {
        splits.min(by: { $0.splitTimeSeconds < $1.splitTimeSeconds })
    }
    
    var slowestSplit: Split? {
        splits.max(by: { $0.splitTimeSeconds < $1.splitTimeSeconds })
    }
    
    // Calculate the relative width for each split's pace bar
    private func barWidthRatio(for split: Split) -> Double {
        guard let fastest = fastestSplit?.splitTimeSeconds,
              let slowest = slowestSplit?.splitTimeSeconds,
              slowest > fastest else {
            return 0.5
        }
        
        // Faster splits (lower time) get longer bars
        // Invert the scale so faster = longer bar
        let range = slowest - fastest
        let position = slowest - split.splitTimeSeconds
        
        if range > 0 {
            // Scale from 0.3 (slowest) to 1.0 (fastest)
            return 0.3 + (position / range) * 0.7
        }
        
        return 1.0
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header row - sticky
            HStack(spacing: 0) {
                Text("Km")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .leading)
                
                Text("Pace")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text("Total time")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 100, alignment: .trailing)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            
            // Divider
            Divider()
            
            // Splits rows
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(splits) { split in
                        ZStack(alignment: .leading) {
                            // Background pace bar starting after the km number
                            HStack(spacing: 0) {
                                Spacer()
                                    .frame(width: 60) // Skip km column width
                                
                                RoundedRectangle(cornerRadius: 0)
                                    .fill(Color.stridePrimary.opacity(0.08))
                                    .frame(width: CGFloat((UIScreen.main.bounds.width - 60 - 32) * CGFloat(barWidthRatio(for: split))))
                            }
                            
                            // Split content
                            HStack(spacing: 0) {
                                // Km number only
                                Text("\(split.kmIndex)")
                                    .font(.system(size: 16, weight: .regular))
                                    .frame(width: 60, alignment: .leading)
                                
                                // Pace
                                Text(split.avgPaceSecondsPerKm.toPaceString())
                                    .font(.system(size: 16, weight: .regular))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                // Total time with icons
                                HStack(spacing: 8) {
                                    Text(split.splitTimeSeconds.toTimeString())
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundColor(colorForSplit(split))
                                    
                                    if split.id == fastestSplit?.id {
                                        Image(systemName: "hare.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.green)
                                    } else if split.id == slowestSplit?.id {
                                        Image(systemName: "tortoise.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.orange)
                                    }
                                }
                                .frame(width: 100, alignment: .trailing)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 12)
                        }
                        
                        Divider()
                    }
                }
            }
        }
    }
    
    private func colorForSplit(_ split: Split) -> Color {
        if split.id == fastestSplit?.id {
            return .green
        } else if split.id == slowestSplit?.id {
            return .orange
        }
        return .primary
    }
}


