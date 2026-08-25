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
        guard parts.count == 2,
              let lo = Self.paceSeconds(String(parts[0])),
              let hi = Self.paceSeconds(String(parts[1])) else { return nil }
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
        let text = details.replacingOccurrences(of: "-", with: "–")

        // Main set is the gate: "10 × 1 min at [roughly] 4:45–5:00/km ... with 1 min ... between"
        guard let main = firstMatch(
            in: text,
            pattern: #"(\d+)\s*[×x]\s*(\d+)\s*(min|sec)\s*at\s*(?:roughly\s*)?([\d]+:[\d]+\s*–\s*[\d]+:[\d]+)"#
        ) else { return [] }

        let reps = Int(main[1]) ?? 0
        let workValue = Double(main[2]) ?? 0
        let workSec = main[3] == "min" ? workValue * 60 : workValue
        let workPace = main[4].replacingOccurrences(of: " ", with: "")
        guard reps > 1, workSec > 0 else { return [] }

        // Recovery: "with 1 min easy float between" / "with 90 sec jog"
        var floatSec = 60.0
        if let rec = firstMatch(in: text, pattern: #"with\s*(\d+)\s*(min|sec)\s*(?:easy|float|jog|recovery)"#) {
            let v = Double(rec[1]) ?? 1
            floatSec = rec[2] == "min" ? v * 60 : v
        }

        var segments: [IntervalSegment] = []

        if let wu = firstMatch(in: text, pattern: #"Warm–?up:\s*([\d.]+)\s*km\s*at\s*([\d]+:[\d]+\s*–\s*[\d]+:[\d]+)"#) {
            segments.append(IntervalSegment(
                kind: .warmup, durationSec: nil,
                distanceKm: Double(wu[1]),
                paceText: wu[2].replacingOccurrences(of: " ", with: "")))
        }

        for rep in 1...reps {
            segments.append(IntervalSegment(
                kind: .work(rep: rep, of: reps),
                durationSec: workSec, distanceKm: nil, paceText: workPace))
            if rep < reps {
                segments.append(IntervalSegment(
                    kind: .float(rep: rep, of: reps),
                    durationSec: floatSec, distanceKm: nil, paceText: "easy"))
            }
        }

        if let cd = firstMatch(in: text, pattern: #"Cool–?down:\s*([\d.]+)\s*km\s*at\s*([\d]+:[\d]+\s*–\s*[\d]+:[\d]+)"#) {
            segments.append(IntervalSegment(
                kind: .cooldown, durationSec: nil,
                distanceKm: Double(cd[1]),
                paceText: cd[2].replacingOccurrences(of: " ", with: "")))
        }

        return segments
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
