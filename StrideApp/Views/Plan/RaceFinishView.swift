import SwiftUI

struct RaceFinishView: View {
    let plan: TrainingPlan
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Celebratory header
            ZStack {
                // Background glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.stridePrimary.opacity(0.4), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 120
                        )
                    )
                    .frame(width: 240, height: 240)
                    .scaleEffect(isAnimating ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isAnimating)
                
                // Trophy or finish flag
                VStack(spacing: 12) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 60))
                        .foregroundStyle(Color.stridePrimary)
                        .symbolEffect(.bounce, options: .repeating, value: isAnimating)
                    
                    Text("RACE DAY")
                        .font(.title3.weight(.heavy))
                        .tracking(4)
                        .foregroundStyle(Color.stridePrimary)
                }
            }
            
            // Race Details
            VStack(spacing: 8) {
                Text(plan.raceName ?? plan.raceType.displayName)
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                
                Text(plan.raceDate.formatted(date: .complete, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                if let goalTime = plan.goalTime {
                    HStack(spacing: 8) {
                        Image(systemName: "target")
                            .foregroundStyle(Color.stridePrimary)
                        
                        Text("Goal: \(goalTime)")
                            .font(.headline)
                    }
                    .padding(.top, 8)
                }
            }
            
            // Countdown
            CountdownView(targetDate: plan.raceDate)
                .padding(.vertical, 8)
            
            // Motivational Quote
            VStack(spacing: 8) {
                Text("\"")
                    .font(.system(size: 48, weight: .thin))
                    .foregroundStyle(Color.stridePrimary.opacity(0.5))
                    .offset(y: 10)
                
                Text("The miracle isn't that I finished. The miracle is that I had the courage to start.")
                    .font(.subheadline)
                    .italic()
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                
                Text("— John Bingham")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.stridePrimary.opacity(0.15),
                            Color.stridePrimary.opacity(0.05)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.stridePrimary.opacity(0.3), lineWidth: 1)
                )
        )
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Countdown View
struct CountdownView: View {
    let targetDate: Date
    @State private var timeRemaining: (days: Int, hours: Int, minutes: Int) = (0, 0, 0)
    
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 16) {
            CountdownUnit(value: timeRemaining.days, label: "DAYS")
            
            Text(":")
                .font(.title2.weight(.light))
                .foregroundStyle(.secondary)
            
            CountdownUnit(value: timeRemaining.hours, label: "HRS")
            
            Text(":")
                .font(.title2.weight(.light))
                .foregroundStyle(.secondary)
            
            CountdownUnit(value: timeRemaining.minutes, label: "MIN")
        }
        .onAppear {
            updateTimeRemaining()
        }
        .onReceive(timer) { _ in
            updateTimeRemaining()
        }
    }
    
    private func updateTimeRemaining() {
        let components = Calendar.current.dateComponents(
            [.day, .hour, .minute],
            from: Date(),
            to: targetDate
        )
        
        timeRemaining = (
            max(0, components.day ?? 0),
            max(0, components.hour ?? 0),
            max(0, components.minute ?? 0)
        )
    }
}

// MARK: - Countdown Unit
struct CountdownUnit: View {
    let value: Int
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(String(format: "%02d", value))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .monospacedDigit()
            
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
        }
        .frame(minWidth: 60)
    }
}

#Preview {
    RaceFinishView(plan: {
        let plan = TrainingPlan(
            raceType: .marathon,
            raceDate: Date().addingTimeInterval(86400 * 45),
            raceName: "Boston Marathon 2026",
            goalTime: "3:30:00",
            currentWeeklyMileage: 50,
            longestRecentRun: 20,
            fitnessLevel: .intermediate,
            startDate: Date()
        )
        return plan
    }())
    .padding()
    .background(Color(.systemBackground))
}
