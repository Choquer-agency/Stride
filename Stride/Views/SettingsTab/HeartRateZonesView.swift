import SwiftUI

/// Settings view for configuring heart rate zones
struct HeartRateZonesView: View {
    @StateObject private var zonesManager = HeartRateZonesManager()
    @State private var ageInput: String = ""
    @State private var restingHRInput: String = ""
    @State private var maxHRInput: String = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Method Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Calculation method")
                        .font(.system(size: 16, weight: .medium))
                    
                    Picker("Method", selection: $zonesManager.calculationMethod) {
                        ForEach(ZoneCalculationMethod.allCases, id: \.self) { method in
                            Text(method.displayName).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: zonesManager.calculationMethod) { newMethod in
                        zonesManager.setCalculationMethod(newMethod)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                
                // Input Fields
                VStack(spacing: 16) {
                    if zonesManager.calculationMethod == .ageBased {
                        // Age-based inputs
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Age")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            HStack {
                                TextField("Enter age", text: $ageInput)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: ageInput) { newValue in
                                        if let age = Int(newValue), age > 0 {
                                            zonesManager.setAge(age)
                                        }
                                    }
                                
                                Text("years")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            
                            Text("Estimated max HR: \(220 - zonesManager.age) bpm")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        // HRR inputs
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Resting heart rate")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            HStack {
                                TextField("Enter resting HR", text: $restingHRInput)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: restingHRInput) { newValue in
                                        if let hr = Int(newValue), hr > 0 {
                                            zonesManager.setRestingHR(hr)
                                        }
                                    }
                                
                                Text("bpm")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Maximum heart rate")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            HStack {
                                TextField("Enter max HR", text: $maxHRInput)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: maxHRInput) { newValue in
                                        if let hr = Int(newValue), hr > 0 {
                                            zonesManager.setMaxHR(hr)
                                        }
                                    }
                                
                                Text("bpm")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Text("HR Reserve: \(zonesManager.maxHR - zonesManager.restingHR) bpm")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                
                // Divider
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 1)
                    .padding(.horizontal, 24)
                
                // Zones Display
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your heart rate zones")
                        .font(.system(size: 16, weight: .medium))
                        .padding(.horizontal, 24)
                    
                    if zonesManager.zones.isEmpty {
                        Text("Enter your details to calculate zones")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 20)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(zonesManager.zones, id: \.number) { zone in
                                ZoneRowView(zone: zone)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
                
                // Info section
                VStack(alignment: .leading, spacing: 8) {
                    Text("About zones")
                        .font(.system(size: 14, weight: .medium))
                    
                    Text("Training in different heart rate zones helps optimize your workouts for specific goals like endurance, speed, or recovery.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Heart rate zones")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Initialize input fields with current values
            ageInput = String(zonesManager.age)
            restingHRInput = String(zonesManager.restingHR)
            maxHRInput = String(zonesManager.maxHR)
        }
    }
}

/// Individual zone row display
struct ZoneRowView: View {
    let zone: HeartRateZone
    
    private var zoneColor: Color {
        switch zone.number {
        case 1: return .blue
        case 2: return .green
        case 3: return .yellow
        case 4: return .orange
        case 5: return .red
        default: return .gray
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Zone indicator
            Circle()
                .fill(zoneColor)
                .frame(width: 12, height: 12)
            
            // Zone name
            Text(zone.displayName)
                .font(.system(size: 16, weight: .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // BPM range
            Text(zone.displayRange)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 12)
        .background(
            zone.number <= 2 ? zoneColor.opacity(0.08) : Color.clear
        )
    }
}



