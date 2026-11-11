import SwiftUI
import SwiftData

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
    
    @Query private var runLogs: [RunLog]

    init(workout: Workout, onComplete: @escaping () -> Void) {
        self.workout = workout
        self.onComplete = onComplete
        let id = workout.id
        let day = Calendar.current.startOfDay(for: workout.completedAt ?? workout.date)
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86400)
        _runLogs = Query(filter: #Predicate<RunLog> {
            $0.plannedWorkoutId == id || ($0.completedAt >= day && $0.completedAt < nextDay)
        }, sort: \RunLog.completedAt, order: .reverse)
    }

    private var isCompletedRun: Bool { workout.isCompleted && workout.workoutType.isRunnable }
    private var historyRun: RunLog? {
        if let exact = runLogs.first(where: { $0.plannedWorkoutId == workout.id }) { return exact }
        guard let distance = workout.actualDistanceKm else { return nil }
        let matches = runLogs.filter {
            Calendar.current.isDate($0.completedAt, inSameDayAs: workout.completedAt ?? workout.date)
                && abs($0.distanceKm - distance) < 0.2
        }
        return matches.count == 1 ? matches.first : nil
    }

    @State private var contentHeight: CGFloat = 0
    @State private var showGymPlayer = false
    @AppStorage(RunLobbyAppearance.storageKey) private var appearanceRaw = RunLobbyAppearance.black.rawValue
    private var appearance: RunLobbyAppearance { RunLobbyAppearance(rawValue: appearanceRaw) ?? .black }
    private var sheetInk: Color { appearance.foreground }
    private var sheetMuted: Color { appearance.secondary }
    private var sheetBackground: Color { appearance.background }

    private struct SessionStep {
        let title: String
        let detail: String?
    }

    /// Many coach plans put the entire long-run prescription on one line. Pull
    /// the actual running blocks out of that line so the sheet doesn't repeat
    /// the title, total distance, and fueling instruction as a paragraph.
    private var sessionSteps: [SessionStep] {
        if workout.workoutType == .longRun {
            let source = workout.details ?? ""
            let first = captures(#"first\s+(\d+(?:\.\d+)?)\s*km\s+at\s+([\d:–-]+/km)"#, in: source)
            let finish = captures(#"(?:final|last)\s+(\d+(?:\.\d+)?)\s*km\s+at\s+([\d:–-]+/km)"#, in: source)
            if let first, let finish {
                let effort = captures(#"(RPE\s*[\d–-]+)"#, in: source)?.first
                return [
                    SessionStep(title: "LONG RUN · \(first[0]) KM", detail: first[1]),
                    SessionStep(title: "MP FINISH · \(finish[0]) KM",
                                detail: finish[1] + (effort.map { " · \($0)" } ?? ""))
                ]
            }
            return [SessionStep(title: "LONG RUN", detail: workout.paceDescription)]
        }
        if !parsedDetail.segments.isEmpty {
            return parsedDetail.segments.enumerated().map { index, segment in
                SessionStep(title: segment.label ?? "STEP \(index + 1)", detail: segment.text)
            }
        }
        // The prescription is already broken out above into distance, pace and
        // heart-rate targets. Reprinting its source paragraph adds no guidance.
        return [SessionStep(title: workout.workoutType.displayName, detail: nil)]
    }

    private func captures(_ pattern: String, in source: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: source) else { return nil }
            return String(source[range])
        }
    }

    private var coachNoteText: String? {
        if isGymWorkout { return nil } // The exercise rows carry the full prescription.
        guard workout.workoutType == .longRun else { return parsedDetail.note }
        let uniqueNotes = parsedDetail.noteSentences.filter { sentence in
            let text = sentence.lowercased()
            return !text.contains("first ") && !text.contains("final ")
                && !text.contains("fuel during") && !text.contains("total:")
        }
        return uniqueNotes.isEmpty ? nil : uniqueNotes.joined(separator: " ")
    }
    
    // Height of the drag indicator + close button area
    private let chromeHeight: CGFloat = 6
    
    private var sheetHeight: CGFloat {
        if isCompletedRun { return UIScreen.main.bounds.height * 0.85 }
        guard contentHeight > 0 else { return 400 }
        let total = contentHeight + chromeHeight
        let maxHeight = UIScreen.main.bounds.height * 0.85
        return min(total, maxHeight)
    }
    
    private var isGymWorkout: Bool {
        workout.workoutType == .gym || workout.workoutType == .crossTraining
    }

    // MARK: - Gym prescription parsing
    //
    // New-format gym lines: "Focus — Exercise 4×6 @ 60 kg; Exercise 3×8; …"
    // Old-format lines fall back to comma-separated focus areas.

    private struct GymItem: Identifiable {
        let id = UUID()
        let name: String
        let scheme: String?     // "4×6 @ 60 kg", "4 min easy", nil for focus-only
    }

    private var hasSavedGymSession: Bool {
        guard isGymWorkout, let owner = AuthService.shared.currentUserID else { return false }
        let prescription = workout.details ?? workout.title
        return GymSessionRecoveryStore.load(ownerID: owner, workoutID: workout.id,
            prescription: prescription,
            stageCount: GymSessionModel.stages(fromPrescription: prescription).count) != nil
    }

    private var gymSource: String {
        var source = workout.details ?? workout.title
        // Strip "Gym (PM):", "Gym:", "Gym —", "- Friday: Gym —" style prefixes
        if let range = source.range(of: #"^.*?Gym(\s*\((?:AM|PM)\))?\s*[:：–—\-]\s*"#, options: .regularExpression) {
            source = String(source[range.upperBound...])
        }
        return source.trimmingCharacters(in: .whitespaces)
    }

    private var gymFocus: String? {
        let source = gymSource
        guard source.contains(";") else { return nil }
        let head = source.components(separatedBy: ";")[0]
        // "Main strength — SkiErg 4 min easy" → focus is the part before the dash
        if let dashRange = head.range(of: #"\s[–—\-]\s"#, options: .regularExpression) {
            let focus = String(head[..<dashRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            if !focus.isEmpty && !focus.contains(where: \.isNumber) { return focus }
        }
        return nil
    }

    private var gymItems: [GymItem] {
        var source = gymSource
        guard source.contains(";") || source.lowercased().hasPrefix("skierg ") else {
            // Old format: comma-separated focus areas, no schemes
            return source
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { GymItem(name: $0.prefix(1).uppercased() + $0.dropFirst(), scheme: nil) }
        }
        // Drop the focus header off the first item if present
        if let focus = gymFocus, let range = source.range(of: focus) {
            source = String(source[range.upperBound...])
            if let dashRange = source.range(of: #"^\s*[–—\-]\s*"#, options: .regularExpression) {
                source = String(source[dashRange.upperBound...])
            }
        }
        return source
            .components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " .")) }
            .filter { !$0.isEmpty }
            .map { item in
                // Split name from scheme at the first digit ("Back squat 4×6 @ 50 kg")
                if let digitIdx = item.firstIndex(where: \.isNumber), digitIdx != item.startIndex {
                    let name = String(item[..<digitIdx]).trimmingCharacters(in: .whitespaces)
                    let scheme = String(item[digitIdx...]).trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty && !scheme.isEmpty {
                        return GymItem(name: name, scheme: scheme)
                    }
                }
                return GymItem(name: item, scheme: nil)
            }
    }

    // MARK: - Structured detail parsing
    //
    // The coach writes one summary line (title — total/pace/RPE, already shown
    // in the big stats) followed by structure lines (Warm-up/Main/Cool-down,
    // "A, then B, then C" chains), fueling guidance, and coaching prose.
    // Each fact renders once: structure as rows, fuel as its own strip, prose
    // as the coach's note — never re-printing the headline stats.

    private struct DetailSegment: Identifiable {
        let id = UUID()
        let label: String?      // "Warm-up" etc.; nil for numbered chain segments
        let text: String
    }

    private struct ParsedDetail {
        var segments: [DetailSegment] = []
        var fuel: String?
        var noteSentences: [String] = []
        var rpe: String?

        var note: String? {
            noteSentences.isEmpty ? nil : noteSentences.joined(separator: " ")
        }
        var isEmpty: Bool { segments.isEmpty && fuel == nil && noteSentences.isEmpty }
    }

    private var parsedDetail: ParsedDetail {
        var result = ParsedDetail()
        guard let details = workout.details, !details.isEmpty else { return result }

        let labelPattern = #"^(Warm-up|Warm up|Main set|Main|Cool-down|Cool down|Structure|Fuel during|Fueling|Fuel|Notes?|Run|Strides)\s*[:：]\s*(.+)$"#

        for rawLine in details.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.allSatisfy({ "—–-_=~─━".contains($0) }) else { continue }

            if let match = line.range(of: labelPattern, options: .regularExpression) {
                let full = String(line[match])
                let colonIdx = full.firstIndex(where: { $0 == ":" || $0 == "：" })!
                let label = String(full[..<colonIdx]).trimmingCharacters(in: .whitespaces)
                let value = String(full[full.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                ingest(label: label, value: value, into: &result)
            } else {
                ingestProse(line, into: &result)
            }
        }
        return result
    }

    private func ingest(label: String, value: String, into result: inout ParsedDetail) {
        switch label.lowercased() {
        case "fuel during", "fueling", "fuel":
            result.fuel = value
        case "note", "notes":
            result.noteSentences.append(value)
        case "structure":
            appendChain(value, into: &result)
        default:
            result.segments.append(DetailSegment(label: label, text: stripRPE(value, into: &result)))
        }
    }

    /// Prose (usually the summary day-line): drop the "Title —" prefix and the
    /// "Total: …" clause (duplicated by the big stats), keep structure chains
    /// and coaching sentences.
    private func ingestProse(_ line: String, into result: inout ParsedDetail) {
        var text = line
        // Strip leading "Title — " (dash must be space-surrounded so hyphenated
        // titles like "Medium-Long Run" don't split mid-word)
        if let dashRange = text.range(of: #"^.{1,60}?\s[–—\-]\s+"#, options: .regularExpression) {
            text = String(text[dashRange.upperBound...])
        }
        for rawSentence in text.components(separatedBy: ". ") {
            var sentence = rawSentence.trimmingCharacters(in: .whitespaces)
            if sentence.hasSuffix(".") { sentence = String(sentence.dropLast()) }
            guard !sentence.isEmpty else { continue }

            let lower = sentence.lowercased()
            if lower.hasPrefix("total:") || lower.hasPrefix("total ") {
                _ = stripRPE(sentence, into: &result)   // keep the RPE, drop the duplicate stats
                // "Total: 7 km …, with 4 × 20 sec strides …" — the tail is real instruction
                if let withRange = sentence.range(of: ", with ", options: .caseInsensitive) {
                    let extra = String(sentence[withRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !extra.isEmpty {
                        result.noteSentences.append("With " + extra + ".")
                    }
                }
            } else if lower.hasPrefix("fuel during:") || lower.hasPrefix("fueling:") {
                if let colonIdx = sentence.firstIndex(of: ":") {
                    result.fuel = String(sentence[sentence.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                }
            } else if sentence.contains(", then ") {
                appendChain(sentence, into: &result)
            } else {
                result.noteSentences.append(stripRPE(sentence, into: &result) + ".")
            }
        }
    }

    private func appendChain(_ text: String, into result: inout ParsedDetail) {
        let parts = text.components(separatedBy: ", then ")
        for part in parts {
            var cleaned = part.trimmingCharacters(in: .whitespaces)
            if cleaned.lowercased().hasPrefix("then ") { cleaned = String(cleaned.dropFirst(5)) }
            if cleaned.hasSuffix(".") { cleaned = String(cleaned.dropLast()) }
            guard !cleaned.isEmpty else { continue }
            result.segments.append(DetailSegment(label: nil, text: cleaned.prefix(1).uppercased() + cleaned.dropFirst()))
        }
    }

    /// Pull "(RPE n)" / "RPE n–m" out of a string into the headline stat.
    private func stripRPE(_ text: String, into result: inout ParsedDetail) -> String {
        var cleaned = text
        if let range = cleaned.range(of: #"\(?RPE\s*([\d–\-]+)\)?"#, options: .regularExpression) {
            if result.rpe == nil {
                let matched = String(cleaned[range])
                result.rpe = matched
                    .replacingOccurrences(of: "(", with: "")
                    .replacingOccurrences(of: ")", with: "")
                    .replacingOccurrences(of: "RPE", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
            cleaned.removeSubrange(range)
        }
        return cleaned
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
    }
    
    var body: some View {
        Group {
            if isCompletedRun { completedRunBody }
            else if workout.isCompleted { legacyBody }
            else { redesignedBody }
        }
    }

    private var completedRunBody: some View {
        ZStack {
            StridePageBackdrop().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(sheetInk)
                                .frame(width: 42, height: 42)
                                .background(sheetInk.opacity(0.09), in: Circle())
                        }
                        .accessibilityLabel("Close run details")
                    }
                    .padding(.horizontal, 22)
                    CompletedRunDetailContent(workout: workout, run: historyRun)
                }
                .padding(.top, 14)
                .padding(.bottom, 32)
            }
        }
        .preferredColorScheme(appearance.colorScheme)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var redesignedBody: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: workout.workoutType.icon)
                            .font(.system(size: 13, weight: .semibold))
                        Text("\(workout.workoutType.displayName.uppercased()) / SESSION")
                            .font(.runEyebrow(10))
                            .tracking(1.2)
                    }
                    .foregroundStyle(Color.stridePrimary)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(sheetInk)
                            .frame(width: 36, height: 36)
                            .background(sheetInk.opacity(0.08), in: Circle())
                            .overlay(Circle().stroke(sheetInk.opacity(0.13), lineWidth: 0.6))
                    }
                    .accessibilityLabel("Close workout")
                }

                Text(workout.title.uppercased())
                    .font(.barlowCondensed(size: 48, weight: .medium))
                    .foregroundStyle(sheetInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 14)
                Text(workout.date.formatted(.dateTime.weekday(.wide).month(.wide).day())
                     + (workout.week.map { " · Week \($0.weekNumber)" } ?? ""))
                    .font(.inter(size: 12))
                    .foregroundStyle(sheetMuted)
                    .padding(.top, 5)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        if let distance = workout.distanceKm {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text(distance == floor(distance) ? String(format: "%.0f", distance) : String(format: "%.1f", distance))
                                    .font(.barlowCondensed(size: 76, weight: .medium))
                                Text("KM").font(.barlowCondensed(size: 25)).foregroundStyle(sheetMuted)
                            }
                            .foregroundStyle(sheetInk)
                        } else {
                            Text(isGymWorkout ? "\(gymItems.count)" : (workout.durationDisplay ?? "—"))
                                .font(.barlowCondensed(size: 76, weight: .medium))
                                .foregroundStyle(sheetInk)
                        }
                        Text(isGymWorkout ? "EXERCISES" : (workout.durationDisplay.map { "EST. \($0)" } ?? "PLANNED SESSION"))
                            .font(.runEyebrow(10))
                            .tracking(1)
                            .foregroundStyle(sheetMuted)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 6) {
                        if workout.workoutType != .longRun, let pace = workout.paceDescription {
                            Text("PACE TARGET")
                                .font(.runEyebrow(9))
                                .tracking(1)
                                .foregroundStyle(sheetMuted)
                            Text(pace)
                                .font(.barlowCondensed(size: 27, weight: .medium))
                                .foregroundStyle(sheetInk)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        if let band = HeartRateZones.band(for: workout.workoutType) {
                            Text("♥  \(band) BPM")
                                .font(.runEyebrow(10))
                                .foregroundStyle(sheetMuted)
                        }
                    }
                }
                .padding(.top, 23)
                .padding(.bottom, 20)

                Rectangle().fill(sheetInk.opacity(0.18)).frame(height: 0.5)

                HStack {
                    Text("THE SESSION")
                    Spacer()
                    Text(isGymWorkout ? "\(gymItems.count) EXERCISES" : "\(sessionSteps.count) PHASE\(sessionSteps.count == 1 ? "" : "S")")
                }
                .font(.runEyebrow(10))
                .tracking(1.2)
                .foregroundStyle(sheetMuted)
                .padding(.top, 22)
                .padding(.bottom, 12)

                if isGymWorkout {
                    ForEach(Array(gymItems.enumerated()), id: \.offset) { index, item in
                        phaseRow(number: index + 1, title: item.name, detail: item.scheme, highlighted: index == 0)
                    }
                } else {
                    ForEach(Array(sessionSteps.enumerated()), id: \.offset) { index, step in
                        phaseRow(number: index + 1, title: step.title,
                                 detail: step.detail, highlighted: index == sessionSteps.count - 1)
                    }
                }

                if !isGymWorkout, workout.workoutType != .longRun, sessionSteps.count > 1 {
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(sessionSteps.indices, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(index == sessionSteps.count - 1 ? Color.stridePrimary : Color.stridePrimary.opacity(0.55))
                                .frame(height: index == sessionSteps.count - 1 ? 24 : 11)
                        }
                    }
                    .frame(height: 26)
                    .padding(.top, 13)
                    .accessibilityLabel("\(sessionSteps.count) session phases")
                }

                if let fuel = effectiveFuel(for: parsedDetail) {
                    fuelCard(fuel)
                }
                if let note = coachNoteText {
                    noteStrip(note)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .background(sheetBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: startSelectedWorkout) {
                HStack(spacing: 10) {
                    Text(hasSavedGymSession ? "RESUME SESSION" : "START SESSION")
                    Image(systemName: "arrow.up.right")
                }
                .font(.barlowCondensed(size: 24, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(Color.stridePrimary, in: Capsule())
            }
            .disabled(workout.workoutType == .rest)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .background(sheetBackground)
        }
        .fullScreenCover(isPresented: $showGymPlayer) {
            GymWorkoutPlayerView(workout: workout) { summary in
                onComplete()
                Task {
                    _ = try? await APIService.shared.logQuickStrengthSession(
                        date: Date(), perceivedEffort: nil, notes: summary
                    )
                }
                dismiss()
            }
        }
        .presentationDetents([.fraction(0.88)])
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
    }

    private func phaseRow(number: Int, title: String, detail: String?, highlighted: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(String(format: "%02d", number))
                .font(.runEyebrow(10))
                .foregroundStyle(highlighted ? .white : sheetMuted)
                .frame(width: 27, height: 27)
                .background(highlighted ? Color.stridePrimary : sheetInk.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title.uppercased())
                    .font(.barlowCondensed(size: 24, weight: .medium))
                    .foregroundStyle(sheetInk)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.inter(size: 12))
                        .foregroundStyle(sheetMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .overlay(alignment: .leading) {
            Rectangle().fill(sheetInk.opacity(0.14))
                .frame(width: 1)
                .offset(x: 13, y: 27)
                .padding(.bottom, 26)
        }
    }

    private func noteStrip(_ text: String) -> some View {
        let bullets = text.components(separatedBy: ". ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Circle().fill(Color.stridePrimary).frame(width: 4, height: 4)
                    Text(bullet).font(.inter(size: 12)).foregroundStyle(sheetMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(sheetInk.opacity(0.06), in: RoundedRectangle(cornerRadius: 15))
            .padding(.top, 12)
    }

    private func fuelCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "fork.knife")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.orange, in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text("FUEL YOUR RUN")
                    .font(.runEyebrow(10))
                    .tracking(1.1)
                    .foregroundStyle(Color.orange)
                Text(text)
                    .font(.inter(size: 13))
                    .foregroundStyle(sheetInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.orange.opacity(0.18), lineWidth: 0.6))
        .padding(.top, 14)
    }

    private func startSelectedWorkout() {
        if isGymWorkout && !GymSessionModel.stages(fromPrescription: workout.details ?? workout.title).isEmpty {
            showGymPlayer = true
        } else if workout.workoutType.isRunnable {
            dismiss()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .strideStartPlannedWorkout, object: workout)
            }
        } else {
            onComplete()
            dismiss()
        }
    }

    private var legacyBody: some View {
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
                    if isCompletedRun {
                        CompletedRunDetailContent(workout: workout, run: historyRun)
                    } else {
                    // Flag Icon Header
                    FlagIconView(size: 24)
                        .foregroundColor(.primary)
                    
                    // Workout Type Badge
                    HStack(spacing: 8) {
                        if workout.isCompleted {
                            CheckmarkCircleView(isCompleted: true, size: 16)
                        } else if workout.isPeloton {
                            Image("PelotonLogo")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 12, height: 16)
                                .foregroundColor(workout.typeColor)
                        } else {
                            Circle()
                                .fill(workout.typeColor)
                                .frame(width: 16, height: 16)
                        }

                        Text(workout.isCompleted
                             ? (workout.isPeloton ? (workout.isPelotonStrength ? "Strength Completed" : "Ride Completed") : (isGymWorkout ? "Gym Completed" : "\(workout.title) Completed"))
                             : (workout.isPeloton ? (workout.isPelotonStrength ? "Peloton Strength" : "Peloton Ride") : (isGymWorkout ? "Gym" : workout.workoutType.displayName)))
                            .font(.inter(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    
                    // Main Stats - Distance & Pace (or Duration for gym/non-run workouts)
                    HStack(alignment: .top, spacing: 32) {
                        // Distance
                        if let distanceKm = workout.distanceKm {
                            statBlock(
                                value: distanceKm == floor(distanceKm) ? "\(Int(distanceKm))" : String(format: "%.1f", distanceKm),
                                label: "km"
                            )
                        } else if isGymWorkout && !GymSessionModel.stages(fromPrescription: workout.details ?? workout.title).isEmpty {
                            // Prescription gym session: exercise count is the honest
                            // headline (the parsed "duration" is just the SkiErg warm-up)
                            statBlock(value: "\(gymItems.count)", label: "exercises")
                        } else if let duration = workout.durationDisplay {
                            // Show duration prominently when no distance (cross-training)
                            statBlock(value: duration, label: "Duration")
                        }

                        // Pace — value without the unit; unit lives in the label
                        if let pace = workout.paceDescription {
                            statBlock(
                                value: pace.replacingOccurrences(of: "/km", with: "").trimmingCharacters(in: .whitespaces),
                                label: "min/km"
                            )
                        }


                        // Heart-rate band — keeps easy days honestly easy
                        if let hr = HeartRateZones.band(for: workout.workoutType) {
                            statBlock(value: hr, label: "bpm")
                        }
                    }
                    .padding(.horizontal, 16)
                    
                    // Workout Details Card
                    if isGymWorkout {
                        if !gymItems.isEmpty {
                            gymDetailCard
                        }
                    } else if !parsedDetail.isEmpty || effectiveFuel(for: parsedDetail) != nil {
                        runDetailCard(parsedDetail)
                    }
                    
                    }
                    // Bottom Action Button (only for non-completed workouts)
                    if workout.workoutType != .rest && !workout.isCompleted {
                        Button(action: {
                            if isGymWorkout && !GymSessionModel.stages(fromPrescription: workout.details ?? workout.title).isEmpty {
                                showGymPlayer = true
                            } else if workout.workoutType.isRunnable {
                                // Route to the Run tab — completion comes from
                                // actually running, never from this button.
                                NotificationCenter.default.post(
                                    name: .strideSwitchToRunTab, object: nil)
                                dismiss()
                            } else {
                                onComplete()
                                dismiss()
                            }
                        }) {
                            Text(hasSavedGymSession ? "Resume Workout" : "Start Workout")
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
            .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("--history-bottom") ? .bottom : .top)
        }
        .background(Color(.systemGroupedBackground))
        .onPreferenceChange(ContentHeightKey.self) { height in
            guard !isCompletedRun, height.isFinite, abs(contentHeight - height) > 1 else { return }
            contentHeight = height
        }
        .fullScreenCover(isPresented: $showGymPlayer) {
            GymWorkoutPlayerView(workout: workout) { summary in
                // Mark complete locally + log the session (with adjustments) server-side
                onComplete()
                Task {
                    _ = try? await APIService.shared.logQuickStrengthSession(
                        date: Date(), perceivedEffort: nil, notes: summary
                    )
                }
                dismiss()
            }
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Stat Block

    private func statBlock(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.barlowCondensed(size: 52, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)

            Text(label)
                .font(.inter(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
        }
    }

    /// Every long run carries fueling guidance: the coach's own line when
    /// present, otherwise a sensible default scaled to the distance.
    private func effectiveFuel(for detail: ParsedDetail) -> String? {
        if let fuel = detail.fuel { return fuel }
        guard workout.workoutType == .longRun else { return nil }
        let km = workout.distanceKm ?? 0
        if km >= 20 {
            return "40–60 g carbs per hour from the start, plus fluids at every opportunity."
        } else if km >= 14 {
            return "30–60 g carbs per hour after the first hour; carry fluids."
        } else {
            return "Carry fluids; a gel is optional past the hour mark."
        }
    }

    // MARK: - Gym Detail Card

    private var gymDetailCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "dumbbell")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                Text("Session")
                    .font(.interSemibold(15))
                    .foregroundStyle(.primary)
                if let focus = gymFocus {
                    Spacer()
                    Text(focus)
                        .font(.inter(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(.systemGray6)))
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(gymItems.enumerated()), id: \.element.id) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(item.name)
                            .font(.inter(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let role = gymItemRole(index: index, item: item) {
                            Text(role)
                                .font(.inter(size: 10, weight: .bold))
                                .kerning(0.5)
                                .foregroundStyle(Color.stridePrimary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.stridePrimary.opacity(0.1)))
                        }
                        Spacer(minLength: 12)
                        if let scheme = item.scheme {
                            Text(GymSessionModel.equipmentUnits(in: "\(item.name) \(scheme)").dropFirst(item.name.count + 1))
                                .font(.barlowCondensed(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    .padding(.vertical, 9)

                    if index < gymItems.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        .padding(.horizontal, 16)
    }

    /// "WARM-UP" / "FINISHER" role pill for SkiErg bookend items.
    private func gymItemRole(index: Int, item: GymItem) -> String? {
        guard item.name.lowercased().contains("skierg") else { return nil }
        if index == 0 { return "WARM-UP" }
        if index == gymItems.count - 1 { return "FINISHER" }
        return nil
    }

    // MARK: - Run Detail Card

    private func runDetailCard(_ detail: ParsedDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Session structure — every row formatted identically
            if !detail.segments.isEmpty {
                HStack(spacing: 8) {
                    TreadmillIconView(size: 20, color: .primary)
                    Text("Session")
                        .font(.interSemibold(15))
                        .foregroundStyle(.primary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(detail.segments.enumerated()), id: \.element.id) { index, segment in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            if let label = segment.label {
                                Circle()
                                    .fill(workout.typeColor)
                                    .frame(width: 6, height: 6)
                                    .offset(y: -2)
                                (Text(label + "  ").font(.inter(size: 14, weight: .semibold)).foregroundColor(.primary)
                                 + Text(segment.text).font(.inter(size: 14, weight: .regular)).foregroundColor(.secondary))
                                    .lineSpacing(2)
                            } else {
                                Text("\(index + 1)")
                                    .font(.barlowCondensed(size: 13, weight: .semibold))
                                    .foregroundStyle(workout.typeColor)
                                    .frame(width: 16, height: 16)
                                    .background(Circle().fill(workout.typeColor.opacity(0.15)))
                                Text(segment.text)
                                    .font(.inter(size: 14, weight: .regular))
                                    .foregroundStyle(.primary)
                                    .lineSpacing(2)
                            }
                        }
                    }
                }
            }

            // Fueling strip — always present on long runs
            if let fuel = effectiveFuel(for: detail) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.orange)
                    (Text("Fuel  ").font(.inter(size: 13, weight: .semibold)).foregroundColor(.primary)
                     + Text(fuel).font(.inter(size: 13, weight: .regular)).foregroundColor(.secondary))
                        .lineSpacing(2)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            // Coach's note
            if let note = detail.note {
                if !detail.segments.isEmpty || effectiveFuel(for: detail) != nil {
                    Divider()
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.stridePrimary)
                    Text(note)
                        .font(.inter(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        .padding(.horizontal, 16)
    }

    // MARK: - Result Helpers

    private func formatResultDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private func formatResultPace(_ paceDisplay: String?) -> String {
        guard let pace = paceDisplay else { return "--" }
        return pace.replacingOccurrences(of: " /km", with: "")
    }

    private func formatResultDistance(_ km: Double) -> String {
        if km == floor(km) {
            return "\(Int(km))"
        }
        return String(format: "%.1f", km)
    }

    private func resultScoreColor(_ score: Int) -> Color {
        switch score {
        case 90...100: return .green
        case 75..<90: return .stridePrimary
        case 60..<75: return .orange
        default: return .red
        }
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
}

// MARK: - WorkoutType Extension
extension WorkoutType {
    var isRunRelated: Bool {
        switch self {
        case .easyRun, .longRun, .tempoRun, .intervals, .fartlek, .hillRepeats, .drills, .recovery, .race:
            return true
        case .rest, .crossTraining, .gym, .mobility:
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

/// Completed runs tell one story: recorded results against targets, then the evidence.
struct CompletedRunDetailContent: View {
    let workout: Workout
    let run: RunLog?
    @Environment(\.modelContext) private var modelContext
    @StateObject private var coach = PostRunCoachViewModel()
    @State private var reviewSaveError: String?
    @AppStorage(RunLobbyAppearance.storageKey) private var appearanceRaw = RunLobbyAppearance.black.rawValue
    private var appearance: RunLobbyAppearance { RunLobbyAppearance(rawValue: appearanceRaw) ?? .black }
    private var style: StridePageStyle { .init(appearance: appearance) }

    private var distance: Double? { run?.distanceKm ?? workout.actualDistanceKm }
    private var duration: Double? { run?.durationSeconds ?? workout.actualDurationSeconds }
    private var targetDistance: Double? { run?.plannedDistanceKm ?? workout.distanceKm }
    private var targetPace: String? { run?.plannedPaceDescription ?? workout.paceDescription }
    private var pace: Double? {
        run?.avgPaceSecPerKm ?? workout.actualAvgPaceSecPerKm
            ?? distance.flatMap { km in duration.flatMap { km > 0 ? $0 / km : nil } }
    }
    private let splits: [CodableKilometerSplit]
    private let hrSamples: [CodableHRSample]
    private let speedSamples: [RunSpeedSample]
    private let splitHeartRates: [Int: Int]
    @Query private var matchingShoes: [Shoe]

    init(workout: Workout, run: RunLog?) {
        self.workout = workout
        self.run = run
        let logged = run?.decodedKmSplits ?? []
        let splits = (logged.isEmpty ? workout.decodedKmSplits : logged).sorted { $0.kilometer < $1.kilometer }
        self.splits = splits
        let hr = run?.decodedHRSamples ?? []
        self.hrSamples = hr
        self.speedSamples = run?.speedSamplesJSON?.data(using: .utf8)
            .flatMap { try? JSONDecoder().decode([RunSpeedSample].self, from: $0) } ?? []
        self.splitHeartRates = Dictionary(splits.compactMap { split in
            RunHistoryMetrics.splitHeartRate(split, allSplits: splits, samples: hr).map { (split.kilometer, $0) }
        }, uniquingKeysWith: { first, _ in first })
        if let shoeID = run?.shoeId {
            _matchingShoes = Query(filter: #Predicate<Shoe> { $0.id == shoeID })
        } else if let name = run?.shoeName {
            _matchingShoes = Query(filter: #Predicate<Shoe> { $0.name == name })
        } else {
            _matchingShoes = Query(filter: #Predicate<Shoe> { _ in false })
        }
    }

    private var recordedShoe: Shoe? { matchingShoes.count == 1 ? matchingShoes.first : nil }
    private var hrBand: String? {
        if let run, run.plannedWorkoutType == nil, run.plannedWorkoutTitle == nil { return nil }
        return HeartRateZones.band(for: run?.plannedWorkoutType ?? workout.workoutType)
    }
    private var hrRange: ClosedRange<Int>? {
        let values = (hrBand ?? "").split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard values.count == 2, values[0] <= values[1] else { return nil }
        return values[0]...values[1]
    }
    private var speedRange: ClosedRange<Double>? {
        guard let range = RunScoringService.parsePaceRange(targetPace), range.min > 0, range.max >= range.min else { return nil }
        return (3600 / range.max)...(3600 / range.min)
    }
    private var savedReview: String? {
        let text = (run?.coachNotes ?? workout.savedCoachNotes)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            historyHeader
            if let score = run?.completionScore ?? workout.completionScore {
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    Text("\(score)")
                        .font(.barlowCondensed(size: 73))
                        .monospacedDigit()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SESSION SCORE")
                            .font(.runEyebrow(10))
                            .foregroundStyle(style.muted)
                        Text("AGAINST YOUR PLAN")
                            .font(.runEyebrow(9))
                            .foregroundStyle(appearance == .red ? .white : Color.stridePrimary)
                    }
                    Spacer()
                    Text("/100")
                        .font(.runEyebrow(11))
                        .foregroundStyle(style.muted)
                }
                .overlay(alignment: .bottom) { Rectangle().fill(style.rule).frame(height: 0.5) }
            }

            if let routeJSON = run?.routeJSON {
                RouteMapView(routeJSON: routeJSON, paceData: splits, showPaceColors: false)
            }

            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 22) {
                metric(distance.map(number) ?? "—", title: "DISTANCE · KM", detail: distanceTarget)
                metric(duration.map(time) ?? "—", title: "TOTAL TIME", detail: timeTarget)
                metric(pace.map(time) ?? "—", title: "AVG PACE · /KM", detail: paceTarget)
                metric(run?.avgHeartRate.map(String.init) ?? "—", title: "AVG HEART RATE · BPM",
                       detail: hrBand.map { "Target \($0) bpm" } ?? "No heart-rate target", pink: true)
            }
            .padding(20)
            .stridePageCard(style, radius: 22)

            if !splits.isEmpty { splitsCard }

            if speedSamples.count >= 2, let duration {
                RunSpeedGraphView(samples: speedSamples, duration: duration, targetSpeedRange: speedRange)
            } else {
                missingChart("Speed", message: "Speed history wasn’t recorded for this run.", color: .stridePrimary)
            }
            if let json = run?.hrSamplesJSON, hrSamples.count >= 2 {
                HeartRateGraphView(hrSamplesJSON: json, avgHeartRate: run?.avgHeartRate,
                    maxHeartRate: run?.maxHeartRate, duration: duration, targetRange: hrRange)
            } else {
                missingChart("Heart Rate", message: "Heart-rate history wasn’t recorded for this run.", color: .heartRatePink)
            }

            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Shoes", icon: "shoeprints.fill")
                HStack(spacing: 14) {
                    if let shoe = recordedShoe { ShoePhotoView(shoe: shoe, size: 64) }
                    else {
                        Image(systemName: "shoe.2").font(.system(size: 28)).foregroundStyle(.secondary)
                            .frame(width: 64, height: 64).background(Color(.systemGray6), in: Circle())
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            shoeName
                            shoeUsage
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            shoeName
                            shoeUsage
                        }
                    }
                }
            }
            .historyCard(style)

            if let rating = run?.feedbackRating, (0...5).contains(rating) {
                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle("How It Felt", icon: "heart.text.square")
                    Text("\(rating) / 5 · \(["Terrible", "Rough", "Tough", "Okay", "Good", "Amazing"][rating])")
                        .font(.barlowCondensed(size: 29))
                }
                .historyCard(style)
            }
            if let notes = run?.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle("Your Notes", icon: "text.bubble")
                    Text(notes).font(.inter(size: 14)).lineSpacing(4)
                }
                .historyCard(style)
            }

            coachCard

        }
        .padding(.horizontal, 22)
        .foregroundStyle(style.ink)
        .onChange(of: coach.isGenerating) { _, generating in
            guard !generating, coach.error == nil, !coach.coachText.isEmpty else { return }
            workout.savedCoachNotes = coach.coachText
            run?.coachNotes = coach.coachText
            do { try modelContext.save() }
            catch { reviewSaveError = "This review couldn’t be saved. Please try again." }
        }
    }

    private var historyHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                FlagIconView(size: 16, color: .stridePrimary)
                Text("RUN HISTORY / COMPLETED")
                    .font(.runEyebrow(10))
                    .tracking(1.2)
                    .foregroundStyle(appearance == .red ? .white : Color.stridePrimary)
            }
            Text(workout.title.uppercased())
                .font(.barlowCondensed(size: 46))
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            Text((run?.completedAt ?? workout.completedAt ?? workout.date)
                .formatted(.dateTime.weekday(.wide).month(.wide).day().year()).uppercased())
                .font(.runEyebrow(10))
                .foregroundStyle(style.muted)
        }
        .padding(.top, 4)
    }

    private var shoeName: some View {
        Text(run?.shoeName ?? recordedShoe?.name ?? "Not recorded")
            .font(.inter(size: 16, weight: .medium))
            .foregroundStyle(run?.shoeName == nil && recordedShoe == nil ? style.muted : style.ink)
    }
    @ViewBuilder private var shoeUsage: some View {
        if let shoe = recordedShoe {
            Text("|  \(shoe.usage.displayName)")
                .font(.inter(size: 12)).foregroundStyle(.secondary)
        }
    }

    private var distanceTarget: String {
        guard let distance, let targetDistance else { return "No distance target" }
        return "\(number(distance)) / \(number(targetDistance)) km"
    }
    private var timeTarget: String {
        if let minutes = run?.plannedDurationMinutes ?? workout.durationMinutes { return "Target \(time(Double(minutes * 60)))" }
        return "Elapsed run time"
    }
    private var paceTarget: String {
        targetPace.map { "Target " + $0.replacingOccurrences(of: "/km", with: "").trimmingCharacters(in: .whitespaces) + " /km" } ?? "No pace target"
    }

    private func metric(_ value: String, title: String, detail: String, pink: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.runEyebrow(9)).foregroundStyle(style.muted)
            Text(value).font(.barlowCondensed(size: 48, weight: .medium))
                .foregroundStyle(pink ? Color.heartRatePink : style.ink)
                .lineLimit(1).minimumScaleFactor(0.65).monospacedDigit()
            Text(detail).font(.runEyebrow(10)).foregroundStyle(style.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var splitsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Kilometer Splits", icon: "flag.checkered")
            HStack(spacing: 0) {
                Text("KM").frame(width: 42, alignment: .leading)
                Text("Pace /km").frame(maxWidth: .infinity, alignment: .leading)
                Text("Time").frame(width: 66, alignment: .trailing)
                Text("HR").foregroundStyle(Color.heartRatePink).frame(width: 48, alignment: .trailing)
            }
            .font(.inter(size: 10, weight: .medium)).foregroundStyle(.secondary)
            ForEach(splits) { split in
                HStack(spacing: 0) {
                    HStack(spacing: 3) {
                        Text("\(split.kilometer)")
                        if split.isFastest { Image(systemName: "flame.fill").font(.system(size: 9)).foregroundStyle(Color.stridePrimary) }
                    }.frame(width: 42, alignment: .leading)
                    Text(split.pace).frame(maxWidth: .infinity, alignment: .leading)
                    Text(RunHistoryMetrics.elapsedSeconds(split.time).map(time) ?? split.time).frame(width: 66, alignment: .trailing)
                    Text(splitHeartRates[split.kilometer].map(String.init) ?? "—")
                        .foregroundStyle(Color.heartRatePink).frame(width: 48, alignment: .trailing)
                }
                .font(.barlowCondensed(size: 21, weight: .medium)).monospacedDigit()
                .padding(.vertical, 5)
                if split.id != splits.last?.id { Divider().overlay(Color.stridePrimary.opacity(0.08)) }
            }
            Text("HR: average of recorded readings in each kilometer. — means no data.")
                .font(.inter(size: 10)).foregroundStyle(.secondary)
        }
        .historyCard(style)
    }

    private var coachCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("AI Coach’s Notes", icon: "sparkles")
            if let review = savedReview {
                Text(review).font(.inter(size: 14)).lineSpacing(5)
            } else {
                if !coach.coachText.isEmpty { Text(coach.coachText).font(.inter(size: 14)).lineSpacing(5) }
                if coach.isGenerating {
                    HStack(spacing: 8) { ProgressView(); Text("Reviewing your run…").font(.inter(size: 12)) }
                } else {
                    if coach.coachText.isEmpty {
                        Text("No coach review was saved for this run.").font(.inter(size: 13)).foregroundStyle(.secondary)
                    }
                    Button {
                        reviewSaveError = nil
                        coach.generateCoaching(result: reviewResult, speak: false)
                    } label: {
                        Label("Review this run", systemImage: "sparkles")
                            .font(.inter(size: 13, weight: .semibold)).foregroundStyle(Color.stridePrimary)
                    }
                    .disabled(distance == nil || duration == nil)
                }
            }
            if let error = coach.error ?? reviewSaveError {
                Text(error).font(.inter(size: 12)).foregroundStyle(Color.stridePrimary)
            }
        }
        .historyCard(style)
    }

    private var reviewResult: RunResult {
        RunResult(sessionID: run?.id ?? workout.id,
            completedAt: run?.completedAt ?? workout.completedAt ?? workout.date,
            distanceKm: distance ?? 0, durationSeconds: duration ?? 0, avgPaceSecPerKm: pace ?? 0,
            kmSplits: splits.map { KilometerSplit(kilometer: $0.kilometer, pace: $0.pace, time: $0.time,
                isFastest: $0.isFastest, diffFromFastest: nil) },
            plannedWorkoutId: workout.id, plannedWorkoutTitle: workout.title,
            plannedWorkoutType: run?.plannedWorkoutType ?? workout.workoutType,
            targetDistanceKm: targetDistance, targetPaceDescription: targetPace,
            targetDurationMinutes: run?.plannedDurationMinutes ?? workout.durationMinutes,
            dataSource: run?.dataSource ?? "manual", treadmillBrand: run?.treadmillBrand,
            routeJSON: run?.routeJSON, elevationGainMeters: run?.elevationGainMeters,
            elevationLossMeters: run?.elevationLossMeters,
            avgHeartRate: run?.avgHeartRate, maxHeartRate: run?.maxHeartRate,
            hrSamplesJSON: run?.hrSamplesJSON, speedSamples: speedSamples,
            plannedWorkoutDetails: workout.details,
            totalPauseDurationSeconds: 0, completedPauseDurations: [])
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title.uppercased(), systemImage: icon).font(.barlowCondensed(size: 23))
    }
    private func missingChart(_ title: String, message: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.inter(size: 14, weight: .semibold)).foregroundStyle(color)
            Text(message).font(.inter(size: 12)).foregroundStyle(.secondary)
        }.historyCard(style)
    }
    private func number(_ value: Double) -> String {
        value == floor(value) ? String(Int(value)) : String(format: "%.2f", value)
    }
    private func time(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.rounded()))
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
            : String(format: "%d:%02d", value / 60, value % 60)
    }
}

