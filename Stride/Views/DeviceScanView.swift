import SwiftUI

/// Screen: Manual Bluetooth device scanning (accessed from Settings)
struct DeviceScanView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @State private var searchText = ""
    
    // Preferred device keywords
    private let preferredKeywords = ["ASSAULT", "AIRRUNNER", "RUNNER"]
    
    private var preferredDevices: [DiscoveredDevice] {
        bluetoothManager.discoveredDevices.filter { device in
            let upperName = device.name.uppercased()
            return preferredKeywords.contains(where: { upperName.contains($0) })
        }
    }
    
    private var otherDevices: [DiscoveredDevice] {
        bluetoothManager.discoveredDevices.filter { device in
            let upperName = device.name.uppercased()
            return !preferredKeywords.contains(where: { upperName.contains($0) })
        }
    }
    
    private var filteredPreferred: [DiscoveredDevice] {
        if searchText.isEmpty {
            return preferredDevices
        }
        return preferredDevices.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    private var filteredOther: [DiscoveredDevice] {
        if searchText.isEmpty {
            return otherDevices
        }
        return otherDevices.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Instructions
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("Manual Device Scanning")
                        .font(.headline)
                }
                Text("Use this only if automatic connection fails. For best results, pair your Assault Runner in iPhone Settings > Bluetooth first.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .background(Color(.systemGray6))
            
            // Scan control button
            Button(action: {
                if bluetoothManager.isScanning {
                    bluetoothManager.stopScanning()
                } else {
                    bluetoothManager.startManualScanning()
                }
            }) {
                HStack {
                    Image(systemName: bluetoothManager.isScanning ? "stop.circle" : "antenna.radiowaves.left.and.right")
                    Text(bluetoothManager.isScanning ? "Stop scanning" : "Start manual scan")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(bluetoothManager.isScanning ? Color.red : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding()
            
            // Search bar
            if !bluetoothManager.discoveredDevices.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search devices", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .padding(.horizontal)
            }
            
            // Device list
            if bluetoothManager.discoveredDevices.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: bluetoothManager.isScanning ? "antenna.radiowaves.left.and.right" : "bluetooth")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text(bluetoothManager.isScanning ? "Scanning for FTMS devices..." : "Tap 'Start manual scan' to discover devices")
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .padding()
                Spacer()
            } else {
                List {
                    // Preferred devices section
                    if !filteredPreferred.isEmpty {
                        Section(header: Text("Assault Runners")) {
                            ForEach(filteredPreferred) { device in
                                DeviceRow(device: device, isPreferred: true)
                                    .onTapGesture {
                                        bluetoothManager.connect(to: device)
                                    }
                            }
                        }
                    }
                    
                    // Other devices section
                    if !filteredOther.isEmpty {
                        Section(header: Text("Other FTMS devices")) {
                            ForEach(filteredOther) { device in
                                DeviceRow(device: device, isPreferred: false)
                                    .onTapGesture {
                                        bluetoothManager.connect(to: device)
                                    }
                            }
                        }
                    }
                }
            }
        }
        .onDisappear {
            // Stop scanning when leaving manual scan view
            bluetoothManager.stopScanning()
        }
    }
}

struct DeviceRow: View {
    let device: DiscoveredDevice
    let isPreferred: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(device.name)
                        .font(.headline)
                    if isPreferred {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                }
                Text("RSSI: \(device.rssi) dBm")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

