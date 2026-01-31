import SwiftUI

/// Settings screen with navigation to different settings sections
struct SettingsView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject var goalManager: GoalManager
    @ObservedObject var workoutManager: WorkoutManager
    @ObservedObject var storageManager: StorageManager
    
    @State private var showDeactivateAlert = false
    
    var body: some View {
        NavigationStack {
            List {
                // Branding Section
                Section {
                    VStack(spacing: 16) {
                        Image("StrideWordmark")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 40)
                        
                        VStack(spacing: 4) {
                            Text("Version 1.0")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("Intelligent Training for Runners")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }
                
                // Goal Section
                Section {
                    if let goal = goalManager.activeGoal {
                        NavigationLink(destination: GoalSetupView(mode: .edit(goal), goalManager: goalManager)) {
                            HStack(spacing: 12) {
                                Image(systemName: "target")
                                    .foregroundColor(.green)
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(goal.displayName)
                                        .font(.body)
                                    
                                    if let targetTime = goal.formattedTargetTime {
                                        Text("\(goal.daysRemaining) days · Target \(targetTime)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("\(goal.daysRemaining) days · Completion goal")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        
                        Button(action: {
                            showDeactivateAlert = true
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "xmark.circle")
                                    .foregroundColor(.red)
                                    .frame(width: 24)
                                
                                Text("Deactivate Goal")
                                    .foregroundColor(.red)
                            }
                        }
                    } else {
                        NavigationLink(destination: GoalSetupView(mode: .create, goalManager: goalManager)) {
                            HStack(spacing: 12) {
                                Image(systemName: "target")
                                    .foregroundColor(.green)
                                    .frame(width: 24)
                                
                                Text("Set Goal")
                                    .font(.body)
                            }
                        }
                    }
                } header: {
                    Text("Goal")
                }
                
                // Bluetooth Section
                Section {
                    NavigationLink(destination: BluetoothSettingsView(bluetoothManager: bluetoothManager)) {
                        HStack(spacing: 12) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Bluetooth")
                                    .font(.body)
                                
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(bluetoothManager.connectedDevice != nil ? Color.green : Color.red)
                                        .frame(width: 8, height: 8)
                                    
                                    if let device = bluetoothManager.connectedDevice {
                                        Text("Connected to \(device.name)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("Not connected")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Device")
                }
                
                // Heart Rate Zones Section
                Section {
                    NavigationLink(destination: AICoachSettingsView()) {
                        HStack(spacing: 12) {
                            Image(systemName: "brain")
                                .foregroundColor(.purple)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AI Coach")
                                    .font(.body)
                                
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(SecureKeyManager.isAPIKeyConfigured ? Color.green : Color.red)
                                        .frame(width: 8, height: 8)
                                    
                                    Text(SecureKeyManager.isAPIKeyConfigured ? "Enabled" : "Disabled")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    
                    NavigationLink(destination: AvailabilitySettingsView(storageManager: storageManager)) {
                        HStack(spacing: 12) {
                            Image(systemName: "calendar.badge.clock")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            
                            Text("Training availability")
                                .font(.body)
                        }
                    }
                    
                    NavigationLink(destination: BaselineSettingsView(
                        baselineManager: BaselineAssessmentManager(
                            storageManager: storageManager,
                            hrZonesManager: HeartRateZonesManager()
                        ),
                        workoutManager: workoutManager
                    )) {
                        HStack(spacing: 12) {
                            Image(systemName: "figure.run.circle")
                                .foregroundColor(.green)
                                .frame(width: 24)
                            
                            Text("Baseline assessment")
                                .font(.body)
                        }
                    }
                    
                    NavigationLink(destination: HeartRateZonesView()) {
                        HStack(spacing: 12) {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red)
                                .frame(width: 24)
                            
                            Text("Heart rate zones")
                                .font(.body)
                        }
                    }
                    
                    NavigationLink(destination: EquipmentSettingsView(storageManager: storageManager)) {
                        HStack(spacing: 12) {
                            Image(systemName: "dumbbell")
                                .foregroundColor(.brown)
                                .frame(width: 24)
                            
                            Text("Available equipment")
                                .font(.body)
                        }
                    }
                } header: {
                    Text("Training")
                }
                
                // Data & Storage Section
                Section {
                    NavigationLink(destination: NeonSettingsView()) {
                        HStack(spacing: 12) {
                            Image(systemName: "cloud.fill")
                                .foregroundColor(.cyan)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Cloud Database")
                                    .font(.body)
                                
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(NeonKeyManager.isConfigured ? Color.green : Color.orange)
                                        .frame(width: 8, height: 8)
                                    
                                    Text(NeonKeyManager.isConfigured ? "Connected" : "Not configured")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Data & Storage")
                }
                
                // Future sections placeholder
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "person.circle")
                            .foregroundColor(.gray)
                            .frame(width: 24)
                        
                        Text("Profile")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 12) {
                        Image(systemName: "envelope")
                            .foregroundColor(.gray)
                            .frame(width: 24)
                        
                        Text("Notifications")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Account")
                } footer: {
                    Text("Additional settings coming soon")
                        .font(.caption)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Deactivate Goal", isPresented: $showDeactivateAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Deactivate", role: .destructive) {
                    Task {
                        do {
                            try await goalManager.deactivateGoal()
                        } catch {
                            print("Error deactivating goal: \(error)")
                        }
                    }
                }
            } message: {
                Text("Your goal will be deactivated but kept in storage. You can set a new goal anytime.")
            }
        }
    }
}


