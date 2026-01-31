import SwiftUI

/// Multi-method baseline fitness assessment input view
struct BaselineAssessmentView: View {
    @ObservedObject var baselineManager: BaselineAssessmentManager
    @ObservedObject var workoutManager: WorkoutManager
    @Environment(\.dismiss) private var dismiss
    
    var goalDistance: Double? // Optional goal distance for race pace calculation
    
    @State private var selectedTab: AssessmentTab = .recentRace
    @State private var showResults = false
    @State private var calculatedAssessment: BaselineAssessment?
    @State private var isCalculating = false
    @State private var errorMessage: String?
    
    
    
    enum AssessmentTab: String, CaseIterable {
        case recentRace = "Recent Race"
        case timeTrial = "Time Trial"
        case guidedTest = "Guided Test"
        case garmin = "Garmin"
        
        var icon: String {
            switch self {
            case .recentRace: return "flag.fill"
            case .timeTrial: return "stopwatch.fill"
            case .guidedTest: return "figure.run"
            case .garmin: return "applewatch"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showResults, let assessment = calculatedAssessment {
                    // Results view
                    resultsView(assessment: assessment)
                } else {
                    // Input view
                    inputView
                }
            }
            .navigationTitle("Baseline Assessment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !showResults {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Input View
    
    private var inputView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Explanation
                VStack(alignment: .leading, spacing: 12) {
                    Text("To create a realistic training plan, Stride needs to know your current fitness level.")
                        .font(.system(size: 16))
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("This unlocks:")
                            .font(.system(size: 15, weight: .semibold))
                        
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                            Text("Personalized training paces")
                        }
                        .font(.system(size: 15))
                        
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                            Text("Accurate race predictions")
                        }
                        .font(.system(size: 15))
                        
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                            Text("Weekly plan adjustments")
                        }
                        .font(.system(size: 15))
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Tab picker
                Picker("Method", selection: $selectedTab) {
                    ForEach(AssessmentTab.allCases, id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                
                // Tab content
                Group {
                    switch selectedTab {
                    case .recentRace:
                        RaceResultTab(
                            baselineManager: baselineManager,
                            goalDistance: goalDistance,
                            isCalculating: $isCalculating,
                            calculatedAssessment: $calculatedAssessment,
                            showResults: $showResults,
                            errorMessage: $errorMessage
                        )
                    case .timeTrial:
                        TimeTrialTab(
                            baselineManager: baselineManager,
                            goalDistance: goalDistance,
                            isCalculating: $isCalculating,
                            calculatedAssessment: $calculatedAssessment,
                            showResults: $showResults,
                            errorMessage: $errorMessage
                        )
                    case .guidedTest:
                        GuidedTestTab(
                            workoutManager: workoutManager,
                            baselineManager: baselineManager,
                            goalDistance: goalDistance,
                            dismiss: dismiss
                        )
                    case .garmin:
                        GarminTab()
                    }
                }
                
                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            .padding()
        }
    }
    
    // MARK: - Results View
    
    private func resultsView(assessment: BaselineAssessment) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Success header
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.stridePrimary)
                    
                    Text("Great work!")
                        .font(.system(size: 28, weight: .bold))
                    
                    if let performance = assessment.testPerformanceDescription {
                        Text(performance)
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 40)
                
                // Training paces card
                TrainingPacesCard(
                    paces: assessment.trainingPaces,
                    vdot: assessment.vdot,
                    assessmentContext: "from your \(assessment.method.displayName.lowercased())"
                )
                
