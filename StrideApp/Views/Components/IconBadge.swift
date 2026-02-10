import SwiftUI

// MARK: - Icon Badge
struct IconBadge: View {
    let icon: String
    let color: Color
    var size: CGFloat = 40
    
    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.2))
                .frame(width: size, height: size)
            
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundColor(color)
        }
    }
}

// MARK: - Animated Check Icon
struct AnimatedCheckIcon: View {
    let isChecked: Bool
    var size: CGFloat = 24
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(isChecked ? Color.green : Color.secondary.opacity(0.3), lineWidth: 2)
                .frame(width: size, height: size)
            
            if isChecked {
                Circle()
                    .fill(Color.green)
                    .frame(width: size, height: size)
                    .transition(.scale.combined(with: .opacity))
                
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundColor(.white)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.strideSpring, value: isChecked)
    }
}

// MARK: - Pulse Animation Modifier
struct PulseModifier: ViewModifier {
    @State private var isPulsing = false
    let duration: Double
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.05 : 1.0)
            .opacity(isPulsing ? 0.8 : 1.0)
            .animation(
                Animation.easeInOut(duration: duration)
                    .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}

extension View {
    func pulse(duration: Double = 1.0) -> some View {
        modifier(PulseModifier(duration: duration))
    }
}

// MARK: - Shimmer Effect
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.3),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: -geometry.size.width + phase * geometry.size.width * 3)
                }
                .mask(content)
            )
            .onAppear {
                withAnimation(
                    .linear(duration: 1.5)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Floating Action Button
struct FloatingActionButton: View {
    let icon: String
    let action: () -> Void
    var size: CGFloat = 56
    
    var body: some View {
        Button(action: {
            Haptics.impact(.medium)
            action()
        }) {
            ZStack {
                Circle()
                    .fill(Color.stridePrimary)
                    .frame(width: size, height: size)
                    .shadow(color: Color.stridePrimary.opacity(0.4), radius: 8, y: 4)
                
                Image(systemName: icon)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundColor(.strideBrandBlack)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Badge View
struct BadgeView: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .foregroundColor(.white)
            .clipShape(Capsule())
    }
}

// MARK: - Empty State Component
struct EmptyStateComponent: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.stridePrimary.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundStyle(Color.stridePrimary)
            }
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.stridePrimary)
                        .foregroundColor(.strideBrandBlack)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(40)
    }
}

#Preview {
    VStack(spacing: 40) {
        HStack(spacing: 20) {
            IconBadge(icon: "figure.run", color: .workoutEasy)
            IconBadge(icon: "flame", color: .workoutTempo)
            IconBadge(icon: "timer", color: .workoutInterval)
        }
        
        HStack(spacing: 20) {
            AnimatedCheckIcon(isChecked: false)
            AnimatedCheckIcon(isChecked: true)
        }
        
        FloatingActionButton(icon: "plus") {}
        
        BadgeView(text: "NEW", color: .stridePrimary)
        
        EmptyStateComponent(
            icon: "figure.run",
            title: "No Workouts",
            subtitle: "Complete your first workout to see it here",
            actionTitle: "Get Started"
        ) {}
    }
    .padding()
    .background(Color(.systemBackground))
}
