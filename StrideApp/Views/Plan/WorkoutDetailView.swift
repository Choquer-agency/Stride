import SwiftUI

// Preference key to measure content height inside ScrollView
private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct WorkoutDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let workout: Workout
    let onComplete: () -> Void
    
    @State private var contentHeight: CGFloat = 0
    
    // Height of the drag indicator + close button area
    private let chromeHeight: CGFloat = 6
    
    private var sheetHeight: CGFloat {
        guard contentHeight > 0 else { return 400 }
        let total = contentHeight + chromeHeight
        let maxHeight = UIScreen.main.bounds.height * 0.85
        return min(total, maxHeight)
    }
    
    // Parse workout details into individual steps
    private var workoutSteps: [String] {
        guard let details = workout.details, !details.isEmpty else { return [] }
        
        // Split by common separators: periods, "then", or newlines
        let separators = CharacterSet(charactersIn: ".\n")
        let steps = details
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { step in
                // Remove empty steps and separator-only lines (underscores, dashes, etc.)
                !step.isEmpty && !step.allSatisfy { "—–-_=~─━".contains($0) }
            }
        
        return steps
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
            
            // Close button (X icon on right)
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    CloseIconView(size: 12, color: .primary)
                        .padding(10)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            
            // Content
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Flag Icon Header
                    FlagIconView(size: 24)
                        .foregroundColor(.primary)
                    
                    // Workout Type Badge
                    HStack(spacing: 8) {
                        Circle()
                            .fill(workout.typeColor)
                            .frame(width: 16, height: 16)
                        
                        Text(workout.workoutType.displayName)
                            .font(.inter(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    
                    // Main Stats - Distance & Pace (or Duration for gym/non-run workouts)
                    HStack(alignment: .top, spacing: 40) {
                        // Distance
                        if let distanceKm = workout.distanceKm {
                            VStack(spacing: 4) {
                                Text(distanceKm == floor(distanceKm) ? "\(Int(distanceKm)) km" : String(format: "%.1f km", distanceKm))
                                    .font(.barlowCondensed(size: 56, weight: .medium))
                                    .foregroundStyle(.primary)
                                
                                Text("Distance")
                                    .font(.inter(size: 14, weight: .regular))
                                    .foregroundStyle(.secondary)
                            }
                        } else if let duration = workout.durationDisplay {
                            // Show duration prominently when no distance (gym, cross-training)
                            VStack(spacing: 4) {
                                Text(duration)
                                    .font(.barlowCondensed(size: 56, weight: .medium))
                                    .foregroundStyle(.primary)
                                
                                Text("Duration")
                                    .font(.inter(size: 14, weight: .regular))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        // Pace
                        if let pace = workout.paceDescription {
                            VStack(spacing: 4) {
                                Text(pace)
                                    .font(.barlowCondensed(size: 56, weight: .medium))
                                    .foregroundStyle(.primary)
                                
                                Text("Pace")
                                    .font(.inter(size: 14, weight: .regular))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    // Workout Details Card
                    if !workoutSteps.isEmpty || (workout.details != nil && !workout.details!.isEmpty) {
                        VStack(spacing: 12) {
                            // Header with treadmill icon - centered
                            HStack(spacing: 8) {
                                if workout.workoutType.isRunRelated {
                                    TreadmillIconView(size: 20, color: .primary)
                                } else {
                                    Image(systemName: workout.workoutType.icon)
                                        .font(.system(size: 18))
                                        .foregroundColor(.primary)
                                }
                                
                                Text("Workout Details")
                                    .font(.interSemibold(15))
                                    .foregroundStyle(.primary)
                            }
                            
                            // Workout steps as line items - centered
                            if workoutSteps.count > 1 {
                                VStack(spacing: 8) {
                                    ForEach(Array(workoutSteps.enumerated()), id: \.offset) { index, step in
                                        Text(step)
                                            .font(.inter(size: 14, weight: .regular))
                                            .foregroundStyle(.secondary)
                                            .lineSpacing(2)
                                            .multilineTextAlignment(.center)
                                    }
                                }
                            } else if let details = workout.details {
                                // Single line or no clear separation
                                Text(details)
                                    .font(.inter(size: 14, weight: .regular))
                                    .foregroundStyle(.secondary)
                                    .lineSpacing(3)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
                        .padding(.horizontal, 16)
                    }
                    
                    // Bottom Action Button
                    if workout.workoutType != .rest {
                        Button(action: {
                            onComplete()
                            dismiss()
                        }) {
                            Text(workout.isCompleted ? "Completed" : "Start Workout")
                                .font(.interSemibold(16))
                                .foregroundColor(.white)
                                .frame(width: UIScreen.main.bounds.width * 0.52)
                                .padding(.vertical, 18)
                                .background(Color.stridePrimary)
                                .clipShape(Capsule())
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                    }
                )
            }
        }
        .background(Color(.systemGroupedBackground))
        .onPreferenceChange(ContentHeightKey.self) { height in
            contentHeight = height
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - WorkoutType Extension
extension WorkoutType {
    var isRunRelated: Bool {
        switch self {
        case .easyRun, .longRun, .tempoRun, .intervals, .hillRepeats, .recovery, .race:
            return true
        case .rest, .crossTraining, .gym:
            return false
        }
    }
}

#Preview {
    WorkoutDetailView(
        workout: Workout(
            date: Date(),
            workoutType: .tempoRun,
            title: "Threshold Run",
            details: "Warm up for 10 minutes at easy pace. Run 10km at threshold pace. Cool down for 10 minutes",
            distanceKm: 12,
            durationMinutes: 60,
            paceDescription: "5:15/km"
        ),
        onComplete: {}
    )
}
