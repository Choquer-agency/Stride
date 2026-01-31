import SwiftUI

/// Card displaying current heart rate zone
struct HeartRateZoneCard: View {
    let heartRate: Int?
    let zonesManager: HeartRateZonesManager
    
    private var zoneInfo: (number: Int, label: String, color: Color)? {
        guard let hr = heartRate,
              let zone = zonesManager.getCurrentZone(bpm: hr) else {
            return nil
        }
        
        let color: Color
        switch zone.zoneNumber {
        case 1: color = .blue
        case 2: color = .green
        case 3: color = .yellow
        case 4: color = .orange
        case 5: color = .red
        default: color = .gray
        }
        
        return (number: zone.zoneNumber, label: zone.zoneLabel, color: color)
    }
    
    private var displayText: String {
        if let zone = zoneInfo {
            return "Z\(zone.number) - \(zone.label)"
        }
        return "--"
    }
    
    private var displayColor: Color {
        return zoneInfo?.color ?? .gray
    }
    
    var body: some View {
        VStack(spacing: 4) {
            if let hr = heartRate {
                Text("\(hr)")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundColor(displayColor)
                
                Text("Heart rate zone")
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(.secondary)
                
                Text(displayText)
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(displayColor)
            } else {
                Text("--")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundColor(.gray)
                
                Text("Heart rate zone")
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
