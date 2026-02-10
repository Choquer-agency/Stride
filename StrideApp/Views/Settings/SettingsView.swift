import SwiftUI

struct SettingsView: View {
    @AppStorage("hapticFeedback") private var hapticFeedback = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @EnvironmentObject private var bluetoothManager: BluetoothManager

    /// Timer that auto-stops scanning after 10 seconds
    @State private var scanTimer: Timer?

    var body: some View {
        List {
                // Treadmill Section
                Section {
                    // Row 1: Connection status
                    HStack {
                        Label("Assault Runner", systemImage: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(Color.primary, Color.stridePrimary)
                        Spacer()
                        Circle()
                            .fill(connectionIndicatorColor)
                            .frame(width: 8, height: 8)
                        Text(bluetoothManager.connectionState)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }

                    // Row 2: Scan / Disconnect button
                    if bluetoothManager.connectedDevice != nil {
                        Button {
                            bluetoothManager.disconnect()
                        } label: {
                            Label("Disconnect", systemImage: "xmark.circle")
                                .foregroundStyle(.red, .red)
                        }
                    } else if bluetoothManager.isScanning {
                        Button {
                            stopScanningCleanup()
                        } label: {
                            HStack {
                                Label("Stop Scanning", systemImage: "stop.circle")
                                    .foregroundStyle(Color.primary, Color.stridePrimary)
                                Spacer()
                                ProgressView()
                                    .tint(Color.stridePrimary)
                            }
                        }
                    } else {
                        Button {
                            startScanningWithTimeout()
                        } label: {
                            Label("Scan for Treadmill", systemImage: "dot.radiowaves.left.and.right")
                                .foregroundStyle(Color.primary, Color.stridePrimary)
                        }
                    }

                    // Rows 3+: Discovered devices (only while scanning)
                    if bluetoothManager.isScanning || !bluetoothManager.discoveredDevices.isEmpty {
                        ForEach(bluetoothManager.discoveredDevices) { device in
                            Button {
                                stopScanningCleanup()
                                bluetoothManager.connect(to: device)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(device.name)
                                            .foregroundStyle(Color.primary)
                                        Text("RSSI: \(device.rssi) dBm")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: rssiIcon(for: device.rssi))
                                        .foregroundStyle(Color.stridePrimary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Treadmill")
                }

                // Training History Section
                Section {
                    NavigationLink {
                        ArchivedPlansView()
                    } label: {
                        Label("Previous Plans", systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(Color.primary, Color.stridePrimary)
                    }
                } header: {
                    Text("Training History")
                }

                // Profile Section
                Section {
                    NavigationLink {
                        SyncSettingsView()
                    } label: {
                        Label("iCloud Sync", systemImage: "icloud")
                            .foregroundStyle(Color.primary, Color.stridePrimary)
                    }
                } header: {
                    Text("Account")
                }
                
                // Preferences Section
                Section {
                    Toggle(isOn: $hapticFeedback) {
                        Label("Haptic Feedback", systemImage: "hand.tap")
                            .foregroundStyle(Color.primary, Color.stridePrimary)
                    }
                    .tint(Color.stridePrimary)
                    
                    Toggle(isOn: $notificationsEnabled) {
                        Label("Workout Reminders", systemImage: "bell")
                            .foregroundStyle(Color.primary, Color.stridePrimary)
                    }
                    .tint(Color.stridePrimary)
                } header: {
                    Text("Preferences")
                }
                
                // Units Section
                Section {
                    HStack {
                        Label("Distance", systemImage: "ruler")
                            .foregroundStyle(Color.primary, Color.stridePrimary)
                        Spacer()
                        Text("Kilometers")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Label("Pace", systemImage: "speedometer")
                            .foregroundStyle(Color.primary, Color.stridePrimary)
                        Spacer()
                        Text("min/km")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Units")
                }
                
                // About Section
                Section {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                            .foregroundStyle(Color.primary, Color.stridePrimary)
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://stride.app/privacy")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                            .foregroundStyle(Color.primary, Color.stridePrimary)
                    }
                    
                    Link(destination: URL(string: "https://stride.app/terms")!) {
                        Label("Terms of Service", systemImage: "doc.text")
                            .foregroundStyle(Color.primary, Color.stridePrimary)
                    }
                } header: {
                    Text("About")
                }
                
                // Support Section
                Section {
                    Link(destination: URL(string: "mailto:support@stride.app")!) {
                        Label("Contact Support", systemImage: "envelope")
                            .foregroundStyle(Color.primary, Color.stridePrimary)
                    }
                    
                    Link(destination: URL(string: "https://stride.app/faq")!) {
                        Label("FAQ", systemImage: "questionmark.circle")
                            .foregroundStyle(Color.primary, Color.stridePrimary)
                    }
                } header: {
                    Text("Support")
                }

                // TEMP: DELETE THIS SECTION after correcting the run data.
                Section {
                    NavigationLink {
                        TempWorkoutEditView()
                    } label: {
                        Label("Edit Run Data", systemImage: "pencil.circle")
                            .foregroundStyle(.red, .red)
                    }
                } header: {
                    Text("Debug (Temporary)")
                }
                // END TEMP
            }
            .tint(Color.stridePrimary)
            .contentMargins(.bottom, 16, for: .scrollContent)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .onDisappear {
                stopScanningCleanup()
            }
    }

    // MARK: - Helpers

    /// Color for the connection indicator dot
    private var connectionIndicatorColor: Color {
        switch bluetoothManager.connectionState {
        case "Connected", "Connected (FTMS)":
            return .green
        case "Connecting...", "Scanning...":
            return .orange
        default:
            return .red
        }
    }

    /// Start BLE scanning and auto-stop after 10 seconds
    private func startScanningWithTimeout() {
        bluetoothManager.startScanning()
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { _ in
            if bluetoothManager.isScanning {
                bluetoothManager.stopScanning()
            }
        }
    }

    /// Stop scanning and invalidate the auto-stop timer
    private func stopScanningCleanup() {
        scanTimer?.invalidate()
        scanTimer = nil
        bluetoothManager.stopScanning()
    }

    /// Map RSSI value to a signal-strength SF Symbol
    private func rssiIcon(for rssi: Int) -> String {
        switch rssi {
        case -50...0:
            return "wifi" // excellent
        case -70..<(-50):
            return "wifi" // good
        case -85..<(-70):
            return "wifi.exclamationmark" // fair
        default:
            return "wifi.slash" // poor
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(BluetoothManager())
    }
}
