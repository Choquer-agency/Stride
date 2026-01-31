import SwiftUI

/// Detailed view of a single workout with Nike-inspired layout
struct HistoryWorkoutDetailView: View {
    @ObservedObject var storageManager: StorageManager
    let session: WorkoutSession
    
    @State private var localSession: WorkoutSession
    @State private var showingTitleEditor = false
    @State private var showingEffortRating = false
    @State private var showingNotesEditor = false
    @State private var editedTitle: String
    @State private var workoutFeedback: WorkoutFeedback?
    
    init(session: WorkoutSession, storageManager: StorageManager) {
        self.session = session
        self.storageManager = storageManager
        self._localSession = State(initialValue: session)
        self._editedTitle = State(initialValue: session.workoutTitle ?? session.startTime.toDefaultWorkoutTitle())
        
        // Load workout feedback if available
        self._workoutFeedback = State(initialValue: storageManager.loadWorkoutFeedback(sessionId: session.id))
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 1. Header Section
                VStack(alignment: .leading, spacing: 8) {
                    // Date in small secondary font
                    Text(localSession.startTime.toDateOnlyString())
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(.secondary)
                    
                    // Editable title with pencil icon
                    HStack(alignment: .center, spacing: 12) {
                        Text(editedTitle)
                            .font(.system(size: 28, weight: .semibold))
                        
                        Button(action: {
                            showingTitleEditor = true
                        }) {
                            Image(systemName: "pencil")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                // 2. Hero Distance Display
                VStack(spacing: 8) {
                    Text(String(format: "%.2f", localSession.totalDistanceKm))
                        .font(.system(size: 72, weight: .medium))
                        .minimumScaleFactor(0.5)
                    Text("Kilometers")
                        .font(.system(size: 16, weight: .light))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                
                // 3. Key Stats Row (3 columns)
                HStack(spacing: 0) {
                    VStack(spacing: 8) {
                        Text(localSession.avgPaceSecondsPerKm.toPaceString())
                            .font(.system(size: 24, weight: .medium))
                        Text("Avg. pace")
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    
                    VStack(spacing: 8) {
                        Text(localSession.durationSeconds.toTimeString())
                            .font(.system(size: 24, weight: .medium))
                        Text("Time")
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    
                    VStack(spacing: 8) {
                        Text("\(localSession.estimatedCalories)")
                            .font(.system(size: 24, weight: .medium))
                        Text("Calories")
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal)
                
                // 4. Secondary Stats Row (Cadence if available)
                if let avgCadence = averageCadence() {
                    HStack(spacing: 20) {
                        VStack(spacing: 8) {
                            Text("\(Int(avgCadence))")
                                .font(.system(size: 24, weight: .medium))
                            Text("Cadence")
                                .font(.system(size: 14, weight: .light))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                }
                
                Divider()
                    .padding(.horizontal)
                
                // 5. Kilometer Splits Table - 4 columns (matching RunTab)
                if !localSession.splits.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Kilometer splits")
                            .font(.system(size: 18, weight: .semibold))
                            .padding(.horizontal)
                        
                        // Table Header
                        HStack(spacing: 0) {
                            Text("KM")
                                .font(.system(size: 14, weight: .light))
                                .foregroundColor(.secondary)
                                .frame(width: 40, alignment: .leading)
                            
                            Spacer()
                                .frame(width: 12)
                            
                            // Bar column has no header
                            Spacer()
                                .frame(width: 100)
                            
                            Spacer()
                                .frame(width: 12)
                            
                            Text("Pace")
                                .font(.system(size: 14, weight: .light))
                                .foregroundColor(.secondary)
                                .frame(width: 90, alignment: .leading)
                            
                            Text("Time")
                                .font(.system(size: 14, weight: .light))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding(.horizontal)
                        
                        // Divider line
                        Rectangle()
                            .fill(Color.stridePrimary)
                            .frame(height: 1)
                            .padding(.horizontal)
                        
                        // Splits list
                        LazyVStack(spacing: 0) {
                            ForEach(Array(localSession.splits.enumerated()), id: \.element.id) { index, split in
                                HistorySplitRowView(
                                    split: split,
                                    splits: localSession.splits,
                                    cumulativeTime: calculateCumulativeTime(upToIndex: index, splits: localSession.splits),
                                    primaryColor: .stridePrimary
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                Divider()
                    .padding(.horizontal)
                
                // 6. Workout Feedback Section (if available)
                if let feedback = workoutFeedback {
                    workoutFeedbackSection(feedback)
                    
                    Divider()
                        .padding(.horizontal)
                }
                
                // 7. My Effort Section
                Button(action: {
                    showingEffortRating = true
                }) {
                    HStack {
                        Text("My effort")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        if let effort = localSession.effortRating {
                            HStack(spacing: 8) {
                                Text("\(effort)/10")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.primary)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 20))
                                .foregroundColor(.stridePrimary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 16)
                }
                
                Divider()
                    .padding(.horizontal)
                
                // 8. Notes Section
                Button(action: {
                    showingNotesEditor = true
                }) {
                    HStack {
                        Text("Notes")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        if let notes = localSession.notes, !notes.isEmpty {
                            HStack(spacing: 8) {
                                Text(notes)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: 150, alignment: .trailing)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 20))
                                .foregroundColor(.stridePrimary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 16)
                }
                
                Divider()
                    .padding(.horizontal)
                
                // Bottom spacer for better scrolling
                Spacer()
                    .frame(height: 100)
            }
            .padding(.vertical)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingTitleEditor) {
            NavigationStack {
                VStack(spacing: 16) {
                    TextField("Workout title", text: $editedTitle)
                        .font(.system(size: 18, weight: .regular))
                        .textFieldStyle(.roundedBorder)
                        .padding()
                    
                    Spacer()
                }
                .navigationTitle("Edit title")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            editedTitle = localSession.workoutTitle ?? localSession.startTime.toDefaultWorkoutTitle()
                            showingTitleEditor = false
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            localSession.workoutTitle = editedTitle
                            saveChanges()
                            showingTitleEditor = false
                        }
                        .fontWeight(.semibold)
                        .foregroundColor(.stridePrimary)
                    }
                }
            }
        }
        .sheet(isPresented: $showingEffortRating) {
            EffortRatingView(effortRating: Binding(
                get: { localSession.effortRating },
                set: { newValue in
                    localSession.effortRating = newValue
                    saveChanges()
                }
            ))
        }
        .sheet(isPresented: $showingNotesEditor) {
            NotesEditorView(notes: Binding(
                get: { localSession.notes },
                set: { newValue in
                    localSession.notes = newValue
                    saveChanges()
                }
            ))
        }
    }
    
    private func averageCadence() -> Double? {
        // Calculate from splits data if available
        let cadences = localSession.splits.compactMap { $0.avgCadence }
        guard !cadences.isEmpty else {
            // Fallback to samples if splits don't have cadence data (legacy workouts)
            let sampleCadences = localSession.recentSamples.compactMap { $0.cadenceSpm }
            guard !sampleCadences.isEmpty else { return nil }
            return sampleCadences.reduce(0, +) / Double(sampleCadences.count)
        }
        return cadences.reduce(0, +) / Double(cadences.count)
    }
    
    private func workoutFeedbackSection(_ feedback: WorkoutFeedback) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Workout feedback")
                .font(.system(size: 18, weight: .semibold))
                .padding(.horizontal)
            
            VStack(spacing: 16) {
                // Completion Status
                HStack {
                    Image(systemName: iconForCompletionStatus(feedback.completionStatus))
                        .foregroundColor(colorForCompletionStatus(feedback.completionStatus))
                    Text(feedback.completionStatus.displayName)
                        .font(.system(size: 16))
                    Spacer()
                }
                
                Divider()
                
                // Metrics Row
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Effort")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Text("\(feedback.perceivedEffort)/10")
                            .font(.system(size: 16, weight: .medium))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fatigue")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Text("\(feedback.fatigueLevel)/5")
                            .font(.system(size: 16, weight: .medium))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pain")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Text("\(feedback.painLevel)/10")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color(feedback.painSeverity.color))
                    }
                    
                    Spacer()
                }
                
                // Pace Adherence (runs only)
                if let paceAdherence = feedback.paceAdherence {
                    Divider()
                    
                    HStack {
                        Image(systemName: "speedometer")
                            .foregroundColor(Color(paceAdherence.color))
                        Text("Pace: \(paceAdherence.displayName)")
                            .font(.system(size: 16))
                            .foregroundColor(Color(paceAdherence.color))
                        Spacer()
                    }
                }
                
                // Pain Areas (if any)
                if let painAreas = feedback.painAreas, !painAreas.isEmpty {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pain areas:")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        
                        FlowLayout(spacing: 8) {
                            ForEach(painAreas, id: \.self) { area in
                                Text(area.displayName)
                                    .font(.system(size: 12, weight: .medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.2))
                                    .foregroundColor(.orange)
                                    .cornerRadius(6)
                            }
                        }
                    }
                }
                
                // Gym-specific feedback
                if let weightFeel = feedback.weightFeel {
                    Divider()
                    
                    HStack {
                        Image(systemName: "dumbbell.fill")
                            .foregroundColor(.stridePrimary)
                        Text("Weights felt: \(weightFeel.displayName)")
                            .font(.system(size: 16))
                        Spacer()
                    }
                }
                
                if let formBreakdown = feedback.formBreakdown {
                    Divider()
                    
                    HStack {
                        Image(systemName: formBreakdown ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundColor(formBreakdown ? .orange : .green)
                        Text("Form: \(formBreakdown ? "Broke down" : "Held strong")")
                            .font(.system(size: 16))
                        Spacer()
                    }
                }
                
                // Coach Notes
                if let notes = feedback.notes, !notes.isEmpty {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Coach notes:")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Text(notes)
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }
    
    private func iconForCompletionStatus(_ status: WorkoutCompletionStatus) -> String {
        switch status {
        case .completedAsPlanned: return "checkmark.circle.fill"
        case .completedModified: return "checkmark.circle"
        case .skipped: return "xmark.circle"
        case .stoppedEarly: return "pause.circle"
        }
    }
    
    private func colorForCompletionStatus(_ status: WorkoutCompletionStatus) -> Color {
        switch status {
        case .completedAsPlanned: return .green
        case .completedModified: return .stridePrimary
        case .skipped: return .orange
        case .stoppedEarly: return .yellow
        }
    }
    
    private func saveChanges() {
        storageManager.updateWorkout(localSession)
    }
    
    // Calculate cumulative time from start to the end of the given split index
    private func calculateCumulativeTime(upToIndex index: Int, splits: [Split]) -> Double {
        var cumulativeTime: Double = 0
        for i in 0...index {
            cumulativeTime += splits[i].splitTimeSeconds
        }
        return cumulativeTime
    }
}


struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

/// Individual split row with 4 columns: KM, Bar, Pace, Time (matching RunTab style)
struct HistorySplitRowView: View {
    let split: Split
    let splits: [Split]
    let cumulativeTime: Double
    let primaryColor: Color
    
    // Calculate relative bar width based on pace (faster = longer)
    private var barWidthRatio: CGFloat {
        guard let fastest = splits.min(by: { $0.avgPaceSecondsPerKm < $1.avgPaceSecondsPerKm })?.avgPaceSecondsPerKm,
              let slowest = splits.max(by: { $0.avgPaceSecondsPerKm < $1.avgPaceSecondsPerKm })?.avgPaceSecondsPerKm,
              slowest > fastest else {
            return 0.5
        }
        
        // Invert: faster pace (lower seconds) = longer bar
        let range = slowest - fastest
        let position = slowest - split.avgPaceSecondsPerKm
        
        if range > 0 {
            // Scale from 0.3 (slowest) to 1.0 (fastest)
            return CGFloat(0.3 + (position / range) * 0.7)
        }
        
        return 1.0
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // KM column
            Text("\(split.kmIndex)")
                .font(.system(size: 16, weight: .regular))
                .frame(width: 40, alignment: .leading)
            
            // Left spacing
            Spacer()
                .frame(width: 12)
            
            // Bar column
            RoundedRectangle(cornerRadius: 2)
                .fill(primaryColor)
                .frame(width: 100 * barWidthRatio, height: 8)
                .frame(width: 100, alignment: .leading)
            
            // Right spacing
            Spacer()
                .frame(width: 12)
            
            // Pace column
            Text(split.avgPaceSecondsPerKm.toPaceString())
                .font(.system(size: 16, weight: .regular))
                .frame(width: 90, alignment: .leading)
            
            // Time column (cumulative)
            Text(cumulativeTime.toTimeString())
                .font(.system(size: 16, weight: .regular))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 12)
    }
}
