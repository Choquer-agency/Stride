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
            /// Rep work — Done advances; weight (kg) is adjustable in 5 kg steps
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
    }

    // MARK: - Entry point

    static func stages(fromPrescription source: String) -> [Stage] {
        let items = prescriptionItems(from: source)
        guard !items.isEmpty else { return [] }

        var exercises = items.map(parseExercise)
        var stages: [Stage] = []

        // Warm-up: leading SkiErg item
        if let first = exercises.first, first.isSkiErg {
            stages.append(contentsOf: skiErgStages(first, section: "Warm-up"))
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
        guard source.contains(";") else { return [] }
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
                if unit.lowercased().hasPrefix("kg") {
                    weightKg = value
                    weightSuffix = unit.contains("/hand") ? "kg/hand" : "kg"
                } else {
                    weightSuffix = unit.isEmpty ? "" : unit   // "lb" — fixed increments, not adjustable
                    repsText += repsText.isEmpty ? "\(Int(value)) \(unit)" : " @ \(Int(value)) \(unit)"
                }
            }
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
            isSkiErg: name.lowercased().contains("skierg")
        )
    }

    // MARK: - Stage builders

    private static func exerciseStages(_ exercise: ParsedExercise, round: Int, section: String) -> [Stage] {
        let setLabel = exercise.sets > 1 ? "SET \(round) OF \(exercise.sets)" : nil
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
                kind: kind
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
                    if i < rounds {
                        stages.append(Stage(exerciseName: "SkiErg — Easy", sectionLabel: section,
                                            setLabel: "ROUND \(i) OF \(rounds)", sideLabel: nil,
                                            kind: .timed(seconds: rest)))
                    }
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
