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
    @State private var showGymPlayer = false
    
    // Height of the drag indicator + close button area
    private let chromeHeight: CGFloat = 6
    
    private var sheetHeight: CGFloat {
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
        guard source.contains(";") else {
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
                        if workout.isCompleted {
                            CheckmarkCircleView(isCompleted: true, size: 16)
                        } else {
                            Circle()
                                .fill(workout.typeColor)
                                .frame(width: 16, height: 16)
                        }

                        Text(workout.isCompleted
                             ? (isGymWorkout ? "Gym Completed" : "\(workout.title) Completed")
                             : (isGymWorkout ? "Gym" : workout.workoutType.displayName))
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
                        } else if isGymWorkout && gymSource.contains(";") {
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

                        // Effort — parsed from the coach's (RPE n) annotation
                        if !isGymWorkout, let rpe = parsedDetail.rpe {
                            statBlock(value: rpe, label: "RPE")
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
                    
                    // Workout Results Card (for completed workouts with actual data)
                    workoutResultsCard

                    // Bottom Action Button (only for non-completed workouts)
                    if workout.workoutType != .rest && !workout.isCompleted {
                        Button(action: {
                            if isGymWorkout && gymSource.contains(";") {
                                showGymPlayer = true
                            } else {
                                onComplete()
                                dismiss()
                            }
                        }) {
                            Text("Start Workout")
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

    // MARK: - Workout Results Card

    @ViewBuilder
    private var workoutResultsCard: some View {
        if workout.isCompleted, workout.actualDistanceKm != nil {
            VStack(spacing: 16) {
                // Header
                HStack(spacing: 8) {
                    CheckmarkCircleView(isCompleted: true, size: 18)

                    Text("Workout Results")
                        .font(.interSemibold(15))
                        .foregroundStyle(.primary)
                }

                // Primary stats row: Distance | Time | Pace
                HStack(spacing: 0) {
                    // Distance
                    VStack(spacing: 4) {
                        Text(formatResultDistance(workout.actualDistanceKm ?? 0))
                            .font(.barlowCondensed(size: 40, weight: .medium))
                            .foregroundColor(.primary)
                        Text("km")
                            .font(.inter(size: 13, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(width: 1, height: 44)

                    // Time
                    VStack(spacing: 4) {
                        Text(formatResultDuration(workout.actualDurationSeconds ?? 0))
                            .font(.barlowCondensed(size: 40, weight: .medium))
                            .foregroundColor(.primary)
                        Text("Time")
                            .font(.inter(size: 13, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(width: 1, height: 44)

                    // Pace
                    VStack(spacing: 4) {
                        Text(formatResultPace(workout.actualPaceDisplay))
                            .font(.barlowCondensed(size: 40, weight: .medium))
                            .foregroundColor(.primary)
                        Text("Pace /km")
                            .font(.inter(size: 13, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 8)

                // Splits table
                if !workout.decodedKmSplits.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(height: 1)

                        Text("Kilometer Splits")
                            .font(.inter(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                            .padding(.top, 4)

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

                        ForEach(workout.decodedKmSplits) { split in
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
                            .padding(.vertical, 4)

                            if split.kilometer < workout.decodedKmSplits.count {
                                Rectangle()
                                    .fill(Color.stridePrimary.opacity(0.15))
                                    .frame(height: 1)
                            }
                        }
                    }
                }

                // Score badge
                if let score = workout.completionScore {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 1)

                    HStack(spacing: 8) {
                        Text("Score")
                            .font(.inter(size: 14, weight: .medium))
                            .foregroundColor(.secondary)

                        Text("\(score)")
                            .font(.barlowCondensed(size: 28, weight: .bold))
                            .foregroundColor(resultScoreColor(score))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
            .padding(.horizontal, 16)
        }
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
                            Text(scheme)
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