private extension View {
    func historyCard(_ style: StridePageStyle) -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .stridePageCard(style, radius: 20)
    }
}

#if DEBUG
struct PlannedWorkoutDetailPreview: View {
    private let container: ModelContainer
    private let workout: Workout
    @State private var showing = true

    init() {
        container = try! ModelContainer(for: Workout.self, RunLog.self, Shoe.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        if ProcessInfo.processInfo.arguments.contains("--runview-demo-long-run") {
            workout = Workout(
                date: Date(), workoutType: .longRun, title: "Long Run with MP Finish",
                details: "Long Run with MP Finish — Total: 26 km. First 22 km at 6:00–6:30/km, final 4 km at 5:30/km (adjusted MP, RPE 5–6). Fuel during: 40–60 g carbs per hour.",
                distanceKm: 26, paceDescription: "6:00–6:30/km"
            )
        } else {
            workout = Workout(
                date: Date(), workoutType: .intervals, title: "VO₂ Intervals",
                details: "Warm-up: 2 km easy at 6:00–6:30/km\nMain set: 5 × 1 km at 4:50–5:05/km with 500 m easy between reps\nCool-down: 3 km relaxed\nNotes: Keep the reps controlled. Take each recovery easy.",
                distanceKm: 12, paceDescription: "4:50–5:05/km"
            )
        }
        container.mainContext.insert(workout)
    }

    var body: some View {
        Color.black.ignoresSafeArea()
            .sheet(isPresented: $showing) {
                WorkoutDetailView(workout: workout, onComplete: {})
                    .modelContainer(container)
                    .preferredColorScheme(.dark)
            }
    }
}

/// Isolated simulator fixture: exercises the real sheet without touching an athlete's store.
struct CompletedRunHistoryPreview: View {
    private let container: ModelContainer
    private let workout: Workout
    @State private var showing = true
    @State private var lastPresentation = Date()

