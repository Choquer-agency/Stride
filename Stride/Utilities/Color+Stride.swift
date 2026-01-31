import SwiftUI

/// Stride brand color tokens
/// Centralizes all brand colors for consistent usage throughout the app
extension Color {
    
    // MARK: - Primary Colors
    
    /// Primary brand color - neon green (#BAFF29)
    /// Use for: Primary actions, current week highlighting, brand accents
    static let stridePrimary = Color(hex: "BAFF29")
    
    /// Light variant of primary color (#F3FFDA)
    /// Use for: Subtle backgrounds, hover states
    static let stridePrimaryLight = Color(hex: "F3FFDA")
    
    // MARK: - Black
    
    /// Stride black - never pure black (#212121)
    /// Use for: Text, borders, shadows instead of Color.black
    static let strideBlack = Color(hex: "212121")
    
    // MARK: - Semantic Colors
    
    /// Success light background (#C8F5D6)
    static let strideSuccessLight = Color(hex: "C8F5D6")
    
    /// Blue light background (#C9E7FF)
    static let strideBlueLight = Color(hex: "C9E7FF")
    
    /// Blue accent (#61B8FF)
    static let strideBlue = Color(hex: "61B8FF")
    
    /// Orange light background (#FFF4CB)
    static let strideOrangeLight = Color(hex: "FFF4CB")
    
    /// Orange accent (#FFCA00)
    static let strideOrange = Color(hex: "FFCA00")
    
    /// Red light background (#F5C8C9)
    static let strideRedLight = Color(hex: "F5C8C9")
    
    /// Red accent (#FF5900)
    static let strideRed = Color(hex: "FF5900")
    
    /// Grey for neutral elements (#E6E6E6)
    static let strideGrey = Color(hex: "E6E6E6")
}
