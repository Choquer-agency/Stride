import SwiftUI

/// A cool AI-inspired loader with orbiting colored circles, glass overlay, and rotating rings.
/// Adapted from CSS animation to native SwiftUI.
struct AILoaderView: View {
    var size: CGFloat = 32
    
    @State private var animationPhase: Double = 0
    @State private var pulsePhase: Double = 0
    @State private var ringRotation: Double = 0
    @State private var ringRotation2: Double = 0
    
    // Scale factor relative to the size parameter
    private var scale: CGFloat { size / 32.0 }
    
    var body: some View {
        ZStack {
            // Background glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.stridePrimary.opacity(0.08),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 1.2
                    )
                )
                .frame(width: size * 2.5, height: size * 2.5)
            
            // Main container circle
            ZStack {
                // Base color
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.75, green: 0.45, blue: 0.55),
                                Color(red: 0.65, green: 0.35, blue: 0.50)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Orbiting circles
                orbitingCircles
                
                // Rotating rings
                rotatingRings
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            
            // Glass overlay
            glassOverlay
        }
        .frame(width: size * 1.1, height: size * 1.1)
        .onAppear {
            startAnimations()
        }
    }
    
    // MARK: - Orbiting Circles
    private var orbitingCircles: some View {
        let radius = size * 0.2
        
        return ZStack {
            // Circle 4 (deep red/purple - background)
            Circle()
                .fill(Color(red: 0.55, green: 0.20, blue: 0.25))
                .frame(width: size * 0.3, height: size * 0.3)
                .offset(
                    x: cos(animationPhase + .pi * 0.0) * radius,
                    y: sin(animationPhase + .pi * 0.0) * radius
                )
                .scaleEffect(0.6 + pulsePhase * 0.4)
                .opacity(0.9)
            
            // Circle 1 (coral/red - largest)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.85, green: 0.30, blue: 0.35),
                            Color(red: 0.60, green: 0.25, blue: 0.40)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.25
                    )
                )
                .frame(width: size * 0.5, height: size * 0.5)
                .offset(
                    x: cos(animationPhase + .pi * 0.5) * radius + size * 0.03,
                    y: sin(animationPhase + .pi * 0.5) * radius
                )
                .scaleEffect(0.6 + pulsePhase * 0.5)
                .opacity(0.9)
            
            // Circle 2 (warm red/orange)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.90, green: 0.35, blue: 0.30),
                            Color(red: 0.80, green: 0.45, blue: 0.50)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.2
                    )
                )
                .frame(width: size * 0.45, height: size * 0.45)
                .offset(
                    x: cos(animationPhase + .pi * 1.0) * radius,
                    y: sin(animationPhase + .pi * 1.0) * radius
                )
                .scaleEffect(0.6 + pulsePhase * 0.4)
                .opacity(0.85)
            
            // Circle 3 (subtle pink accent - smallest)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.90, green: 0.50, blue: 0.55),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.1
                    )
                )
                .frame(width: size * 0.15, height: size * 0.15)
                .offset(
                    x: cos(animationPhase + .pi * 1.5) * radius - size * 0.03,
                    y: sin(animationPhase + .pi * 1.5) * radius
                )
                .scaleEffect(0.6 + pulsePhase * 0.3)
                .opacity(0.6)
        }
    }
    
    // MARK: - Rotating Rings
    private var rotatingRings: some View {
        ZStack {
            // Ring 1
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            Color.white.opacity(0.3),
                            Color.stridePrimary.opacity(0.2),
                            Color(red: 0.7, green: 0.3, blue: 0.5).opacity(0.3),
                            Color.white.opacity(0.1)
                        ],
                        center: .center
                    ),
                    lineWidth: size * 0.04
                )
                .frame(width: size * 0.85, height: size * 0.85)
                .rotation3DEffect(.degrees(ringRotation), axis: (x: 0.5, y: 1, z: 0))
                .opacity(0.7)
            
            // Ring 2
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            Color.stridePrimary.opacity(0.2),
                            Color.white.opacity(0.3),
                            Color(red: 0.5, green: 0.2, blue: 0.4).opacity(0.2),
                            Color.white.opacity(0.1)
                        ],
                        center: .center
                    ),
                    lineWidth: size * 0.03
                )
                .frame(width: size * 0.9, height: size * 0.9)
                .rotation3DEffect(.degrees(ringRotation2), axis: (x: 1, y: 0.5, z: 0))
                .opacity(0.5)
        }
    }
    
    // MARK: - Glass Overlay
    private var glassOverlay: some View {
        ZStack {
            // Main glass
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: size, height: size)
            
            // Highlight
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.35),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.7, y: 0.3),
                        startRadius: 0,
                        endRadius: size * 0.4
                    )
                )
                .frame(width: size, height: size)
            
            // Subtle border
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: size * 0.03)
                .frame(width: size, height: size)
        }
    }
    
    // MARK: - Animations
    private func startAnimations() {
        // Orbiting animation - continuous rotation
        withAnimation(
            .linear(duration: 5.5)
            .repeatForever(autoreverses: false)
        ) {
            animationPhase = .pi * 2
        }
        
        // Pulse animation
        withAnimation(
            .easeInOut(duration: 2.75)
            .repeatForever(autoreverses: true)
        ) {
            pulsePhase = 1.0
        }
        
        // Ring rotation 1
        withAnimation(
            .linear(duration: 8)
            .repeatForever(autoreverses: false)
        ) {
            ringRotation = 360
        }
        
        // Ring rotation 2
        withAnimation(
            .linear(duration: 6)
            .repeatForever(autoreverses: false)
        ) {
            ringRotation2 = 360
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        AILoaderView(size: 32)
        AILoaderView(size: 64)
        AILoaderView(size: 100)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemBackground))
}