    init() {
        container = try! ModelContainer(for: Workout.self, RunLog.self, Shoe.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let saturday = ProcessInfo.processInfo.arguments.contains("--history-saturday")
        let missing = saturday || ProcessInfo.processInfo.arguments.contains("--history-missing-data")
        workout = Workout(date: Date(), workoutType: .easyRun, title: "Easy Run",
            distanceKm: 6, paceDescription: "6:00–6:30/km")
        workout.isCompleted = true
        workout.completedAt = workout.date
        workout.actualDistanceKm = 6
        workout.actualDurationSeconds = 2366
        workout.actualAvgPaceSecPerKm = 2366 / 6
        workout.completionScore = 97
        let values = [385, 385, 394, 406, 399, 397]
        var elapsed = 0
        let splits = values.enumerated().map { index, seconds in
            elapsed += seconds
            return CodableKilometerSplit(kilometer: index + 1,
                pace: String(format: "%d:%02d", seconds / 60, seconds % 60),
                time: String(format: "%d:%02d", elapsed / 60, elapsed % 60), isFastest: index == 0)
        }
        workout.kmSplitsJSON = String(data: try! JSONEncoder().encode(splits), encoding: .utf8)
        let log = RunLog(distanceKm: 6, durationSeconds: 2366, avgPaceSecPerKm: 2366 / 6,
            kmSplitsJSON: workout.kmSplitsJSON, avgHeartRate: missing ? nil : 142,
            maxHeartRate: missing ? nil : 150, shoeName: missing ? nil : "Indoor Zoom Fly",
            plannedWorkoutId: workout.id, plannedWorkoutTitle: workout.title,
            plannedWorkoutTypeRaw: "easy_run", plannedDistanceKm: 6,
            plannedPaceDescription: "6:00–6:30/km", completionScore: 97)
        log.completedAt = workout.date
        if saturday {
            workout.date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 10))!
            workout.completedAt = workout.date
            workout.title = "Recovery Run"
            workout.workoutType = .recovery
            workout.distanceKm = 4
            workout.actualDistanceKm = 4
            workout.actualDurationSeconds = 1620
            workout.actualAvgPaceSecPerKm = 405
            workout.paceDescription = "6:30–6:50/km"
            workout.kmSplitsJSON = nil
            workout.completionScore = nil
            log.completedAt = workout.date
            log.distanceKm = 4
            log.durationSeconds = 1620
            log.avgPaceSecPerKm = 405
            log.kmSplitsJSON = nil
            log.plannedWorkoutTitle = workout.title
            log.plannedWorkoutTypeRaw = "recovery"
            log.plannedDistanceKm = 4
            log.plannedPaceDescription = workout.paceDescription
            log.completionScore = nil
        }
        if !missing {
            let shoe = Shoe(name: "Zoom Fly", photoData: UIImage(systemName: "shoe.2")?.pngData())
            shoe.usage = .indoor
            log.shoeId = shoe.id
            log.shoeName = shoe.name
            container.mainContext.insert(shoe)
            let speeds = stride(from: 0.0, through: 2366.0, by: 5).map { t in
                RunSpeedSample(t: t, kmh: 9.15 + sin(t / 140) * 0.35 + cos(t / 33) * 0.12)
            }
            let heart = speeds.map { CodableHRSample(t: $0.t, bpm: 135 + min(11, Int($0.t / 220)) + Int(sin($0.t / 110) * 3)) }
            log.speedSamplesJSON = String(data: try! JSONEncoder().encode(speeds), encoding: .utf8)
            log.hrSamplesJSON = String(data: try! JSONEncoder().encode(heart), encoding: .utf8)
            log.coachNotes = "You completed the full 6 km. Your average pace was just outside the planned range, while your heart rate stayed controlled. Keep the next easy run conversational and leave yourself fresh for the longer session."
        }
        container.mainContext.insert(workout)
        container.mainContext.insert(log)
        try! container.mainContext.save()
    }

