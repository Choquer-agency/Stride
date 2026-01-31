import Foundation
import CoreBluetooth

/// Represents a BLE device discovered during scanning
struct DiscoveredDevice: Identifiable {
    let id: UUID
    let peripheral: CBPeripheral
    let name: String
    var rssi: Int
    
    init(peripheral: CBPeripheral, rssi: Int) {
        self.id = peripheral.identifier
        self.peripheral = peripheral
        self.name = peripheral.name ?? "Unknown Device"
        self.rssi = rssi
    }
    
    /// Update RSSI when the same device is rediscovered
    mutating func updateRSSI(_ newRSSI: Int) {
        self.rssi = newRSSI
    }
}

