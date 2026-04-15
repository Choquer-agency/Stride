import Foundation

enum PaceUnit: String, Codable, CaseIterable {
    case km = "km"
    case miles = "miles"

    var label: String {
        switch self {
        case .km: return "per kilometer"
        case .miles: return "per mile"
        }
    }

    var shortLabel: String {
        switch self {
        case .km: return "/km"
        case .miles: return "/mi"
        }
    }

    /// Conversion factor from sec/km to sec/unit
    var conversionFactor: Double {
        switch self {
        case .km: return 1.0
        case .miles: return 1.60934  // 1 mile = 1.60934 km
        }
    }
}

struct VoiceCoachSettings: Codable {
    var isEnabled: Bool = true
    var announceKmSplits: Bool = true
    var announcePaceZone: Bool = true
    var announceHalfway: Bool = true
    var speakPausedResumed: Bool = true
    var paceUnit: PaceUnit = .km
    var announceCountdown: Bool = true
    var announceWorkoutPreview: Bool = true
    var announceEncouragement: Bool = true
    var announcePostRunSummary: Bool = true
    var announceRecords: Bool = true

    // MARK: - UserDefaults Persistence

    private static let key = "VoiceCoachSettings"

    static func load() -> VoiceCoachSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(VoiceCoachSettings.self, from: data) else {
            return VoiceCoachSettings()
        }
        return settings
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
