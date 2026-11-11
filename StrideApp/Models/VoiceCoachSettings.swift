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

enum PaceUpdateFrequency: String, Codable, CaseIterable {
    case `default`, every200m, every500m, every1km

    var label: String {
        switch self {
        case .default: return "Default"
        case .every200m: return "Every 200m"
        case .every500m: return "Every 500m"
        case .every1km: return "Every 1km"
        }
    }

    var distanceMeters: Double? {
        switch self {
        case .default: return nil
        case .every200m: return 200
        case .every500m: return 500
        case .every1km: return 1000
        }
    }

    var explanation: String {
        switch self {
        case .default: return "Default: alerts after 30 seconds of sustained pace change, with a 90-second cooldown for off-target alerts. Returning on target is confirmed after 12 seconds. Splits are controlled separately."
        case .every200m: return "Every 200 meters: hear your current pace and whether you are too fast, too slow, or on target."
        case .every500m: return "Every 500 meters: hear your current pace and whether you are too fast, too slow, or on target."
        case .every1km: return "Every kilometer: hear your current pace and whether you are too fast, too slow, or on target."
        }
    }
}

struct VoiceCoachSettings: Codable {
    var isEnabled: Bool = true
    var announceKmSplits: Bool = true
    var announcePaceZone: Bool = true
    var announceHalfway: Bool = true
    var speakPausedResumed: Bool = true
    var paceUpdateFrequency: PaceUpdateFrequency = .default
    var paceUnit: PaceUnit = .km
    var announceCountdown: Bool = true
    var announceWorkoutPreview: Bool = true
    var announceEncouragement: Bool = true
    var announcePostRunSummary: Bool = true
    var announceRecords: Bool = true
    var announceTerrainCoaching: Bool = true
    var announceFinishPush: Bool = true

    init() {}

    private enum CodingKeys: String, CodingKey {
        case isEnabled, announceKmSplits, announcePaceZone, announceHalfway, speakPausedResumed, paceUpdateFrequency, paceUnit, announceCountdown, announceWorkoutPreview, announceEncouragement, announcePostRunSummary, announceRecords, announceTerrainCoaching, announceFinishPush
    }

    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? isEnabled
        announceKmSplits = try values.decodeIfPresent(Bool.self, forKey: .announceKmSplits) ?? announceKmSplits
        announcePaceZone = try values.decodeIfPresent(Bool.self, forKey: .announcePaceZone) ?? announcePaceZone
        announceHalfway = try values.decodeIfPresent(Bool.self, forKey: .announceHalfway) ?? announceHalfway
        speakPausedResumed = try values.decodeIfPresent(Bool.self, forKey: .speakPausedResumed) ?? speakPausedResumed
        paceUpdateFrequency = try values.decodeIfPresent(PaceUpdateFrequency.self, forKey: .paceUpdateFrequency) ?? paceUpdateFrequency
        paceUnit = try values.decodeIfPresent(PaceUnit.self, forKey: .paceUnit) ?? paceUnit
        announceCountdown = try values.decodeIfPresent(Bool.self, forKey: .announceCountdown) ?? announceCountdown
        announceWorkoutPreview = try values.decodeIfPresent(Bool.self, forKey: .announceWorkoutPreview) ?? announceWorkoutPreview
        announceEncouragement = try values.decodeIfPresent(Bool.self, forKey: .announceEncouragement) ?? announceEncouragement
        announcePostRunSummary = try values.decodeIfPresent(Bool.self, forKey: .announcePostRunSummary) ?? announcePostRunSummary
        announceRecords = try values.decodeIfPresent(Bool.self, forKey: .announceRecords) ?? announceRecords
        announceTerrainCoaching = try values.decodeIfPresent(Bool.self, forKey: .announceTerrainCoaching) ?? announceTerrainCoaching
        announceFinishPush = try values.decodeIfPresent(Bool.self, forKey: .announceFinishPush) ?? announceFinishPush
    }

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
