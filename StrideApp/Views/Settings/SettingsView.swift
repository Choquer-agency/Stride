import SwiftUI

/// Renders all settings sections without a List wrapper.
/// Designed to be composed inside ProfileView's List.
struct SettingsSectionsView: View {
    @AppStorage("hapticFeedback") private var hapticFeedback = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @EnvironmentObject private var bluetoothManager: BluetoothManager
    @EnvironmentObject private var authService: AuthService

    @State private var scanTimer: Timer?
    @State private var leaderboardOptIn: Bool = false
    @State private var displayName: String = ""
    @State private var didLoadCommunityFields = false

    var body: some View {
        // Community Section
        Section {
            Toggle(isOn: $leaderboardOptIn) {
                Label("Join Leaderboards", systemImage: "trophy")
                    .foregroundStyle(Color.primary, Color.stridePrimary)
            }
            .tint(Color.stridePrimary)
            .onChange(of: leaderboardOptIn) { _, newValue in
                guard didLoadCommunityFields else { return }
                saveCommunityField { $0.leaderboardOptIn = newValue }
            }

            HStack {
                Label("Display Name", systemImage: "person.text.rectangle")
                    .foregroundStyle(Color.primary, Color.stridePrimary)
                Spacer()
                TextField("Runner123", text: $displayName)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 150)
                    .onSubmit {
                        let trimmed = displayName.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        saveCommunityField { $0.displayName = trimmed }
                    }
            }
        } header: {
            Text("Community")
        } footer: {
            Text("Your display name and profile photo are visible on leaderboards when opted in.")
        }
        .onAppear { loadCommunityFields() }

        // Treadmill Section
        Section {
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

        // Gear Section
        Section {
            NavigationLink {
                ShoesView()
            } label: {
                Label("Shoes", systemImage: "shoe.2")
                    .foregroundStyle(Color.primary, Color.stridePrimary)
            }
        } header: {
            Text("Gear")
        }

        // Account Section
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

    // MARK: - Community Helpers

    private func loadCommunityFields() {
        if let user = currentUser {
            leaderboardOptIn = user.leaderboardOptIn
            displayName = user.displayName ?? ""
        }
        didLoadCommunityFields = true
    }

    private var currentUser: UserResponse? {
        switch authService.authState {
        case .signedIn(let user): return user
        case .needsProfile(let user): return user
        default: return nil
        }
    }

    private func saveCommunityField(_ update: (inout ProfileUpdateRequest) -> Void) {
        var request = ProfileUpdateRequest()
        update(&request)
        Task {
            _ = try? await authService.updateProfile(request)
        }
    }

    // MARK: - Helpers

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

    private func startScanningWithTimeout() {
        bluetoothManager.startScanning()
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { _ in
            if bluetoothManager.isScanning {
                bluetoothManager.stopScanning()
            }
        }
    }

    private func stopScanningCleanup() {
        scanTimer?.invalidate()
        scanTimer = nil
        bluetoothManager.stopScanning()
    }

    private func rssiIcon(for rssi: Int) -> String {
        switch rssi {
        case -50...0:
            return "wifi"
        case -70..<(-50):
            return "wifi"
        case -85..<(-70):
            return "wifi.exclamationmark"
        default:
            return "wifi.slash"
        }
    }
}

#Preview {
    NavigationStack {
        List {
            SettingsSectionsView()
        }
        .navigationTitle("Settings")
    }
    .environmentObject(BluetoothManager())
}
