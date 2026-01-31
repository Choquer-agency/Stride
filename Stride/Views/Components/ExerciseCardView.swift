import SwiftUI

/// Expandable card showing exercise details
struct ExerciseCardView: View {
    let exercise: Exercise
    let assignment: ExerciseAssignment
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsed state - always visible
            collapsedContent
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                }
            
            // Expanded state - shown when tapped
            if isExpanded {
                expandedContent
                    .padding()
                    .background(Color(.systemGray5))
                    .cornerRadius(bottomLeft: 12, bottomRight: 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    // MARK: - Collapsed Content
    
    private var collapsedContent: some View {
        HStack(alignment: .top, spacing: 12) {
            // Exercise icon
            Image(systemName: exercise.imageName)
                .font(.system(size: 24))
                .foregroundColor(.green)
                .frame(width: 40, height: 40)
            
            // Exercise info
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(assignment.fullDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if let loadString = assignment.loadDisplayString {
                    Text(loadString)
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            
            Spacer()
            
            // Expand indicator
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Expanded Content
    
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
            
            // Why it helps runners
            detailSection(
                title: "Why This Helps Runners",
                icon: "figure.run",
                content: exercise.whyItHelpsRunners
            )
            
            // Load guidance
            detailSection(
                title: "Load Guidance",
                icon: "scalemass",
                content: exercise.loadGuidance
            )
            
            // Coaching cues
            if !exercise.coachingCues.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.green)
                        Text("Coaching Cues")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    
                    ForEach(exercise.coachingCues, id: \.self) { cue in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(cue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // Common mistakes
            if !exercise.commonMistakes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("Common Mistakes")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    
                    ForEach(exercise.commonMistakes, id: \.self) { mistake in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(mistake)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // Equipment badge
            if !exercise.requiredEquipment.contains(.none) {
                HStack(spacing: 8) {
                    Image(systemName: "dumbbell")
                        .foregroundColor(.brown)
                    Text("Equipment: " + exercise.requiredEquipment.map { $0.displayName }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.systemGray4))
                .cornerRadius(8)
            }
            
            // Contraindications warning
            if !exercise.avoidIf.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Avoid if experiencing:")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                        Text(exercise.avoidIf.map { $0.displayName }.joined(separator: ", ") + " pain")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
    
    // MARK: - Helper Views
    
    private func detailSection(title: String, icon: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.green)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            
            Text(content)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Corner Radius Extension

extension View {
    func cornerRadius(bottomLeft: CGFloat = 0, bottomRight: CGFloat = 0) -> some View {
        clipShape(RoundedCorner(radius: bottomLeft, corners: [.bottomLeft, .bottomRight]))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Preview

#Preview {
    let exercise = Exercise(
        slug: "bulgarian_split_squat",
        name: "Bulgarian Split Squat",
        category: .strength,
        primaryMuscles: [.quads, .glutes],
        secondaryMuscles: [.hamstrings],
        runnerBenefit: .powerDevelopment,
        supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon],
        injuryPreventionTags: [.knee],
        defaultSets: 3,
        defaultReps: 8...12,
        defaultRestSeconds: 90,
        loadType: .fixedRecommendation,
        loadGuidance: "Use a weight you could lift 10-12 times with good form",
        whyItHelpsRunners: "Builds single-leg strength and balance critical for running efficiency.",
        commonMistakes: ["Letting front knee collapse inward", "Leaning too far forward"],
        coachingCues: ["Keep front knee tracking over toes", "Drive through front heel"],
        requiredEquipment: [.dumbbells],
        alternativeExercises: ["reverse_lunge"],
        movementPattern: .lunge
    )
    
    let assignment = ExerciseAssignment(
        exerciseSlug: "bulgarian_split_squat",
        order: 1,
        sets: 3,
        reps: 8...12,
        restSeconds: 90,
        rpeTarget: 7.5
    )
    
    return ScrollView {
        VStack(spacing: 16) {
            ExerciseCardView(exercise: exercise, assignment: assignment)
        }
        .padding()
    }
}
