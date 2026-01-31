import SwiftUI

/// Settings view for training availability configuration
struct AvailabilitySettingsView: View {
    @ObservedObject var storageManager: StorageManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var availability: TrainingAvailability
    @State private var hasChanges = false
    @State private var showSaveConfirmation = false
    
    init(storageManager: StorageManager) {
        self.storageManager = storageManager
        
        // Load existing preferences or use defaults
        let preferences = storageManager.loadTrainingPreferences()
        _availability = State(initialValue: preferences.getEffectiveAvailability())
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection
                
                // Week selector
                weekSelectorSection
                
                // Warning if no training days
                if availability.totalAvailableDays == 0 {
                    warningSection
                }
                
                // Long run day selector
                longRunDaySection
                
                // Double days toggle
                doubleDaysToggleSection
                
                Spacer(minLength: 40)
            }
            .padding()
        }
        .navigationTitle("Training Availability")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(hasChanges)
        .toolbar {
            if hasChanges {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAvailability()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .alert("Saved", isPresented: $showSaveConfirmation) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Your training availability has been updated.")
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Training Days")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text("Select which days you can train, must rest, or have unavailable")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Week Selector
    
    private var weekSelectorSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Week Schedule")
                .font(.headline)
            
            HStack(spacing: 12) {
                ForEach(0..<7, id: \.self) { dayIndex in
                    dayButton(for: dayIndex)
                }
            }
            
            // Legend
            VStack(spacing: 8) {
                legendItem(icon: "checkmark.circle.fill", color: .green, label: "Training day")
                legendItem(icon: "moon.fill", color: .orange, label: "Rest day (hard constraint)")
                legendItem(icon: "circle", color: .gray, label: "Unavailable (blank)")
            }
            .font(.caption)
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func dayButton(for dayIndex: Int) -> some View {
        let state = availability.stateForDay(dayIndex)
        
        return Button(action: {
            toggleDayState(dayIndex)
        }) {
            VStack(spacing: 6) {
                // Icon
                stateIcon(for: state)
                    .font(.title2)
                    .foregroundColor(stateColor(for: state))
                    .frame(height: 32)
                
                // Day label
                Text(TrainingAvailability.shortDayName(for: dayIndex))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(stateBackgroundColor(for: state))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(stateBorderColor(for: state), lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func stateIcon(for state: DayState) -> some View {
        Group {
            switch state {
            case .available:
                Image(systemName: "checkmark.circle.fill")
            case .rest:
                Image(systemName: "moon.fill")
            case .unavailable:
                Image(systemName: "circle")
            }
        }
    }
    
    private func stateColor(for state: DayState) -> Color {
        switch state {
        case .available: return .green
        case .rest: return .orange
        case .unavailable: return .gray
        }
    }
    
    private func stateBackgroundColor(for state: DayState) -> Color {
        switch state {
        case .available: return Color.green.opacity(0.1)
        case .rest: return Color.orange.opacity(0.1)
        case .unavailable: return Color(.systemGray6)
        }
    }
    
    private func stateBorderColor(for state: DayState) -> Color {
        switch state {
        case .available: return .green
        case .rest: return .orange
        case .unavailable: return .clear
        }
    }
    
    private func legendItem(icon: String, color: Color, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            Text(label)
                .foregroundColor(.secondary)
        }
    }
    
    private func toggleDayState(_ dayIndex: Int) {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        let currentState = availability.stateForDay(dayIndex)
        let nextState = availability.nextState(for: currentState)
        availability.setState(nextState, forDay: dayIndex)
        hasChanges = true
    }
    
    // MARK: - Warning Section
    
    private var warningSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            
            Text("You currently have no training days selected. At least one training day is recommended to generate a plan.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Long Run Day Section
    
    private var longRunDaySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preferred Long Run Day")
                .font(.headline)
            
            Text("Choose which day you'd prefer to do your long run (optional)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Horizontal button selector
            if availability.availableDays.isEmpty {
                Text("Select training days first")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
            } else {
                VStack(spacing: 8) {
                    // First row: No preference button (full width)
                    longRunDayButton(day: nil, label: "No preference")
                    
                    // Remaining rows: Day buttons in groups of 3
                    let sortedDays = Array(availability.availableDays).sorted()
                    ForEach(0..<((sortedDays.count + 2) / 3), id: \.self) { rowIndex in
                        HStack(spacing: 8) {
                            ForEach(0..<3, id: \.self) { colIndex in
                                let index = rowIndex * 3 + colIndex
                                if index < sortedDays.count {
                                    longRunDayButton(day: sortedDays[index], label: TrainingAvailability.dayName(for: sortedDays[index]))
                                } else {
                                    // Empty spacer for alignment
                                    Color.clear
                                        .frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func longRunDayButton(day: Int?, label: String) -> some View {
        let isSelected = (day == nil && availability.preferredLongRunDay == nil) || 
                        (day != nil && availability.preferredLongRunDay == day)
        
        return Button(action: {
            availability.preferredLongRunDay = day
            hasChanges = true
        }) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isSelected ? Color.stridePrimary.opacity(0.1) : Color(.systemBackground))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.stridePrimary : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Double Days Toggle
    
    private var doubleDaysToggleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(
                get: { availability.allowDoubleDays },
                set: { availability.allowDoubleDays = $0; hasChanges = true }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allow Double Days")
                        .font(.headline)
                    
                    Text("Permit running and gym workouts on the same day (for advanced athletes)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Actions
    
    private func saveAvailability() {
        // Validate
        if let error = availability.validate() {
            print("⚠️ Availability validation error: \(error)")
            return
        }
        
        // Load current preferences
        var preferences = storageManager.loadTrainingPreferences()
        
        // Update availability
        preferences.availability = availability
        
        // Save
        do {
            try storageManager.saveTrainingPreferences(preferences)
            hasChanges = false
            showSaveConfirmation = true
            print("✅ Saved training availability")
        } catch {
            print("⚠️ Error saving availability: \(error)")
        }
    }
}

#Preview {
    NavigationStack {
        AvailabilitySettingsView(storageManager: StorageManager())
    }
}
