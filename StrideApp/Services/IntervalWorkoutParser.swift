import Foundation

/// One phase of a structured run (fartlek / intervals / threshold blocks).
struct IntervalSegment: Equatable {
    enum Kind: Equatable {
        case warmup
        case work(rep: Int, of: Int)
        case float(rep: Int, of: Int)
        case cooldown
    }

    let kind: Kind
    let durationSec: Double?    // timed phase (reps, floats)
    let distanceKm: Double?     // distance phase (warm-up, cool-down)
    let paceText: String        // "6:00–6:30", "4:45–5:00", "easy"

    /// Target pace bounds in sec/km when paceText is a M:SS–M:SS range.
    var paceBounds: (min: Double, max: Double)? {
        let parts = paceText.replacingOccurrences(of: "-", with: "–").split(separator: "–")
        guard let first = parts.first, let lo = Self.paceSeconds(String(first)) else { return nil }
        if parts.count == 1 { return (lo - 15, lo + 15) }
        guard parts.count == 2, let hi = Self.paceSeconds(String(parts[1])) else { return nil }
        return (min(lo, hi), max(lo, hi))
    }

    private static func paceSeconds(_ s: String) -> Double? {
        let bits = s.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard bits.count == 2, let m = Double(bits[0]), let sec = Double(bits[1]) else { return nil }
        return m * 60 + sec
    }

    var displayLabel: String {
        switch kind {
        case .warmup: return "WARM-UP"
        case .work(let rep, let of): return "REP \(rep) OF \(of)"
        case .float(let rep, let of): return "FLOAT · REP \(rep) OF \(of)"
        case .cooldown: return "COOL-DOWN"
        }
    }
}

/// Parses coach prose like:
///   Warm-up: 2.5 km at 6:00–6:30/km
///   Main set: 10 × 1 min at roughly 4:45–5:00/km effort (RPE 7) with 1 min easy float between
///   Cool-down: 2.5 km at 6:00–6:30/km
/// into an ordered segment list. Returns [] when the text has no repeat structure
/// (plain runs keep the normal run screen).
enum IntervalWorkoutParser {