                // Continue button
                Button(action: {
                    dismiss()
                }) {
                    Text("Save and Continue")
                        .font(.system(size: 18, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(Color.stridePrimary)
                        .foregroundColor(.strideBlack)
                        .cornerRadius(100)
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
    }
}

// MARK: - Race Result Tab

struct RaceResultTab: View {
    @ObservedObject var baselineManager: BaselineAssessmentManager
    let goalDistance: Double?
    
    @Binding var isCalculating: Bool
    @Binding var calculatedAssessment: BaselineAssessment?
    @Binding var showResults: Bool
    @Binding var errorMessage: String?
    
    @State private var selectedDistance: RaceDistanceOption = .fiveK
    @State private var customDistance: String = ""
    @State private var hours: Int = 0
    @State private var minutes: Int = 20
    @State private var seconds: Int = 0
    @State private var selectedDate = Date()
    
    
    
    enum RaceDistanceOption: String, CaseIterable {
        case threeK = "3K"
        case fiveK = "5K"
        case tenK = "10K"
        case halfMarathon = "Half Marathon"
        case marathon = "Marathon"
        case custom = "Custom"
        
        var kilometers: Double? {
            switch self {
            case .threeK: return 3.0
            case .fiveK: return 5.0
            case .tenK: return 10.0
            case .halfMarathon: return 21.0975
            case .marathon: return 42.195
            case .custom: return nil
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Enter your most recent race result to calculate your fitness level.")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
            
            // Distance picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Distance")
                    .font(.system(size: 16, weight: .medium))
                
                Picker("Distance", selection: $selectedDistance) {
                    ForEach(RaceDistanceOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
                
                if selectedDistance == .custom {
                    TextField("Enter distance in km", text: $customDistance)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                }
            }
            
            // Time input
            VStack(alignment: .leading, spacing: 8) {
                Text("Time")
                    .font(.system(size: 16, weight: .medium))
                
                HStack(spacing: 12) {
                    // Hours
                    VStack {
                        Picker("Hours", selection: $hours) {
                            ForEach(0..<10) { hour in
                                Text("\(hour)").tag(hour)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 80)
                        Text("hours")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    // Minutes
                    VStack {
                        Picker("Minutes", selection: $minutes) {
                            ForEach(0..<60) { minute in
                                Text("\(minute)").tag(minute)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 80)
                        Text("min")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    // Seconds
                    VStack {
                        Picker("Seconds", selection: $seconds) {
                            ForEach(0..<60) { second in
                                Text("\(second)").tag(second)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 80)
                        Text("sec")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(height: 120)
            }
            
            // Date picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Race Date")
                    .font(.system(size: 16, weight: .medium))
                
                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .frame(maxWidth: .infinity)
            }
            
            // Calculate button
            Button(action: {
                calculateBaseline()
            }) {
                if isCalculating {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.strideBlack)
                } else {
                    Text("Calculate Fitness")
                        .font(.system(size: 18, weight: .bold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(isValid ? .stridePrimary : Color.gray)
            .foregroundColor(.strideBlack)
            .cornerRadius(100)
            .disabled(!isValid || isCalculating)
        }
    }
    
    private var isValid: Bool {
        let hasDistance = selectedDistance != .custom || !customDistance.isEmpty
        let hasTime = hours > 0 || minutes > 0 || seconds > 0
        return hasDistance && hasTime
    }
    
    private func calculateBaseline() {
        errorMessage = nil
        isCalculating = true
        
        Task {
            do {
                // Get distance
                let distance: Double
                if selectedDistance == .custom {
                    guard let customDist = Double(customDistance), customDist > 0 else {
                        errorMessage = "Please enter a valid distance"
                        isCalculating = false
                        return
                    }
                    distance = customDist
                } else {
                    distance = selectedDistance.kilometers!
                }
                
                // Calculate time in seconds
                let timeSeconds = TimeInterval(hours * 3600 + minutes * 60 + seconds)
                
                // Create assessment
                let assessment = try await baselineManager.createFromRaceResult(
                    distance: distance,
                    time: timeSeconds,
                    goalDistance: goalDistance
                )
                
                calculatedAssessment = assessment
                showResults = true
                isCalculating = false
            } catch {
                errorMessage = error.localizedDescription
                isCalculating = false
            }
        }
    }
}

// MARK: - Time Trial Tab

struct TimeTrialTab: View {
    @ObservedObject var baselineManager: BaselineAssessmentManager
    let goalDistance: Double?
    
    @Binding var isCalculating: Bool
    @Binding var calculatedAssessment: BaselineAssessment?
    @Binding var showResults: Bool
    @Binding var errorMessage: String?
    
    @State private var selectedDistance: RaceResultTab.RaceDistanceOption = .fiveK
    @State private var customDistance: String = ""
    @State private var hours: Int = 0
    @State private var minutes: Int = 20
    @State private var seconds: Int = 0
    
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Enter a recent hard training effort (like a tempo run or fast finish) to calculate your fitness level.")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
            
            // Distance picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Distance")
                    .font(.system(size: 16, weight: .medium))
                
                Picker("Distance", selection: $selectedDistance) {
                    ForEach(RaceResultTab.RaceDistanceOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
                
                if selectedDistance == .custom {
                    TextField("Enter distance in km", text: $customDistance)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                }
            }
            
            // Time input
            VStack(alignment: .leading, spacing: 8) {
                Text("Time")
                    .font(.system(size: 16, weight: .medium))
                
                HStack(spacing: 12) {
                    // Hours
                    VStack {
                        Picker("Hours", selection: $hours) {
                            ForEach(0..<10) { hour in
                                Text("\(hour)").tag(hour)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 80)
                        Text("hours")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    // Minutes
                    VStack {
                        Picker("Minutes", selection: $minutes) {
                            ForEach(0..<60) { minute in
                                Text("\(minute)").tag(minute)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 80)
                        Text("min")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    // Seconds
                    VStack {
                        Picker("Seconds", selection: $seconds) {
                            ForEach(0..<60) { second in
                                Text("\(second)").tag(second)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 80)
                        Text("sec")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(height: 120)
            }
            
            // Calculate button
            Button(action: {
                calculateBaseline()
            }) {
                if isCalculating {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.strideBlack)
                } else {
                    Text("Calculate Fitness")
                        .font(.system(size: 18, weight: .bold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(isValid ? .stridePrimary : Color.gray)
            .foregroundColor(.strideBlack)
            .cornerRadius(100)
            .disabled(!isValid || isCalculating)
        }
    }
    
    private var isValid: Bool {
        let hasDistance = selectedDistance != .custom || !customDistance.isEmpty
        let hasTime = hours > 0 || minutes > 0 || seconds > 0
        return hasDistance && hasTime
    }
    
    private func calculateBaseline() {
        errorMessage = nil
        isCalculating = true
        
        Task {
            do {
                // Get distance
                let distance: Double
                if selectedDistance == .custom {
                    guard let customDist = Double(customDistance), customDist > 0 else {
                        errorMessage = "Please enter a valid distance"
                        isCalculating = false
                        return
                    }
                    distance = customDist
                } else {
                    distance = selectedDistance.kilometers!
                }
                
                // Calculate time in seconds
                let timeSeconds = TimeInterval(hours * 3600 + minutes * 60 + seconds)
                
                // Create assessment
                let assessment = try await baselineManager.createFromTimeTrial(
                    distance: distance,
                    time: timeSeconds,
                    goalDistance: goalDistance
                )
                
                calculatedAssessment = assessment
                showResults = true
                isCalculating = false
            } catch {
                errorMessage = error.localizedDescription
                isCalculating = false
            }
        }
    }
}

// MARK: - Guided Test Tab

struct GuidedTestTab: View {
    @ObservedObject var workoutManager: WorkoutManager
    @ObservedObject var baselineManager: BaselineAssessmentManager
    let goalDistance: Double?
    let dismiss: DismissAction
    
    @State private var selectedDistance: TestDistance = .fiveK
    
    
    
    enum TestDistance: String, CaseIterable {
        case threeK = "3K"
        case fiveK = "5K"
        case tenK = "10K"
        
        var kilometers: Double {
            switch self {
            case .threeK: return 3.0
            case .fiveK: return 5.0
            case .tenK: return 10.0
            }
        }
        
        var estimatedTime: String {
            switch self {
            case .threeK: return "15-20 minutes"
            case .fiveK: return "20-30 minutes"
            case .tenK: return "40-60 minutes"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Run a timed test on your treadmill at your best sustainable effort.")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
            
            // Test distance picker
            VStack(alignment: .leading, spacing: 12) {
                Text("Test Distance")
                    .font(.system(size: 16, weight: .medium))
                
                ForEach(TestDistance.allCases, id: \.self) { distance in
                    Button(action: {
                        selectedDistance = distance
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(distance.rawValue)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.primary)
                                
                                Text("Estimated time: \(distance.estimatedTime)")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if selectedDistance == distance {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.stridePrimary)
                                    .font(.system(size: 24))
                            }
                        }
                        .padding()
                        .background(selectedDistance == distance ? Color.stridePrimary.opacity(0.1) : Color(.systemGray6))
                        .cornerRadius(12)
                    }
                }
            }
            
            // Instructions
            VStack(alignment: .leading, spacing: 12) {
                Text("Instructions")
                    .font(.system(size: 16, weight: .medium))
                
                VStack(alignment: .leading, spacing: 8) {
                    InstructionRow(number: 1, text: "Warm up for 10-15 minutes at easy pace")
                    InstructionRow(number: 2, text: "Start the test and run at your best sustainable effort")
                    InstructionRow(number: 3, text: "The test will auto-finish at \(selectedDistance.rawValue)")
                    InstructionRow(number: 4, text: "Your fitness level will be calculated immediately")
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            
            Spacer()
            
            // Start test button
            Button(action: {
                startBaselineTest()
            }) {
                Text("Start Baseline Test")
                    .font(.system(size: 18, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(Color.stridePrimary)
                    .foregroundColor(.strideBlack)
                    .cornerRadius(100)
            }
        }
    }
    
    private func startBaselineTest() {
        // Set baseline test mode in workout manager
        workoutManager.startBaselineTest(targetDistanceKm: selectedDistance.kilometers)
        dismiss()
    }
}

struct InstructionRow: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.green)
                .clipShape(Circle())
            
            Text(text)
                .font(.system(size: 15))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Garmin Tab

struct GarminTab: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "applewatch")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("Coming Soon")
                .font(.system(size: 24, weight: .bold))
            
            Text("Garmin Connect integration is in development. You'll be able to sync your workout history and automatically calculate your fitness level.")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview {
    let storageManager = StorageManager()
    let hrZonesManager = HeartRateZonesManager()
    let baselineManager = BaselineAssessmentManager(
        storageManager: storageManager,
        hrZonesManager: hrZonesManager
    )
    let workoutManager = WorkoutManager(storageManager: storageManager)
    
    return BaselineAssessmentView(
        baselineManager: baselineManager,
        workoutManager: workoutManager,
        goalDistance: 21.0975
    )
}