    var body: some View {
        Color(.systemGroupedBackground).ignoresSafeArea()
            .sheet(isPresented: $showing) {
                WorkoutDetailView(workout: workout, onComplete: {})
                    .onAppear {
                        if ProcessInfo.processInfo.arguments.contains("--history-cycle") {
                            print("HISTORY_SHEET_READY \(Int(Date().timeIntervalSince(lastPresentation) * 1000)) ms")
                        }
                    }
            }
            .modelContainer(container)
            .task {
                guard ProcessInfo.processInfo.arguments.contains("--history-cycle") else { return }
                for index in 1...5 {
                    try? await Task.sleep(for: .milliseconds(600))
                    showing = false
                    try? await Task.sleep(for: .milliseconds(400))
                    lastPresentation = Date()
                    showing = true
                    print("HISTORY_REOPEN \(index)")
                }
                try? await Task.sleep(for: .milliseconds(600))
                print("HISTORY_CYCLE_COMPLETE")
            }
    }
}
#endif


/// Stats opens the same recorded review as the calendar, including free and unlinked runs.
struct RecordedRunReviewSheet: View {
    let run: RunLog
    private let workout: Workout
    @Environment(\.dismiss) private var dismiss
    @AppStorage(RunLobbyAppearance.storageKey) private var appearanceRaw = RunLobbyAppearance.black.rawValue
    private var appearance: RunLobbyAppearance { RunLobbyAppearance(rawValue: appearanceRaw) ?? .black }

