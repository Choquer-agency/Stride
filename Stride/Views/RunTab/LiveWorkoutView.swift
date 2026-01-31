import SwiftUI

/// Live workout display with real-time metrics
struct LiveWorkoutView: View {
    @ObservedObject var workoutManager: WorkoutManager
    @StateObject private var hrZonesManager = HeartRateZonesManager()
    @StateObject private var storageManager = StorageManager()
    @State private var showCompletionSheet = false
    @State private var showReviewScreen = false
    @State private var reviewFeedback: WorkoutFeedback?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 1. Top Section - Time and Distance (compact, same size)
                HStack(spacing: 40) {
                    // Time
                    VStack(spacing: 4) {
                        Text(workoutManager.liveStats.durationSeconds.toFullTimeString())
                            .font(.system(size: 40, weight: .medium))
                            .minimumScaleFactor(0.5)
                        Text("Time")
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(.secondary)
                    }
                    
                    // Distance
                    VStack(spacing: 4) {
                        Text(String(format: "%.2f", workoutManager.liveStats.totalDistanceMeters / 1000.0))
                            .font(.system(size: 40, weight: .medium))
                            .minimumScaleFactor(0.5)
                        Text("Distance (km)")
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 24)
                .padding(.bottom, 24)
                
                // 2. Hero Section - Current Pace (LARGE)
                VStack(spacing: 4) {
                    Text(workoutManager.liveStats.currentPaceSecPerKm.toPaceString())
                        .font(.system(size: 96, weight: .medium))
                        .minimumScaleFactor(0.5)
                    Text("Pace (/km)")
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 24)
                
                // 3. Pace Graph
                VStack(spacing: 12) {
                    if let samples = workoutManager.currentSession?.recentSamples, !samples.isEmpty {
                        PaceLineGraphView(samples: samples, primaryColor: .stridePrimary)
                            .frame(height: 70)
                            .padding(.horizontal, 24)
                    } else {
                        RoundedRectangle(cornerRadius: 0)
                            .fill(Color.clear)
                            .frame(height: 70)
                            .overlay(
                                Text("Pace graph")
                                    .font(.system(size: 14, weight: .light))
                                    .foregroundColor(.secondary)
                            )
                            .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, 24)
                
                // 4. Middle Section - Pace Drift and HR Zone (no backgrounds)
                HStack(spacing: 40) {
                    PaceDriftCard(paceDriftPercent: workoutManager.liveStats.paceDriftPercent)
                    
                    HeartRateZoneCard(
                        heartRate: workoutManager.liveStats.heartRate,
                        zonesManager: hrZonesManager
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                
                // 5. Kilometer Splits Table - 4 columns
                VStack(alignment: .leading, spacing: 16) {
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
                    .padding(.horizontal, 24)
                    
                    // Divider line
                    Rectangle()
                        .fill(Color.stridePrimary)
                        .frame(height: 1)
                        .padding(.horizontal, 24)
                    
                    // Splits list
                    LazyVStack(spacing: 0) {
                        if let splits = workoutManager.currentSession?.splits, !splits.isEmpty {
                            ForEach(Array(splits.enumerated()), id: \.element.id) { index, split in
                                SplitRowView(
                                    split: split,
                                    splits: splits,
                                    cumulativeTime: calculateCumulativeTime(upToIndex: index, splits: splits),
                                    primaryColor: .stridePrimary
                                )
                            }
                        } else {
                            Text("No splits yet - complete your first kilometer!")
                                .font(.system(size: 14, weight: .light))
                                .foregroundColor(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 32)
                
                // Split notification overlay
                if let split = workoutManager.recentSplitNotification {
                    HStack {
                        Image(systemName: "flag.fill")
                            .foregroundColor(.stridePrimary)
                        Text("Km \(split.kmIndex): \(split.splitTimeSeconds.toTimeString())")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .padding()
                    .background(Color.stridePrimary.opacity(0.1))
                    .cornerRadius(8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(), value: split.id)
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
                
                // Control buttons
                HStack(spacing: 20) {
                    // Pause/Resume button
                    Button(action: {
                        if workoutManager.isPaused {
                            workoutManager.resumeWorkout()
                        } else {
                            workoutManager.pauseWorkout()
                        }
                    }) {
                        Text(workoutManager.isPaused ? "Resume" : "Pause")
                            .font(.system(size: 18, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(Color.stridePrimary)
                            .foregroundColor(.strideBlack)
                            .cornerRadius(100)
                    }
                    
                    // Finish button
                    Button(action: {
                        if workoutManager.isTestMode {
                            workoutManager.stopTestWorkout()
                        } else {
                            workoutManager.stopWorkout()
                        }
                    }) {
                        Text("Finish")
                            .font(.system(size: 18, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(Color.strideBlack)
                            .foregroundColor(.stridePrimary)
                            .cornerRadius(100)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .sheet(isPresented: $showCompletionSheet) {
            WorkoutCompletionSheet(
                workoutManager: workoutManager,
                storageManager: storageManager,
                showReviewScreen: $showReviewScreen,
                reviewFeedback: $reviewFeedback
            )
        }
        .sheet(isPresented: $showReviewScreen) {
            if let feedback = reviewFeedback, let session = workoutManager.currentSession {
                WorkoutReviewScreen(feedback: feedback, session: session)
            }
        }
        .onChange(of: workoutManager.isAwaitingCompletion) { isAwaiting in
            if isAwaiting {
                showCompletionSheet = true
            }
        }
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

/// Individual split row with 4 columns: KM, Bar, Pace, Time
struct SplitRowView: View {
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

/// Real-time line graph showing pace over time during workout
struct PaceLineGraphView: View {
    let samples: [WorkoutSample]
    let primaryColor: Color
    
    private var paceData: [(time: TimeInterval, pace: Double)] {
        guard let firstSample = samples.first else { return [] }
        let startTime = firstSample.timestamp
        
        // Convert samples to pace data and apply smoothing
        var rawData: [(time: TimeInterval, pace: Double)] = []
        
        for sample in samples {
            let elapsed = sample.timestamp.timeIntervalSince(startTime)
            // Convert speed to pace (min/km)
            guard sample.speedMps > 0.1 else { continue }
            let paceMinPerKm = (1000.0 / sample.speedMps) / 60.0
            rawData.append((time: elapsed, pace: paceMinPerKm))
        }
        
        // Apply simple moving average smoothing (window of 5 samples)
        return smoothPaceData(rawData, windowSize: 5)
    }
    
    /// Apply moving average smoothing to reduce graph jitter
    private func smoothPaceData(_ data: [(time: TimeInterval, pace: Double)], windowSize: Int) -> [(time: TimeInterval, pace: Double)] {
        guard data.count > windowSize else { return data }
        
        var smoothed: [(time: TimeInterval, pace: Double)] = []
        
        for i in 0..<data.count {
            // Calculate window bounds
            let startIdx = max(0, i - windowSize / 2)
            let endIdx = min(data.count - 1, i + windowSize / 2)
            
            // Calculate average pace in window
            var paceSum = 0.0
            var count = 0
            for j in startIdx...endIdx {
                paceSum += data[j].pace
                count += 1
            }
            
            let avgPace = paceSum / Double(count)
            smoothed.append((time: data[i].time, pace: avgPace))
        }
        
        return smoothed
    }
    
    private var maxPace: Double {
        // Lower pace is better, so max is actually slower
        let paces = paceData.map { $0.pace }
        guard let dataPaceMax = paces.max() else { return 10.0 }
        // Add 10% padding to the top for visual spacing
        return dataPaceMax * 1.1
    }
    
    private var minPace: Double {
        // Higher pace is faster, so min is actually faster
        let paces = paceData.map { $0.pace }
        guard let dataPaceMin = paces.min() else { return 3.0 }
        // Subtract 10% padding from the bottom for visual spacing
        return max(dataPaceMin * 0.9, 0)
    }
    
    private var maxTime: TimeInterval {
        paceData.map { $0.time }.max() ?? 60.0
    }
    
    var body: some View {
        GeometryReader { geometry in
            if samples.isEmpty {
                VStack {
                    Spacer()
                    Text("Waiting for data...")
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ZStack(alignment: .bottom) {
                    // Pace line with gradient fill
                    ZStack {
                        // Filled area under the line
                        Path { path in
                            let data = paceData
                            guard !data.isEmpty else { return }
                            
                            let width = geometry.size.width
                            let height = geometry.size.height
                            
                            // Start from bottom left
                            path.move(to: CGPoint(x: 0, y: height))
                            
                            // Move to first data point
                            let firstPoint = pointForData(
                                time: data[0].time,
                                pace: data[0].pace,
                                width: width,
                                height: height
                            )
                            path.addLine(to: firstPoint)
                            
                            // Draw line through all points
                            for dataPoint in data.dropFirst() {
                                let point = pointForData(
                                    time: dataPoint.time,
                                    pace: dataPoint.pace,
                                    width: width,
                                    height: height
                                )
                                path.addLine(to: point)
                            }
                            
                            // Complete the fill by going to bottom right then bottom left
                            if let lastPoint = data.last {
                                let finalX = pointForData(
                                    time: lastPoint.time,
                                    pace: lastPoint.pace,
                                    width: width,
                                    height: height
                                ).x
                                path.addLine(to: CGPoint(x: finalX, y: height))
                            }
                            path.addLine(to: CGPoint(x: 0, y: height))
                            path.closeSubpath()
                        }
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    primaryColor.opacity(0.3),
                                    primaryColor.opacity(0.0)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        
                        // Pace line stroke
                        Path { path in
                            let data = paceData
                            guard !data.isEmpty else { return }
                            
                            let width = geometry.size.width
                            let height = geometry.size.height
                            
                            // Calculate first point
                            let firstPoint = pointForData(
                                time: data[0].time,
                                pace: data[0].pace,
                                width: width,
                                height: height
                            )
                            path.move(to: firstPoint)
                            
                            // Draw line through all points
                            for dataPoint in data.dropFirst() {
                                let point = pointForData(
                                    time: dataPoint.time,
                                    pace: dataPoint.pace,
                                    width: width,
                                    height: height
                                )
                                path.addLine(to: point)
                            }
                        }
                        .stroke(primaryColor, lineWidth: 2.5)
                        
                        // Add dots at data points (sampling every nth point for performance)
                        let samplingRate = max(1, paceData.count / 50)
                        ForEach(Array(paceData.enumerated().filter { $0.offset % samplingRate == 0 }), id: \.offset) { _, dataPoint in
                            Circle()
                                .fill(primaryColor)
                                .frame(width: 5, height: 5)
                                .position(
                                    pointForData(
                                        time: dataPoint.time,
                                        pace: dataPoint.pace,
                                        width: geometry.size.width,
                                        height: geometry.size.height
                                    )
                                )
                        }
                        
                        // Endpoint circle
                        if let lastDataPoint = paceData.last {
                            Circle()
                                .fill(primaryColor)
                                .frame(width: 8, height: 8)
                                .position(
                                    pointForData(
                                        time: lastDataPoint.time,
                                        pace: lastDataPoint.pace,
                                        width: geometry.size.width,
                                        height: geometry.size.height
                                    )
                                )
                        }
                    }
                    .drawingGroup() // Optimize rendering by flattening into a single layer
                }
            }
        }
    }
    
    private func pointForData(time: TimeInterval, pace: Double, width: CGFloat, height: CGFloat) -> CGPoint {
        // X position based on time (left to right)
        let xRatio = maxTime > 0 ? time / maxTime : 0
        let x = width * CGFloat(xRatio)
        
        // Y position based on pace (bottom to top, inverted because lower pace = better)
        // Note: In pace, LOWER numbers are FASTER, so we invert the mapping
        let paceRange = maxPace - minPace
        let yRatio = paceRange > 0 ? (pace - minPace) / paceRange : 0.5
        let y = height * CGFloat(yRatio) // Slower pace = higher on chart
        
        return CGPoint(x: x, y: y)
    }
}
