import SwiftUI
import SwiftData

struct RunSummaryView: View {
    @Environment(\.modelContext) private var modelContext
    let result: RunResult
    let score: Int?
    let shoes: [Shoe]
    var onSave: (_ feedbackRating: Int?, _ notes: String, _ shoeId: UUID?, _ shoeName: String?, _ coachNotes: String?) -> Void

    @State private var feedbackRating: Int? = nil
    @State private var feedbackNotes: String = ""
    @State private var selectedShoe: Shoe?
    @FocusState private var notesFocused: Bool

    /// Outdoor runs offer outdoor shoes; treadmill runs offer indoor shoes.
    private var eligibleShoes: [Shoe] {
        let wanted: ShoeUsage = result.isOutdoorRun ? .outdoor : .indoor
        let matching = shoes.filter { $0.usage == wanted }
        return matching.isEmpty ? shoes : matching   // fall back if none tagged
    }
    @State private var showShareSheet = false
    @State private var shareImage: UIImage?
    @StateObject private var coachVM = PostRunCoachViewModel()
    
    @AppStorage(RunLobbyAppearance.storageKey) private var appearanceRaw = RunLobbyAppearance.black.rawValue
    private var appearance: RunLobbyAppearance { RunLobbyAppearance(rawValue: appearanceRaw) ?? .black }
    private var style: StridePageStyle { .init(appearance: appearance) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                summaryHeader
                summaryHero
                if let score { summaryScore(score) }
                if let notice = result.recoveryNotice {
                    Text(notice).font(.inter(size: 12)).foregroundStyle(style.muted)
                        .padding(15).frame(maxWidth: .infinity, alignment: .leading)
                        .stridePageCard(style, radius: 18)
                }
                primaryStats
                feedbackSection
                if !shoes.isEmpty { shoePickerSection }
                notesSection
                aiCoachSection

                if let routeJSON = result.routeJSON {
                    RouteMapView(
                        routeJSON: routeJSON,
                        paceData: result.kmSplits.map {
                            CodableKilometerSplit(kilometer: $0.kilometer, pace: $0.pace,
                                                  time: $0.time, isFastest: $0.isFastest)
                        },
                        showPaceColors: false
                    )
                    if result.elevationGainMeters != nil || result.elevationLossMeters != nil {
                        ElevationProfileView(routeJSON: routeJSON,
                            elevationGain: result.elevationGainMeters,
                            elevationLoss: result.elevationLossMeters)
                    }
                }
                if result.speedSamples.count >= 2 {
                    RunSpeedGraphView(samples: result.speedSamples, duration: result.durationSeconds)
                }
                if let hrJSON = result.hrSamplesJSON {
                    HeartRateGraphView(hrSamplesJSON: hrJSON,
                        avgHeartRate: result.avgHeartRate,
                        maxHeartRate: result.maxHeartRate,
                        duration: result.durationSeconds)
                }
                if result.isPlannedRun { plannedVsActualCard }
                if !result.kmSplits.isEmpty { splitsSection }
                if let shoe = selectedShoe,
                   shoe.effectiveMaxKm > 0,
                   shoe.totalDistanceKm + result.distanceKm >= shoe.effectiveMaxKm {
                    shoeRetirementBanner(shoe)
                }
                if result.isOutdoorRun { shareButton }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background { StridePageBackdrop().ignoresSafeArea() }
        .foregroundStyle(style.ink)
        .preferredColorScheme(appearance.colorScheme)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                onSave(feedbackRating, feedbackNotes, selectedShoe?.id, selectedShoe?.name,
                       coachVM.isGenerating ? nil : coachVM.coachText)
            } label: {
                Text("SAVE RUN")
                    .font(.barlowCondensed(size: 26))
                    .tracking(0.7)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(Color.stridePrimary, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .background(appearance.background.opacity(0.96))
        }
        .onAppear {
            guard !coachVM.isGenerating && coachVM.coachText.isEmpty && coachVM.error == nil else { return }
            // A free run has no prescribed shoe. Ask the athlete to choose when
            // several pairs exist instead of silently logging the default pair.
            selectedShoe = !result.isPlannedRun && eligibleShoes.count > 1
                ? nil : (eligibleShoes.first(where: \.isDefault) ?? eligibleShoes.first)
            coachVM.generateCoaching(result: result) { review in
                let sessionID = result.sessionID
                guard let log = try? modelContext.fetch(FetchDescriptor<RunLog>(
                    predicate: #Predicate { $0.id == sessionID })).first else { return }
                log.coachNotes = review
                try? modelContext.save()
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = shareImage { ShareSheet(activityItems: [image]) }
        }
    }

    private var summaryHeader: some View {
        HStack {
            Image(appearance == .white ? "StrideLogo" : (appearance == .red ? "StrideLogoRed" : "StrideLogoDark"))
                .resizable()
                .aspectRatio(690.0 / 156.0, contentMode: .fit)
                .frame(width: 120)
                .accessibilityLabel("Stride")
            Spacer()
            Text(result.completedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased())
                .font(.runEyebrow(10))
                .foregroundStyle(style.muted)
        }
    }

    private var summaryHero: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("RUN").foregroundStyle(style.ink)
            Text("COMPLETE.").foregroundStyle(appearance == .red ? .white : Color.stridePrimary)
            Text("\((result.plannedWorkoutTitle ?? "FREE RUN").uppercased()) · \(result.isOutdoorRun ? "OUTDOOR" : "INDOOR")")
                .font(.runEyebrow(10))
                .foregroundStyle(style.muted)
                .padding(.top, 8)
        }
        .font(.barlowCondensed(size: 57))
        .lineSpacing(-8)
        .padding(.top, 18)
    }

    private func summaryScore(_ value: Int) -> some View {
        HStack(alignment: .bottom, spacing: 18) {
            Text("\(value)")
                .font(.barlowCondensed(size: 77))
                .monospacedDigit()
                .foregroundStyle(style.ink)
            VStack(alignment: .leading, spacing: 4) {
                Text("SESSION SCORE")
                    .font(.runEyebrow(10))
                    .foregroundStyle(style.muted)
                Text(value >= 90 ? "CONSISTENT EFFORT" : value >= 75 ? "SOLID SESSION" : "SESSION LOGGED")
                    .font(.runEyebrow(9))
                    .foregroundStyle(appearance == .red ? .white : Color.stridePrimary)
            }
            .padding(.bottom, 10)
            Spacer()
        }
        .padding(.top, 12)
        .padding(.bottom, 5)
        .overlay(alignment: .bottom) { Rectangle().fill(style.rule).frame(height: 0.5) }
    }

    private var shareButton: some View {
        Button {
            Task {
                shareImage = await RouteShareService.generateShareImage(result: result)
                if shareImage != nil { showShareSheet = true }
            }
        } label: {
            HStack {
                Text("SHARE ROUTE").font(.barlowCondensed(size: 22))
                Spacer()
                Image(systemName: "square.and.arrow.up").font(.system(size: 15))
            }
            .foregroundStyle(style.ink)
            .padding(18)
            .stridePageCard(style, radius: 20)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Primary Stats

    private var primaryStats: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(result.distanceDisplay)
                    .font(.barlowCondensed(size: 80))
                    .monospacedDigit()
                Text("KM").font(.barlowCondensed(size: 25)).foregroundStyle(style.muted)
                Spacer(minLength: 0)
                if let target = result.targetDistanceKm {
                    Text("GOAL \(formatDistance(target).uppercased())")
                        .font(.runEyebrow(10)).foregroundStyle(style.muted)
                }
            }
            Rectangle().fill(style.rule).frame(height: 0.5)
            HStack(spacing: 0) {
                summaryMetric(result.durationDisplay, label: "TIME")
                summaryMetric(result.avgPaceDisplay, label: "AVG /KM")
                summaryMetric(result.avgHeartRate.map(String.init) ?? "—", label: "AVG BPM")
            }
        }
        .padding(18)
        .stridePageCard(style)
    }