    init(run: RunLog, workout: Workout?) {
        self.run = run
        if let workout { self.workout = workout }
        else {
            let snapshot = Workout(date: run.completedAt, workoutType: run.plannedWorkoutType ?? .easyRun,
                title: run.effectiveTitle, distanceKm: run.plannedDistanceKm,
                durationMinutes: run.plannedDurationMinutes, paceDescription: run.plannedPaceDescription)
            snapshot.isCompleted = true
            snapshot.completedAt = run.completedAt
            snapshot.actualDistanceKm = run.distanceKm
            snapshot.actualDurationSeconds = run.durationSeconds
            snapshot.actualAvgPaceSecPerKm = run.avgPaceSecPerKm
            snapshot.kmSplitsJSON = run.kmSplitsJSON
            snapshot.completionScore = run.completionScore
            self.workout = snapshot
        }
    }
    var body: some View {
        ZStack {
            StridePageBackdrop().ignoresSafeArea()
            VStack(spacing: 4) {
                HStack { Spacer(); Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(appearance.foreground).frame(width: 42, height: 42).background(appearance.foreground.opacity(0.09), in: Circle()) }.accessibilityLabel("Close run details") }
                    .padding(.horizontal, 22)
                ScrollView(showsIndicators: false) { CompletedRunDetailContent(workout: workout, run: run).padding(.top, 8).padding(.bottom, 28) }
            }
        }
        .preferredColorScheme(appearance.colorScheme)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
