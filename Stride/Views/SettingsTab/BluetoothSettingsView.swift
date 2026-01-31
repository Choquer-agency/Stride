import SwiftUI

/// Dedicated Bluetooth settings and device scanning screen
struct BluetoothSettingsView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Connection Status Indicator
            connectionStatusBanner
            
            // Device Scanning Section
            DeviceScanView(bluetoothManager: bluetoothManager)
        }
        .navigationTitle("Bluetooth")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var connectionStatusBanner: some View {
        HStack(spacing: 12) {
            // Connection indicator circle
            Circle()
                .fill(bluetoothManager.connectedDevice != nil ? Color.green : Color.red)
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Assault runner")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
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
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
    }
}