    static func parse(_ details: String?) -> [IntervalSegment] {
        guard let details, !details.isEmpty else { return [] }
        let text = details.lowercased()
            .replacingOccurrences(of: "-", with: "–")
            .replacingOccurrences(of: "—", with: "–")
        let amount = #"(\d+(?:\.\d+)?)\s*(minutes?|mins?|seconds?|secs?|km|metres?|meters?|m|s)\b"#
        let pace = #"(\d{1,2}:\d{2}(?:\s*–\s*\d{1,2}:\d{2})?)"#
        let approx = #"\s*(?:at|@)\s*(?:roughly\s*|about\s*|approximately\s*)?"#
        let repeated = firstMatch(in: text, pattern: #"(\d+)\s*[×x]\s*"# + amount + approx + pace)
        // Continuous tempo: "Main set: 6 km continuous at 5:00/km" is one work block.
        let continuous = firstMatch(in: text, pattern:
            #"main set\s*:\s*"# + amount + #"(?:\s*(?:continuous|steady|tempo))?"# + approx + pace)
            .map { [$0[0], "1"] + $0.dropFirst() }
        guard let main = repeated ?? continuous,
              let reps = Int(main[1]), (1...100).contains(reps),
              let work = measurement(main[2], main[3]) else { return [] }

        // Never invent a recovery duration if the prescription cannot be read.
        let recovery = firstMatch(in: text, pattern:
            #"(?:with|/|recovery:|recoveries:)\s*"# + amount + #"\s*(?:easy|float|jog|walk|rest|recovery)[^;\n]*?(?:at\s*"# + pace + #"|(?=between|;|\n|$))"#)
            ?? firstMatch(in: text, pattern: #"(?:with|/|recovery:|recoveries:)\s*"# + amount)
        let rest = recovery.flatMap { measurement($0[1], $0[2]) }
        guard reps == 1 || rest != nil else { return [] }
        let recoveryPace = recovery.flatMap { $0.count > 3 && !$0[3].isEmpty ? $0[3] : nil } ?? "easy"

        func bookend(_ label: String, kind: IntervalSegment.Kind) -> IntervalSegment? {
            guard let match = firstMatch(in: text, pattern:
                label + #"\s*:?\s*"# + amount + #"(?:\s*(?:at|@)\s*"# + pace + #")?"#),
                  let value = measurement(match[1], match[2]) else { return nil }
            return IntervalSegment(kind: kind, durationSec: value.seconds, distanceKm: value.km,
                                   paceText: match[3].isEmpty ? "easy" : match[3])
        }
        let warmup = bookend(#"warm[–\s]?up"#, kind: .warmup)
        let cooldown = bookend(#"cool[–\s]?down"#, kind: .cooldown)
        // An unreadable phase or additional block must not silently disappear.
        if firstMatch(in: text, pattern: #"warm[–\s]?up"#) != nil && warmup == nil { return [] }
        if firstMatch(in: text, pattern: #"cool[–\s]?down"#) != nil && cooldown == nil { return [] }
        let repeats = try? NSRegularExpression(pattern: #"\d+\s*[×x]\s*\d"#)
        if let repeats, repeats.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
            != (repeated == nil ? 0 : 1) { return [] }
        var segments: [IntervalSegment] = []
        if let warmup { segments.append(warmup) }
        for rep in 1...reps {
            segments.append(IntervalSegment(kind: .work(rep: rep, of: reps),
                durationSec: work.seconds, distanceKm: work.km, paceText: main[4]))
            if rep < reps, let rest {
                segments.append(IntervalSegment(kind: .float(rep: rep, of: reps),
                    durationSec: rest.seconds, distanceKm: rest.km, paceText: recoveryPace))
            }
        }
        if let cooldown { segments.append(cooldown) }
        return segments
    }

    /// Distance-based pace changes in continuous runs, without switching to interval UI.
    /// Only accept explicit first/final distances that add up to the planned total.
    static func progression(_ details: String?, totalKm: Double?) -> [IntervalSegment] {
        guard let details, let totalKm, totalKm > 0 else { return [] }
        let text = details.lowercased().replacingOccurrences(of: "-", with: "–")
            .replacingOccurrences(of: "—", with: "–")
        let phase = #"(\d+(?:\.\d+)?)\s*km\s*(?:at|@)\s*(\d{1,2}:\d{2}(?:\s*–\s*\d{1,2}:\d{2})?)"#
        guard let first = firstMatch(in: text, pattern: #"\bfirst\s+"# + phase),
              let final = firstMatch(in: text, pattern: #"\b(?:final|last)\s+"# + phase),
              let firstKm = Double(first[1]), let finalKm = Double(final[1]),
              firstKm > 0, finalKm > 0, abs(firstKm + finalKm - totalKm) < 0.05 else { return [] }
        let phases = [
            IntervalSegment(kind: .work(rep: 1, of: 2), durationSec: nil, distanceKm: firstKm, paceText: first[2]),
            IntervalSegment(kind: .work(rep: 2, of: 2), durationSec: nil, distanceKm: finalKm, paceText: final[2])
        ]
        guard phases.allSatisfy({ $0.paceBounds != nil }) else { return [] }
        return phases
    }

    /// Strides without a numeric pace use the prescribed effort, never an invented speed.
    /// One minute of easy recovery is the displayed default when the plan omits it.
    static func strides(_ details: String?, totalKm: Double?, easyPace: String?) -> [IntervalSegment] {
        guard let details, let totalKm, totalKm > 0,
              let match = firstMatch(in: details.lowercased(), pattern:
                #"(\d+)\s*[×x]\s*(\d+)\s*(?:seconds?|secs?|s)\s+strides"#),
              let reps = Int(match[1]), (1...20).contains(reps),
              let seconds = Double(match[2]), seconds > 0 else { return [] }
        let finalKm = firstMatch(in: details.lowercased(), pattern: #"final\s+(\d+(?:\.\d+)?)\s*km"#)
            .flatMap { Double($0[1]) } ?? min(2, totalKm)
        let recovery = firstMatch(in: details.lowercased(), pattern:
            #"with\s+(\d+)\s*(seconds?|secs?|minutes?|mins?)\s*(?:easy|jog|recovery)"#)
            .flatMap { measurement($0[1], $0[2])?.seconds } ?? 60
        var segments = [IntervalSegment(kind: .warmup, durationSec: nil,
            distanceKm: max(0, totalKm - finalKm), paceText: easyPace ?? "easy")]
        for rep in 1...reps {
            // A visible three-second preparation phase before every stride.
            segments.append(IntervalSegment(kind: .float(rep: rep, of: reps), durationSec: 3,
                distanceKm: nil, paceText: "Get ready for a stride"))
            segments.append(IntervalSegment(kind: .work(rep: rep, of: reps), durationSec: seconds,
                distanceKm: nil, paceText: "Fast, relaxed effort · build smoothly · no sprint"))
            if rep < reps {
                segments.append(IntervalSegment(kind: .float(rep: rep, of: reps), durationSec: recovery,
                    distanceKm: nil, paceText: "easy"))
            }
        }
        return segments
    }

    private static func measurement(_ number: String, _ unit: String) -> (seconds: Double?, km: Double?)? {
        guard let value = Double(number), value > 0 else { return nil }
        if unit == "km" { return (nil, value) }
        if unit == "m" || unit.hasPrefix("met") { return (nil, value / 1000) }
        return (unit.hasPrefix("min") ? value * 60 : value, nil)
    }

    private static func firstMatch(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (0..<match.numberOfRanges).map {
            guard let range = Range(match.range(at: $0), in: text) else { return "" }
            return String(text[range])
        }
    }
}

/// Preview only: proportional bars describe prescribed phases, never measured progress.
enum RunSessionProfile {
    static func levels(details: String?, totalKm: Double?, easyPace: String?, allowSteady: Bool) -> [Double] {
        var phases = IntervalWorkoutParser.parse(details)
        if phases.isEmpty { phases = IntervalWorkoutParser.progression(details, totalKm: totalKm) }
        if phases.isEmpty { phases = IntervalWorkoutParser.strides(details, totalKm: totalKm, easyPace: easyPace) }
        guard !phases.isEmpty else { return allowSteady ? Array(repeating: 0.3, count: 48) : [] }
        let base = phases.compactMap { $0.paceBounds?.max }.max() ?? 390
        // Include every phase, even a 20-second stride in a long easy run.
        // Durations determine remaining width; a minimum bar keeps short reps visible.
        let weights = phases.map { max(1, $0.durationSec ?? (($0.distanceKm ?? 0) * base)) }
        let total = weights.reduce(0, +)
        let count = max(48, phases.count)
        var result: [Double] = []
        for (index, phase) in phases.enumerated() {
            let height: Double
            switch phase.kind {
            case .warmup, .cooldown: height = 0.28
            case .float: height = 0.18
            case .work:
                height = phase.paceBounds.map { min(1, max(0.3, 0.3 + (base - $0.min) / 150)) } ?? 0.95
            }
            let bars = max(1, Int((weights[index] / total * Double(count)).rounded()))
            result.append(contentsOf: repeatElement(height, count: bars))
        }
        return result
    }
}
