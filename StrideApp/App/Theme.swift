import SwiftUI
import UIKit

// MARK: - Color Theme
extension Color {
    // Brand Colors
    static let stridePrimary = Color(hex: "FF2617")
    static let strideDarkRed = Color(hex: "D40B15")
    static let strideBrandBlack = Color(hex: "221212")
    
    // Legacy aliases for compatibility
    static let strideOrange = stridePrimary
    static let strideCoral = strideDarkRed
    
    // Light mode backgrounds
    static let strideBackground = Color(red: 0.98, green: 0.98, blue: 0.98)
    static let strideCard = Color.white
    static let strideBorder = Color.black.opacity(0.08)
    
    // Workout type colors - Intensity Based
    // Green: Easy, Recovery, Rest
    static let workoutEasy = Color.green
    static let workoutRecovery = Color.green.opacity(0.7)
    static let workoutRest = Color.green.opacity(0.5)
    
    // Yellow: Long, Tempo, Gym
    static let workoutLong = Color.yellow.opacity(0.9)
    static let workoutTempo = Color.orange
    static let workoutGym = Color.yellow.opacity(0.8)
    
    // Red: Intervals, Hills, Race
    static let workoutInterval = Color.red
    static let workoutRace = Color.stridePrimary
}

// MARK: - Typography
extension Font {
    // Legacy system fonts (deprecated - use custom fonts below)
    static let strideTitle = Font.system(size: 28, weight: .bold, design: .rounded)
    static let strideHeadline = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let strideSubheadline = Font.system(size: 16, weight: .medium, design: .rounded)
    static let strideBody = Font.system(size: 15, weight: .regular, design: .default)
    static let strideCaption = Font.system(size: 13, weight: .regular, design: .default)
    
    // MARK: - Custom Fonts
    
    /// Barlow Condensed - Use for numbers, stats, and numeric displays
    static func barlowCondensed(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let fontName: String
        switch weight {
        case .bold, .black, .heavy:
            fontName = "BarlowCondensed-Bold"
        case .semibold:
            fontName = "BarlowCondensed-SemiBold"
        case .medium:
            fontName = "BarlowCondensed-Medium"
        default:
            fontName = "BarlowCondensed-Regular"
        }
        return Font.custom(fontName, size: size)
    }
    
    /// Inter - Use for all body text and UI labels
    static func inter(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let fontName: String
        switch weight {
        case .bold, .black, .heavy:
            fontName = "Inter-Bold"
        case .semibold:
            fontName = "Inter-SemiBold"
        case .medium:
            fontName = "Inter-Medium"
        default:
            fontName = "Inter-Regular"
        }
        return Font.custom(fontName, size: size)
    }
    
    // Convenience helpers
    static func interBody(_ size: CGFloat = 15) -> Font {
        Font.custom("Inter-Regular", size: size)
    }
    
    static func interMedium(_ size: CGFloat = 15) -> Font {
        Font.custom("Inter-Medium", size: size)
    }
    
    static func interSemibold(_ size: CGFloat = 15) -> Font {
        Font.custom("Inter-SemiBold", size: size)
    }
    
    static func interBold(_ size: CGFloat = 15) -> Font {
        Font.custom("Inter-Bold", size: size)
    }
}

// MARK: - Gradients
extension LinearGradient {
    static let strideAccent = LinearGradient(
        colors: [Color.stridePrimary, Color.strideDarkRed],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let strideLight = LinearGradient(
        colors: [Color.strideBackground, Color.strideCard],
        startPoint: .top,
        endPoint: .bottom
    )
    
    // Legacy alias
    static let strideDark = strideLight
}

// MARK: - View Modifiers
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.strideCard)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.strideBorder, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.strideBrandBlack)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                configuration.isPressed 
                    ? Color.strideDarkRed 
                    : Color.stridePrimary
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.strideBorder, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}
