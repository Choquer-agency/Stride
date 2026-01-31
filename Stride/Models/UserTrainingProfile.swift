import Foundation

/// User's training environment and stable profile data
/// Separate from TrainingPreferences which may vary by goal/plan
struct UserTrainingProfile: Codable {
    var availableEquipment: Set<GymEquipment>
    
    // Future expansion:
    // var injuryHistory: [InjuryArea]?
    // var experienceLevel: ExperienceLevel?
    // var mobilityLimitations: [String]?
    
    // MARK: - Initializer
    
    init(availableEquipment: Set<GymEquipment> = [.none, .dumbbells, .resistanceBands]) {
        // Always ensure .none is included for bodyweight fallback
        var equipment = availableEquipment
        equipment.insert(.none)
        self.availableEquipment = equipment
    }
    
    // MARK: - Defaults
    
    static var `default`: UserTrainingProfile {
        return UserTrainingProfile(
            availableEquipment: [.none, .dumbbells, .resistanceBands, .weightPlates]
        )
    }
    
    // MARK: - Equipment Categories
    
    /// Bodyweight exercises (no equipment)
    var hasBodyweightOnly: Bool {
        return availableEquipment.contains(.none)
    }
    
    /// Has basic weights (dumbbells, kettlebells, bands)
    var hasBasicWeights: Bool {
        return availableEquipment.intersection([.dumbbells, .kettlebell, .resistanceBands]).count > 0
    }
    
    /// Has advanced equipment (barbell, rack, machines)
    var hasAdvancedEquipment: Bool {
        return availableEquipment.intersection([.barbell, .squatRack, .cableMachine]).count > 0
    }
    
    /// Summary description of available equipment
    var equipmentSummary: String {
        if availableEquipment.isEmpty || (availableEquipment.count == 1 && availableEquipment.contains(.none)) {
            return "Bodyweight only"
        }
        
        let equipmentNames = availableEquipment
            .filter { $0 != .none }
            .sorted { $0.displayName < $1.displayName }
            .map { $0.displayName }
        
        if equipmentNames.isEmpty {
            return "Bodyweight only"
        } else if equipmentNames.count <= 2 {
            return equipmentNames.joined(separator: ", ")
        } else {
            return "\(equipmentNames.count) types"
        }
    }
}
