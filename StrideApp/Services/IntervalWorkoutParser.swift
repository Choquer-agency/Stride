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
