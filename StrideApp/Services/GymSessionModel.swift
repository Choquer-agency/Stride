import Foundation

/// Parses a gym prescription line ("Focus — SkiErg 4 min easy; Back Squat 3×8
/// @ 40 kg; Side Plank 3×30 sec/side @ BW; SkiErg 6 × 30 sec hard / 30 sec easy")
/// into an ordered list of guided-player stages, circuit-style:
/// warm-up → round 1 of every exercise → round 2 → … → finisher.
enum GymSessionModel {

    // MARK: - Types

    struct Stage: Identifiable {
        enum Kind {
            /// Countdown timer (SkiErg warm-up, plank holds, interval work/rest)
            case timed(seconds: Int)
            /// Rep work — loads are stored canonically in kilograms.
            case reps(repsText: String, weightKg: Double?, weightSuffix: String)
            /// No timer, no reps — user taps Done when finished (e.g. 500 m SkiErg)
            case manual(detail: String)
        }

        let id = UUID()
        let exerciseName: String
        let sectionLabel: String       // "Warm-up" | "Round 2 of 3" | "Finisher"
        let setLabel: String?          // "SET 2 OF 3"
        let sideLabel: String?         // "LEFT" | "RIGHT"
        let kind: Kind
        var timedLoadKg: Double? = nil
        var timedLoadSuffix: String = ""
        var isStartingLoad: Bool = false

        var loadKg: Double? {
            if case .reps(_, let kg, _) = kind { return kg }
            return timedLoadKg
        }
        var loadSuffix: String {
            if case .reps(_, _, let suffix) = kind { return suffix }
            return timedLoadSuffix
        }
    }

    struct ParsedExercise {
        let name: String
        let scheme: String
        let sets: Int
        let repsText: String
        let weightKg: Double?
        let weightSuffix: String       // "kg", "kg/hand", "lb", ""
        let perSide: Bool
        let holdSeconds: Int?          // timed holds ("45 sec")
        let isSkiErg: Bool
        var isStartingLoad: Bool = false
    }

    // MARK: - Entry point

    static func stages(fromPrescription source: String) -> [Stage] {
        let items = prescriptionItems(from: source)
        guard !items.isEmpty else { return [] }

        var exercises = items.map(parseExercise)
        var stages: [Stage] = []

        // Warm-up: leading SkiErg item
        if let first = exercises.first, first.isSkiErg {
            stages.append(contentsOf: skiErgStages(first,
                section: exercises.count == 1 ? "Session" : "Warm-up"))
            exercises.removeFirst()
        }

        // Finisher: trailing SkiErg item
        var finisher: ParsedExercise?
        if let last = exercises.last, last.isSkiErg {
            finisher = last
            exercises.removeLast()
        }

        // Circuit rounds across the strength work
        let maxSets = exercises.map(\.sets).max() ?? 0
        if maxSets > 0 {
            for round in 1...maxSets {
                let section = maxSets == 1 ? "Session" : "Round \(round) of \(maxSets)"
                for exercise in exercises where round <= exercise.sets {
                    stages.append(contentsOf: exerciseStages(exercise, round: round, section: section))
                }
            }
        }

        if let finisher {
            stages.append(contentsOf: skiErgStages(finisher, section: "Finisher"))
        }
        return stages
    }

    // MARK: - Item extraction (mirrors WorkoutDetailView.gymItems)

