import Foundation

/// Ballpark heart-rate bands per workout type, derived from an estimated max
/// HR of ~187 (age-based). Coarse by design — the point is keeping easy days
/// honestly easy (80/20), not lab precision.
enum HeartRateZones {
    static func band(for type: WorkoutType) -> String? {
        switch type {
        case .recovery: return "120–135"
        case .easyRun: return "130–147"
        case .longRun: return "135–150"
        case .tempoRun: return "147–162"
        case .intervals, .hillRepeats: return "163–172"
        case .fartlek: return "140–165"
        case .race: return "155–175"
        case .drills, .mobility, .rest, .crossTraining, .gym: return nil
        }
    }
}