    private func summaryMetric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.barlowCondensed(size: 30))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
            Text(label).font(.runEyebrow(9)).foregroundStyle(style.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Planned vs Actual
    
    private var plannedVsActualCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.stridePrimary)
                Text("PLAN COMPARISON")
                    .font(.barlowCondensed(size: 24))
                    .foregroundColor(.primary)
            }
            
            // Workout title
            if let title = result.plannedWorkoutTitle {
                Text(title)
                    .font(.inter(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            // Comparison rows
            VStack(spacing: 12) {
                if let targetDist = result.targetDistanceKm {
                    comparisonRow(
                        label: "Distance",
                        planned: formatDistance(targetDist),
                        actual: formatDistance(result.distanceKm),
                        isGood: result.distanceKm >= targetDist
                    )
                }
                
                if let targetPace = result.targetPaceDescription {
                    comparisonRow(
                        label: "Avg Pace",
                        planned: targetPace,
                        actual: result.avgPaceDisplay + " /km",
                        isGood: isPaceGood()
                    )
                }
                
                if let targetMins = result.targetDurationMinutes {
                    comparisonRow(
                        label: "Duration",
                        planned: formatDurationMinutes(targetMins),
                        actual: result.durationDisplay,
                        isGood: true
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .stridePageCard(style, radius: 20)
    }
    
    private func comparisonRow(label: String, planned: String, actual: String, isGood: Bool) -> some View {
        HStack {
            Text(label)
                .font(.inter(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
            
            Spacer()
            
            // Planned
            VStack(spacing: 2) {
                Text(planned)
                    .font(.barlowCondensed(size: 18, weight: .medium))
                    .foregroundColor(.secondary)
                Text("Planned")
                    .font(.inter(size: 10, weight: .regular))
                    .foregroundColor(Color(.tertiaryLabel))
            }
            .frame(width: 80)
            
            // Arrow
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            
            // Actual
            VStack(spacing: 2) {
                Text(actual)
                    .font(.barlowCondensed(size: 18, weight: .medium))
                    .foregroundColor(isGood ? .green : .orange)
                Text("Actual")
                    .font(.inter(size: 10, weight: .regular))
                    .foregroundColor(Color(.tertiaryLabel))
            }
            .frame(width: 80)
        }
    }
    
    // MARK: - Splits Section
    
    private var splitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("KILOMETRE SPLITS")
                .font(.barlowCondensed(size: 24))
                .foregroundColor(.primary)
            
            // Header row
            HStack(spacing: 0) {
                Text("KM")
                    .font(.inter(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 30, alignment: .leading)
                
                Spacer()
                
                Text("Pace")
                    .font(.inter(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("Time")
                    .font(.inter(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 70, alignment: .trailing)
            }
            
            ForEach(result.kmSplits) { split in
                HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Text("\(split.kilometer)")
                            .font(.barlowCondensed(size: 18, weight: .medium))
                            .foregroundColor(.primary)
                        
                        if split.isFastest {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.stridePrimary)
                        }
                    }
                    .frame(width: 50, alignment: .leading)
                    
                    Spacer()
                    
                    Text("\(split.pace) /km")
                        .font(.barlowCondensed(size: 18, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text(formatSplitTime(split.time))
                        .font(.barlowCondensed(size: 18, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 70, alignment: .trailing)
                }
                .padding(.vertical, 6)
                
                if split.kilometer < result.kmSplits.count {
                    Rectangle()
                        .fill(Color.stridePrimary.opacity(0.2))
                        .frame(height: 1)
                }
            }
        }
        .padding(16)
        .stridePageCard(style, radius: 20)
    }
    
    // MARK: - AI Coach Section

    private var aiCoachSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.stridePrimary)
                Text("COACH NOTES")
                    .font(.barlowCondensed(size: 24))
                    .foregroundColor(.primary)

                Spacer()

                if coachVM.isPlaying {
                    Button {
                        coachVM.stopPlayback()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.stridePrimary)
                    }
                }
            }

            if coachVM.isGenerating {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.stridePrimary)
                    Text(coachVM.coachText.isEmpty ? "Your coach is reviewing your run..." : "")
                        .font(.inter(size: 13, weight: .regular))
                        .foregroundColor(.secondary)
                }
            }

            if !coachVM.coachText.isEmpty {
                Text(coachVM.coachText)
                    .font(.inter(size: 14, weight: .regular))
                    .foregroundColor(.primary)
                    .lineSpacing(4)

                if coachVM.isPlaying {
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.stridePrimary)
                                .frame(width: 3, height: CGFloat.random(in: 8...16))
                        }
                        Text("Playing...")
                            .font(.inter(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
            }

            if let error = coachVM.error {
                Text(error)
                    .font(.inter(size: 12, weight: .regular))
                    .foregroundColor(.red)
                Button("TRY COACH AGAIN") {
                    coachVM.generateCoaching(result: result) { review in
                        let sessionID = result.sessionID
                        guard let log = try? modelContext.fetch(FetchDescriptor<RunLog>(
                            predicate: #Predicate { $0.id == sessionID })).first else { return }
                        log.coachNotes = review
                        try? modelContext.save()
                    }
                }
                .font(.runEyebrow(10))
                .foregroundStyle(Color.stridePrimary)
            }
        }
        .padding(16)
        .stridePageCard(style, radius: 20)
    }

    // MARK: - Feedback Section
    
    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("HOW DID IT FEEL?")
                .font(.barlowCondensed(size: 24))
                .foregroundColor(.primary)
            
            HStack(spacing: 0) {
                ForEach(0...5, id: \.self) { rating in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            feedbackRating = rating
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Text("\(rating)")
                                .font(.barlowCondensed(size: 24, weight: .medium))
                                .foregroundColor(feedbackRating == rating ? .white : .primary)
                            
                            Text(feedbackLabel(for: rating))
                                .font(.inter(size: 9, weight: .medium))
                                .foregroundColor(feedbackRating == rating ? .white.opacity(0.8) : .secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(feedbackRating == rating ? feedbackColor(for: rating) : Color.clear)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(4)
            .background(style.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
    
    private func feedbackLabel(for rating: Int) -> String {
        switch rating {
        case 0: return "Terrible"
        case 1: return "Rough"
        case 2: return "Tough"
        case 3: return "Okay"
        case 4: return "Good"
        case 5: return "Amazing"
        default: return ""
        }
    }
    
    private func feedbackColor(for rating: Int) -> Color {
        switch rating {
        case 0: return .red
        case 1: return .orange
        case 2: return Color(red: 0.9, green: 0.6, blue: 0.1)
        case 3: return .yellow.opacity(0.8)
        case 4: return Color(red: 0.3, green: 0.7, blue: 0.3)
        case 5: return .green
        default: return .gray
        }
    }
    
    // MARK: - Shoe Retirement Banner

    private func shoeRetirementBanner(_ shoe: Shoe) -> some View {
        HStack(spacing: 12) {
            Text("🎉")
                .font(.system(size: 30))
            VStack(alignment: .leading, spacing: 3) {
                Text("\(shoe.name) hit its max")
                    .font(.inter(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Text("\(Int(shoe.totalDistanceKm + result.distanceKm)) of \(Int(shoe.effectiveMaxKm)) km. Go ahead and buy a new pair — you earned it!")
                    .font(.inter(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.92))
            }
            Spacer()
        }
        .padding(16)
        .background(
            LinearGradient(colors: [Color.stridePrimary, Color.strideDarkRed],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YOUR NOTES")
                .font(.barlowCondensed(size: 24))
                .foregroundColor(.primary)

            // Pause summary (non-editable)
            if let pauseInfo = result.pauseSummary {
                Text(pauseInfo)
                    .font(.inter(size: 13, weight: .regular))
                    .foregroundColor(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(style.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            TextField("Any notes about this run...", text: $feedbackNotes, axis: .vertical)
                .font(.inter(size: 14, weight: .regular))
                .lineLimit(3...6)
                .focused($notesFocused)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { notesFocused = false }
                    }
                }
                .padding(14)
                .background(style.card)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
    
    // MARK: - Shoe Picker Section

    private var shoePickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SHOES")
                .font(.barlowCondensed(size: 24))
                .foregroundColor(.primary)
            if !result.isPlannedRun && eligibleShoes.count > 1 {
                Text("Choose the pair you wore for this run.")
                    .font(.inter(size: 12))
                    .foregroundStyle(style.muted)
            }

            VStack(spacing: 8) {
                Button {
                    selectedShoe = nil
                } label: {
                    HStack {
                        Text("None")
                        Spacer()
                        if selectedShoe == nil { Image(systemName: "checkmark.circle.fill") }
                    }
                    .padding(14)
                }

                ForEach(eligibleShoes, id: \.id) { shoe in
                    Button {
                        selectedShoe = shoe
                    } label: {
                        HStack(spacing: 12) {
                            ShoePhotoView(shoe: shoe, size: 56)
                            Text(shoe.name)
                                .font(.inter(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedShoe?.id == shoe.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.stridePrimary)
                            }
                        }
                        .padding(12)
                        .background(style.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .accessibilityAddTraits(selectedShoe?.id == shoe.id ? .isSelected : [])
                }
            }
            .buttonStyle(.plain)

        }
    }

    // MARK: - Helpers
    
    private func formatDistance(_ km: Double) -> String {
        if km == floor(km) {
            return "\(Int(km)) km"
        }
        return String(format: "%.1f km", km)
    }
    
    private func formatDurationMinutes(_ minutes: Int) -> String {
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            if m == 0 { return "\(h)h" }
            return "\(h)h \(m)m"
        }
        return "\(minutes) min"
    }
    
    private func formatSplitTime(_ timeString: String) -> String {
        let components = timeString.split(separator: ":").compactMap { Int($0) }
        if components.count == 3 {
            let hours = components[0]
            let minutes = components[1]
            let seconds = components[2]
            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, minutes, seconds)
            }
            return String(format: "%d:%02d", minutes, seconds)
        } else if components.count == 2 {
            return String(format: "%d:%02d", components[0], components[1])
        }
        return timeString
    }
    
    private func isPaceGood() -> Bool {
        guard let targetPace = RunScoringService.parsePaceToSeconds(result.targetPaceDescription) else {
            return true
        }
        // Within ±5 sec/km of target is good
        return abs(result.avgPaceSecPerKm - targetPace) <= 5.0
    }
}

#Preview {
    RunSummaryView(
        result: RunResult(
            distanceKm: 9.8,
            durationSeconds: 3120,
            avgPaceSecPerKm: 318.4,
            kmSplits: [
                KilometerSplit(kilometer: 1, pace: "5:22", time: "00:05:22", isFastest: false, diffFromFastest: 4),
                KilometerSplit(kilometer: 2, pace: "5:18", time: "00:10:40", isFastest: true, diffFromFastest: 0),
                KilometerSplit(kilometer: 3, pace: "5:25", time: "00:16:05", isFastest: false, diffFromFastest: 7)
            ],
            plannedWorkoutId: UUID(),
            plannedWorkoutTitle: "Easy 10K",
            plannedWorkoutType: .easyRun,
            targetDistanceKm: 10.0,
            targetPaceDescription: "5:30/km",
            targetDurationMinutes: 55,
            dataSource: "bluetooth_ftms",
            treadmillBrand: "Assault Runner",
            routeJSON: nil,
            elevationGainMeters: nil,
            elevationLossMeters: nil,
            avgHeartRate: 152,
            maxHeartRate: 171,
            hrSamplesJSON: nil,
            totalPauseDurationSeconds: 0,
            completedPauseDurations: []
        ),
        score: 85,
        shoes: [],
        onSave: { _, _, _, _, _ in }
    )
}
