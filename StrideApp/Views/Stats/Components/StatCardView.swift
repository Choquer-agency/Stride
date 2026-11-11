import SwiftUI

struct StatCardView: View {
    let title: String
    let value: String
    let subtitle: String?
    let changeText: String?
    
    init(title: String, value: String, subtitle: String? = nil, changeText: String? = nil) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.changeText = changeText
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.inter(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.barlowCondensed(size: 34, weight: .medium))
                .lineLimit(1).minimumScaleFactor(0.65)
                .foregroundStyle(.primary)
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.inter(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            
            if let changeText = changeText {
                HStack(spacing: 4) {
                    Image(systemName: changeText.hasPrefix("+") ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text(changeText)
                        .font(.inter(size: 11, weight: .medium))
                }
                .foregroundStyle(changeText.hasPrefix("+") ? Color.green : Color.orange)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    HStack(spacing: 12) {
        StatCardView(
            title: "Weekly Distance",
            value: "62 / 66 km",
            subtitle: "94% completed",
            changeText: "+8% vs last week"
        )
        
        StatCardView(
            title: "Year-to-Date",
            value: "412 km",
            subtitle: "in 2026"
        )
    }
    .padding()
}
