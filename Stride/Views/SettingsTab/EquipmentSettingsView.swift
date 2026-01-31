import SwiftUI

/// Equipment selection view for gym workouts
struct EquipmentSettingsView: View {
    @ObservedObject var storageManager: StorageManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var userProfile: UserTrainingProfile
    @State private var showSaveAlert = false
    
    init(storageManager: StorageManager) {
        self.storageManager = storageManager
        _userProfile = State(initialValue: storageManager.loadUserProfile())
    }
    
    var body: some View {
        List {
            // Bodyweight section
            Section {
                equipmentToggle(.none)
            } header: {
                Text("Bodyweight")
            } footer: {
                Text("No equipment needed - exercises using only your body weight")
            }
            
            // Basic Weights
            Section {
                equipmentToggle(.dumbbells)
                equipmentToggle(.kettlebell)
                equipmentToggle(.medicineBall)
                equipmentToggle(.wallBall)
                equipmentToggle(.weightPlates)
            } header: {
                Text("Basic Weights")
            } footer: {
                Text("Portable equipment suitable for home gyms")
            }
            
            // Barbell & Racks
            Section {
                equipmentToggle(.barbell)
                equipmentToggle(.squatRack)
                equipmentToggle(.smithMachine)
                equipmentToggle(.bench)
            } header: {
                Text("Barbell & Racks")
            } footer: {
                Text("Heavy lifting equipment typically found in commercial gyms")
            }
            
            // Functional Training
            Section {
                equipmentToggle(.resistanceBands)
                equipmentToggle(.trxBands)
                equipmentToggle(.suspensionTrainer)
                equipmentToggle(.stabilityBall)
                equipmentToggle(.foamRoller)
                equipmentToggle(.yogaMat)
            } header: {
                Text("Functional Training")
            } footer: {
                Text("Portable equipment for functional movement and recovery")
            }
            
            // Plyometric Equipment
            Section {
                equipmentToggle(.plyoBox)
                equipmentToggle(.jumpRope)
                equipmentToggle(.agilityCone)
                equipmentToggle(.sled)
            } header: {
                Text("Plyometric Equipment")
            } footer: {
                Text("Equipment for explosive power and speed training")
            }
            
            // Cable & Machines
            Section {
                equipmentToggle(.cableMachine)
                equipmentToggle(.legPressMachine)
                equipmentToggle(.hamstringCurlMachine)
                equipmentToggle(.legExtensionMachine)
                equipmentToggle(.rowingMachine)
            } header: {
                Text("Cable & Machines")
            } footer: {
                Text("Specialized gym machines for targeted muscle groups")
            }
            
            // Advanced Equipment
            Section {
                equipmentToggle(.pullUpBar)
                equipmentToggle(.dipStation)
                equipmentToggle(.ghdMachine)
                equipmentToggle(.landmineAttachment)
            } header: {
                Text("Advanced Equipment")
            } footer: {
                Text("Specialized equipment for advanced training")
            }
            
            // Summary
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Available Equipment")
                        .font(.headline)
                    
                    if userProfile.availableEquipment.isEmpty {
                        Text("No equipment selected")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text(userProfile.equipmentSummary)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Available Equipment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    saveProfile()
                }
                .fontWeight(.semibold)
            }
        }
        .alert("Settings Saved", isPresented: $showSaveAlert) {
            Button("OK", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("Your equipment preferences have been saved. Training plans will be adjusted accordingly.")
        }
    }
    
    // MARK: - Equipment Toggle
    
    private func equipmentToggle(_ equipment: GymEquipment) -> some View {
        Toggle(isOn: Binding(
            get: { userProfile.availableEquipment.contains(equipment) },
            set: { isOn in
                if isOn {
                    userProfile.availableEquipment.insert(equipment)
                } else {
                    userProfile.availableEquipment.remove(equipment)
                }
            }
        )) {
            HStack(spacing: 12) {
                Image(systemName: equipment.icon)
                    .foregroundColor(.green)
                    .frame(width: 24)
                
                Text(equipment.displayName)
                    .font(.body)
            }
        }
    }
    
    // MARK: - Actions
    
    private func saveProfile() {
        do {
            try storageManager.saveUserProfile(userProfile)
            showSaveAlert = true
        } catch {
            print("Error saving user profile: \(error)")
        }
    }
}

#Preview {
    NavigationStack {
        EquipmentSettingsView(storageManager: StorageManager())
    }
}
