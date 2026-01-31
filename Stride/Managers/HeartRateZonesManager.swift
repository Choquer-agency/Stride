import Foundation
import Combine

/// Represents a single heart rate zone with its range and label
struct HeartRateZone: Codable {
    let number: Int
    let label: String
    let lowerBPM: Int
    let upperBPM: Int
    
    var displayRange: String {
        return "\(lowerBPM)-\(upperBPM) bpm"
    }
    
    var displayName: String {
        return "Z\(number) - \(label)"
    }
}

/// Method for calculating heart rate zones
enum ZoneCalculationMethod: String, Codable, CaseIterable {
    case ageBased = "age_based"
    case hrr = "hrr"
    
    var displayName: String {
        switch self {
        case .ageBased:
            return "Age-based"
        case .hrr:
            return "HRR (Karvonen)"
        }
    }
}

/// Manages heart rate zone calculations and user preferences
class HeartRateZonesManager: ObservableObject {
    // MARK: - Published Properties
    @Published var calculationMethod: ZoneCalculationMethod = .ageBased
    @Published var age: Int = 30
    @Published var restingHR: Int = 60
    @Published var maxHR: Int = 190
    @Published var zones: [HeartRateZone] = []
    
    // MARK: - UserDefaults Keys
    private let methodKey = "hr_zone_calculation_method"
    private let ageKey = "hr_zone_age"
    private let restingHRKey = "hr_zone_resting_hr"
    private let maxHRKey = "hr_zone_max_hr"
    
    // MARK: - Initialization
    init() {
        loadPreferences()
        calculateZones()
    }
    
    // MARK: - Public Methods
    
    /// Get the current zone for a given BPM
    /// Returns nil if zones haven't been calculated or BPM is invalid
    func getCurrentZone(bpm: Int?) -> (zoneNumber: Int, zoneLabel: String, zoneBPMRange: String)? {
        guard let bpm = bpm, bpm > 0, !zones.isEmpty else {
            return nil
        }
        
        // Find which zone this BPM falls into
        for zone in zones {
            if bpm >= zone.lowerBPM && bpm <= zone.upperBPM {
                return (zoneNumber: zone.number, zoneLabel: zone.label, zoneBPMRange: zone.displayRange)
            }
        }
        
        // If BPM is above all zones, return Z5
        if bpm > zones.last!.upperBPM {
            let z5 = zones.last!
            return (zoneNumber: z5.number, zoneLabel: z5.label, zoneBPMRange: z5.displayRange)
        }
        
        // If BPM is below all zones, return Z1
        if bpm < zones.first!.lowerBPM {
            let z1 = zones.first!
            return (zoneNumber: z1.number, zoneLabel: z1.label, zoneBPMRange: z1.displayRange)
        }
        
        return nil
    }
    
    /// Update calculation method and recalculate zones
    func setCalculationMethod(_ method: ZoneCalculationMethod) {
        calculationMethod = method
        savePreferences()
        calculateZones()
    }
    
    /// Update age and recalculate zones (for age-based method)
    func setAge(_ newAge: Int) {
        age = max(10, min(100, newAge)) // Clamp between 10-100
        savePreferences()
        calculateZones()
    }
    
    /// Update resting HR and recalculate zones (for HRR method)
    func setRestingHR(_ hr: Int) {
        restingHR = max(30, min(100, hr)) // Clamp between 30-100
        savePreferences()
        calculateZones()
    }
    
    /// Update max HR and recalculate zones
    func setMaxHR(_ hr: Int) {
        maxHR = max(100, min(220, hr)) // Clamp between 100-220
        savePreferences()
        calculateZones()
    }
    
    // MARK: - Private Methods
    
    /// Calculate zones based on current method and parameters
    private func calculateZones() {
        switch calculationMethod {
        case .ageBased:
            calculateAgeBasedZones()
        case .hrr:
            calculateHRRZones()
        }
    }
    
    /// Calculate zones using age-based (220 - age) method
    private func calculateAgeBasedZones() {
        let estimatedMaxHR = 220 - age
        
        zones = [
            HeartRateZone(
                number: 1,
                label: "Recovery",
                lowerBPM: Int(Double(estimatedMaxHR) * 0.50),
                upperBPM: Int(Double(estimatedMaxHR) * 0.60)
            ),
            HeartRateZone(
                number: 2,
                label: "Aerobic",
                lowerBPM: Int(Double(estimatedMaxHR) * 0.60),
                upperBPM: Int(Double(estimatedMaxHR) * 0.70)
            ),
            HeartRateZone(
                number: 3,
                label: "Tempo",
                lowerBPM: Int(Double(estimatedMaxHR) * 0.70),
                upperBPM: Int(Double(estimatedMaxHR) * 0.80)
            ),
            HeartRateZone(
                number: 4,
                label: "Threshold",
                lowerBPM: Int(Double(estimatedMaxHR) * 0.80),
                upperBPM: Int(Double(estimatedMaxHR) * 0.90)
            ),
            HeartRateZone(
                number: 5,
                label: "Max",
                lowerBPM: Int(Double(estimatedMaxHR) * 0.90),
                upperBPM: Int(Double(estimatedMaxHR) * 1.00)
            )
        ]
    }
    
    /// Calculate zones using Heart Rate Reserve (Karvonen) method
    private func calculateHRRZones() {
        let hrr = Double(maxHR - restingHR)
        
        zones = [
            HeartRateZone(
                number: 1,
                label: "Recovery",
                lowerBPM: Int(hrr * 0.50) + restingHR,
                upperBPM: Int(hrr * 0.59) + restingHR
            ),
            HeartRateZone(
                number: 2,
                label: "Aerobic",
                lowerBPM: Int(hrr * 0.60) + restingHR,
                upperBPM: Int(hrr * 0.69) + restingHR
            ),
            HeartRateZone(
                number: 3,
                label: "Tempo",
                lowerBPM: Int(hrr * 0.70) + restingHR,
                upperBPM: Int(hrr * 0.79) + restingHR
            ),
            HeartRateZone(
                number: 4,
                label: "Threshold",
                lowerBPM: Int(hrr * 0.80) + restingHR,
                upperBPM: Int(hrr * 0.89) + restingHR
            ),
            HeartRateZone(
                number: 5,
                label: "Max",
                lowerBPM: Int(hrr * 0.90) + restingHR,
                upperBPM: Int(hrr * 1.00) + restingHR
            )
        ]
    }
    
    /// Load preferences from UserDefaults
    private func loadPreferences() {
        let defaults = UserDefaults.standard
        
        if let methodString = defaults.string(forKey: methodKey),
           let method = ZoneCalculationMethod(rawValue: methodString) {
            calculationMethod = method
        }
        
        let savedAge = defaults.integer(forKey: ageKey)
        if savedAge > 0 {
            age = savedAge
        }
        
        let savedRestingHR = defaults.integer(forKey: restingHRKey)
        if savedRestingHR > 0 {
            restingHR = savedRestingHR
        }
        
        let savedMaxHR = defaults.integer(forKey: maxHRKey)
        if savedMaxHR > 0 {
            maxHR = savedMaxHR
        }
    }
    
    /// Save preferences to UserDefaults
    private func savePreferences() {
        let defaults = UserDefaults.standard
        defaults.set(calculationMethod.rawValue, forKey: methodKey)
        defaults.set(age, forKey: ageKey)
        defaults.set(restingHR, forKey: restingHRKey)
        defaults.set(maxHR, forKey: maxHRKey)
    }
}