    static func prescriptionItems(from raw: String) -> [String] {
        var source = raw
        if let range = source.range(of: #"^.*?Gym(\s*\((?:AM|PM)\))?\s*[:：–—\-]\s*"#, options: .regularExpression) {
            source = String(source[range.upperBound...])
        }
        // A rescheduled SkiErg interval block is a complete workout on its own.
        guard source.contains(";") || source.lowercased().hasPrefix("skierg ") else { return [] }
        // Drop a leading focus header ("Main strength — ")
        let head = source.components(separatedBy: ";")[0]
        if let dashRange = head.range(of: #"\s[–—\-]\s"#, options: .regularExpression) {
            let focus = String(head[..<dashRange.lowerBound])
            if !focus.contains(where: \.isNumber), let focusRange = source.range(of: focus) {
                source = String(source[focusRange.upperBound...])
                if let strip = source.range(of: #"^\s*[–—\-]\s*"#, options: .regularExpression) {
                    source = String(source[strip.upperBound...])
                }
            }
        }
        return source
            .components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " .")) }
            .filter { !$0.isEmpty }
    }

    static let kilogramsPerPound = 0.45359237

    static func isDumbbell(_ text: String) -> Bool {
        let text = text.lowercased()
        if text.range(of: #"\b(dumbbells?|db)\b"#, options: .regularExpression) != nil { return true }
        if text.range(of: #"\b(barbell|kettlebells?|kb|bodyweight|bw)\b"#, options: .regularExpression) != nil { return false }
        return ["goblet squat", "split squat", "step-up", "step up", "farmer hold", "suitcase carry", "single-leg rdl", "single leg rdl", "single-leg romanian deadlift", "single leg romanian deadlift"]
            .contains(where: text.contains)
    }

    static func isBarbell(_ text: String) -> Bool {
        let text = text.lowercased()
        guard !isDumbbell(text), !text.contains("landmine"), !text.contains("single-leg"), !text.contains("single leg") else { return false }
        return ["barbell", "back squat", "front squat", "rdl", "romanian deadlift", "deadlift", "hip thrust", "good morning"]
            .contains(where: text.contains)
    }

    static func barbellPlateKg(totalKg: Double, barKg: Double) -> Double {
        max(0, (totalKg - barKg) / 2)
    }

    static func dumbbellPounds(_ kg: Double) -> Double { kg / kilogramsPerPound }
    static func roundedDumbbellKg(_ pounds: Double) -> Double {
        max(5, (pounds / 5).rounded(.toNearestOrAwayFromZero) * 5) * kilogramsPerPound
    }

    static func displayLoad(_ kg: Double, suffix: String) -> String {
        let value = suffix.hasPrefix("lb") ? dumbbellPounds(kg) : kg
        return "\(number(value)) \(suffix)"
    }

    static func number(_ value: Double) -> String {
        abs(value - value.rounded()) < 0.001 ? String(Int(value.rounded())) : String(format: "%.2f", value)
    }

    /// A shared normalization for the plan and player: convert units, never relabel kilograms as pounds.
    static func equipmentUnits(in item: String) -> String {
        let exercise = parseExercise(item)
        guard let at = item.range(of: #"@\s*"#, options: .regularExpression) else {
            if let kg = exercise.weightKg { return item + " @ " + displayLoad(kg, suffix: exercise.weightSuffix) + " (starting load)" }
            return item
        }
        guard let kg = exercise.weightKg else { return item }
        let original = String(item[at.upperBound...]).lowercased()
        let starting = original.first?.isNumber != true ? " (starting load)" : ""
        var detail = ""
        if exercise.weightSuffix.contains("total incl. bar") {
            let storedBar = UserDefaults.standard.double(forKey: "gym_bar_weight_kg")
            let bar = storedBar > 0 ? storedBar : 20
            detail = " (\(number(barbellPlateKg(totalKg: kg, barKg: bar))) kg per side + \(number(bar)) kg bar)"
        }
        return String(item[..<at.upperBound]) + displayLoad(kg, suffix: exercise.weightSuffix) + starting + detail
    }

    // MARK: - Per-exercise parsing

    static func parseExercise(_ item: String) -> ParsedExercise {
        var name = item
        var scheme = ""
        if let digitIdx = item.firstIndex(where: \.isNumber), digitIdx != item.startIndex {
            name = String(item[..<digitIdx]).trimmingCharacters(in: .whitespaces)
            scheme = String(item[digitIdx...]).trimmingCharacters(in: .whitespaces)
        }

        // Sets: leading "3×" / "3 ×" / "3x"
        var sets = 1
        var repsText = scheme
        if let match = scheme.range(of: #"^(\d+)\s*[×x]\s*"#, options: .regularExpression) {
            sets = Int(scheme[match].filter(\.isNumber)) ?? 1
            repsText = String(scheme[match.upperBound...]).trimmingCharacters(in: .whitespaces)
        }

        // Weight: "@ 40 kg", "@ 8 kg/hand", "@ 12 lb", "@ 20 kg DB", "@ BW"
        var weightKg: Double? = nil
        var weightSuffix = ""
        if let atRange = repsText.range(of: #"@\s*"#, options: .regularExpression) {
            let loadText = String(repsText[atRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            repsText = String(repsText[..<atRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            if loadText.uppercased().hasPrefix("BW") {
                weightSuffix = "BW"
            } else if let numRange = loadText.range(of: #"^[\d.]+"#, options: .regularExpression) {
                let value = Double(loadText[numRange]) ?? 0
                let unit = String(loadText[numRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                let lower = unit.lowercased()
                if lower.hasPrefix("kg") || lower.hasPrefix("lb") {
                    var kg = lower.hasPrefix("lb") ? value * kilogramsPerPound : value
                    if isDumbbell(item) {
                        kg = roundedDumbbellKg(dumbbellPounds(kg))
                        weightSuffix = "lb each"
                    } else if item.lowercased().range(of: #"\b(kettlebells?|kb)\b"#, options: .regularExpression) != nil {
                        weightSuffix = "lb" + (lower.contains("/hand") ? " each" : "")
                    } else if isBarbell(item) {
                        // Legacy prescriptions without a basis remain TOTAL loads.
                        let platesPerSide = lower.range(of: #"^(?:kgs?|lbs?)\s*(?:/side|per\s+side)"#, options: .regularExpression) != nil
                        weightSuffix = platesPerSide ? "kg per side (plates only)" : "kg total incl. bar"
                    } else if item.lowercased().contains("landmine") {
                        weightSuffix = "kg plates on loaded end"
                    } else {
                        weightSuffix = "kg" + (lower.contains("/hand") ? " per hand" : "")
                    }
                    weightKg = kg
                } else {
                    // Preserve qualitative instructions and give adjustable dumbbells a usable starting load.
                    weightSuffix = ""
                }
            }
        }

        let isStartingLoad = weightKg == nil && weightSuffix != "BW" && isDumbbell(item)
        if isStartingLoad {
            weightKg = roundedDumbbellKg(5)
            weightSuffix = "lb each"
        }

        let perSide = repsText.contains("/side") || repsText.contains("/leg")
            || repsText.lowercased().contains("each side") || repsText.lowercased().contains("each leg")

        // Timed hold: reps like "45 sec" / "30 sec/side"
        var holdSeconds: Int? = nil
        if let holdMatch = repsText.range(of: #"^(\d+)\s*sec"#, options: .regularExpression) {
            holdSeconds = Int(repsText[holdMatch].filter(\.isNumber))
        }

        return ParsedExercise(
            name: name,
            scheme: scheme,
            sets: sets,
            repsText: repsText,
            weightKg: weightKg,
            weightSuffix: weightSuffix,
            perSide: perSide,
            holdSeconds: holdSeconds,
            isSkiErg: name.lowercased().contains("skierg"),
            isStartingLoad: isStartingLoad
        )
    }

    // MARK: - Stage builders

    private static func exerciseStages(_ exercise: ParsedExercise, round: Int, section: String) -> [Stage] {
        // No set label — the "Round X of Y" section pill already carries it.
        let setLabel: String? = nil
        let sides: [String?] = exercise.perSide ? ["LEFT", "RIGHT"] : [nil]

        return sides.map { side in
            let kind: Stage.Kind
            if let hold = exercise.holdSeconds {
                kind = .timed(seconds: hold)
            } else {
                kind = .reps(repsText: exercise.repsText,
                             weightKg: exercise.weightKg,
                             weightSuffix: exercise.weightSuffix)
            }
            return Stage(
                exerciseName: exercise.name,
                sectionLabel: section,
                setLabel: setLabel,
                sideLabel: side,
                kind: kind,
                timedLoadKg: exercise.holdSeconds != nil ? exercise.weightKg : nil,
                timedLoadSuffix: exercise.holdSeconds != nil ? exercise.weightSuffix : "",
                isStartingLoad: exercise.isStartingLoad
            )
        }
    }

    private static func skiErgStages(_ exercise: ParsedExercise, section: String) -> [Stage] {
        let scheme = exercise.scheme.lowercased()

        // "4 min easy" / "3 min easy" — single countdown
        if let match = scheme.range(of: #"^(\d+)\s*min"#, options: .regularExpression) {
            let minutes = Int(scheme[match].filter(\.isNumber)) ?? 4
            return [Stage(exerciseName: "SkiErg", sectionLabel: section, setLabel: nil, sideLabel: nil,
                          kind: .timed(seconds: minutes * 60))]
        }

        // "6 × 30 sec hard / 30 sec easy" — alternating work/rest countdowns
        if let match = scheme.range(of: #"(\d+)\s*[×x]\s*(\d+)\s*sec[^/]*/\s*(\d+)\s*(sec|min)"#, options: .regularExpression) {
            let numbers = scheme[match].components(separatedBy: CharacterSet.decimalDigits.inverted)
                .compactMap { Int($0) }
            if numbers.count >= 3 {
                let rounds = numbers[0], work = numbers[1]
                let rest = scheme[match].contains("min") ? numbers[2] * 60 : numbers[2]
                var stages: [Stage] = []
                for i in 1...rounds {
                    stages.append(Stage(exerciseName: "SkiErg — Hard", sectionLabel: section,
                                        setLabel: "ROUND \(i) OF \(rounds)", sideLabel: nil,
                                        kind: .timed(seconds: work)))
                    stages.append(Stage(exerciseName: "SkiErg — Easy", sectionLabel: section,
                                        setLabel: "ROUND \(i) OF \(rounds)", sideLabel: nil,
                                        kind: .timed(seconds: rest)))
                }
                return stages
            }
        }

        // "2 × 500 m moderate" — distance work, user taps Done per rep
        if let match = scheme.range(of: #"^(\d+)\s*[×x]"#, options: .regularExpression) {
            let reps = Int(scheme[match].filter(\.isNumber)) ?? 1
            let detail = String(scheme[match.upperBound...]).trimmingCharacters(in: .whitespaces)
            return (1...reps).map { i in
                Stage(exerciseName: "SkiErg", sectionLabel: section,
                      setLabel: reps > 1 ? "REP \(i) OF \(reps)" : nil, sideLabel: nil,
                      kind: .manual(detail: detail))
            }
        }

        return [Stage(exerciseName: "SkiErg", sectionLabel: section, setLabel: nil, sideLabel: nil,
                      kind: .manual(detail: exercise.scheme))]
    }
}


/// A gym draft records progress, never completion. Restored timers wait for an explicit tap.
enum GymSessionRecoveryStore {
    struct Checkpoint: Codable {
        let ownerID: String
        let workoutID: UUID
        let prescription: String
        let sessionID: UUID
        let sessionStart: Date
        let stageIndex: Int
        let remainingSeconds: Int
        let weights: [String: Double]
    }

    private static func url(ownerID: String, workoutID: UUID) -> URL? {
        guard let owner = UUID(uuidString: ownerID),
              let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return directory.appendingPathComponent("stride-gym-\(owner.uuidString.lowercased())-\(workoutID.uuidString.lowercased()).json")
    }

    static func save(_ checkpoint: Checkpoint) throws {
        guard let url = url(ownerID: checkpoint.ownerID, workoutID: checkpoint.workoutID) else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try JSONEncoder().encode(checkpoint).write(to: url, options: options)
    }

    static func load(ownerID: String, workoutID: UUID, prescription: String, stageCount: Int) -> Checkpoint? {
        guard let url = url(ownerID: ownerID, workoutID: workoutID),
              let data = try? Data(contentsOf: url),
              let checkpoint = try? JSONDecoder().decode(Checkpoint.self, from: data),
              checkpoint.ownerID.lowercased() == ownerID.lowercased(), checkpoint.workoutID == workoutID,
              checkpoint.prescription == prescription, (0...stageCount).contains(checkpoint.stageIndex),
              checkpoint.remainingSeconds >= 0,
              checkpoint.weights.values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        return checkpoint
    }

    static func remove(ownerID: String, workoutID: UUID) {
        guard let url = url(ownerID: ownerID, workoutID: workoutID) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
