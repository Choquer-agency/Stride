import SwiftUI

/// Reusable component displaying training pace zones from baseline assessment
struct TrainingPacesCard: View {
    let paces: TrainingPaces
    let vdot: Double
    let assessmentContext: String? // e.g., "from your recent 5K time trial"
    
    @State private var showRacePredictions = false
    @State private var showVDOTInfo = false
    
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with VDOT
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Training Paces")
                        .font(.system(size: 20, weight: .bold))
                    
                    if let context = assessmentContext {
                        Text(context)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // VDOT with info button
                HStack(spacing: 4) {
                    Text("VDOT \(Int(vdot))")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.stridePrimary)
                    
                    Button(action: {
                        showVDOTInfo = true
                    }) {
                        Image(systemName: "questionmark.circle")
                            .foregroundColor(.secondary)
                            .font(.system(size: 16))
                    }
                }
            }
            
            // Pace zones
            VStack(spacing: 12) {
                PaceZoneRow(
                    title: "Easy",
                    pace: paces.easy.displayRange,
                    description: "Recovery runs, easy days",
                    color: .blue
                )
                
                PaceZoneRow(
                    title: "Long Run",
                    pace: paces.longRun.displayRange,
                    description: "Sunday long runs, aerobic building",
                    color: .green
                )
                
                PaceZoneRow(
                    title: "Threshold",
                    pace: paces.threshold.toPaceString() + "/km",
                    description: "Tempo runs, cruise intervals, comfortably hard",
                    color: .orange
                )
                
                PaceZoneRow(
                    title: "Interval",
                    pace: paces.interval.toPaceString() + "/km",
                    description: "VO2max work, hard 3-5min efforts",
                    color: .red
                )
                
                PaceZoneRow(
                    title: "Repetition",
                    pace: paces.repetition.toPaceString() + "/km",
                    description: "Speed work, short fast reps",
                    color: .purple
                )
                
                if let racePace = paces.racePace {
                    PaceZoneRow(
                        title: "Race Pace",
                        pace: racePace.toPaceString() + "/km",
                        description: "Your goal race pace",
                        color: .stridePrimary
                    )
                }
            }
            
            // Race predictions toggle
            Button(action: {
                withAnimation {
                    showRacePredictions.toggle()
                }
            }) {
                HStack {
                    Text("Race Time Predictions")
                        .font(.system(size: 16, weight: .medium))
                    
                    Spacer()
                    
                    Image(systemName: showRacePredictions ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14))
                }
                .foregroundColor(.primary)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            
            if showRacePredictions {
                racePredictionsView
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.strideBlack.opacity(0.1), radius: 8, x: 0, y: 2)
        .sheet(isPresented: $showVDOTInfo) {
            VDOTInfoSheet()
        }
    }
    
    // MARK: - Race Predictions View
    
    private var racePredictionsView: some View {
        let predictions = VDOTCalculator.predictRaceTimes(vdot: vdot)
        
        return VStack(spacing: 8) {
            ForEach(Array(predictions.sorted(by: { $0.key < $1.key })), id: \.key) { distance, time in
                HStack {
                    Text(distance)
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text(time.toTimeString())
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Pace Zone Row

struct PaceZoneRow: View {
    let title: String
    let pace: String
    let description: String
    let color: Color
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Color indicator
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .padding(.top, 4)
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                    
                    Spacer()
                    
                    Text(pace)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(color)
                }
                
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - VDOT Info Sheet

struct VDOTInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("What is VDOT?")
                        .font(.system(size: 24, weight: .bold))
                    
                    Text("VDOT is a fitness metric developed by legendary running coach Jack Daniels. It represents your running economy and aerobic capacity.")
                        .font(.system(size: 16))
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Understanding Your Number")
                            .font(.system(size: 18, weight: .semibold))
                        
                        Text("• VDOT 30-40: Beginner runner\n• VDOT 40-50: Recreational runner\n• VDOT 50-60: Competitive runner\n• VDOT 60-70: Advanced runner\n• VDOT 70+: Elite runner")
                            .font(.system(size: 15))
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How It's Used")
                            .font(.system(size: 18, weight: .semibold))
                        
                        Text("Your VDOT determines your personalized training paces for different workout types. These paces are scientifically calibrated to help you improve fitness while avoiding overtraining.")
                            .font(.system(size: 15))
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Improving Your VDOT")
                            .font(.system(size: 18, weight: .semibold))
                        
                        Text("As you train consistently and complete workouts at your prescribed paces, your VDOT will naturally improve over time. Retake your baseline test every 8-12 weeks to track progress.")
                            .font(.system(size: 15))
                    }
                }
                .padding()
            }
            .navigationTitle("About VDOT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let samplePaces = TrainingPaces(
        easy: PaceRange(min: 330, max: 390),
        longRun: PaceRange(min: 318, max: 330),
        threshold: 285,
        interval: 255,
        repetition: 240,
        racePace: 270
    )
    
    return TrainingPacesCard(
        paces: samplePaces,
        vdot: 52.5,
        assessmentContext: "from your recent 5K time trial"
    )
    .padding()
}
