import Foundation
import CoreBluetooth
import os.log

private let hrLog = Logger(subsystem: "com.stride.app", category: "HeartRate")

// Standard Bluetooth SIG Heart Rate Profile identifiers
private let heartRateServiceUUID = CBUUID(string: "180D")
private let heartRateMeasurementUUID = CBUUID(string: "2A37")

/// Live heart-rate over Bluetooth LE using the standard Heart Rate Profile
/// (service 0x180D / measurement characteristic 0x2A37).
///
/// Works with any broadcaster: Fitbit/Pixel watches with "Broadcast heart rate"
/// enabled during an exercise, chest straps, etc. The cloud (Google Health API)
/// path is minutes-to-hours behind; this is the only true-live source mid-run.
///
/// Usage: `startScanning()` when a run begins, observe `currentBPM`,
/// `stopAndDisconnect()` when the run ends. Samples accumulate in `samples`
/// (capped) for post-run logging.
@MainActor
final class HeartRateManager: NSObject, ObservableObject {
    static let shared = HeartRateManager()

    struct Sample: Codable {
        let t: TimeInterval   // seconds since sampling started
        let bpm: Int
    }

    @Published private(set) var currentBPM: Int?
    @Published private(set) var isConnected = false
    @Published private(set) var deviceName: String?
    @Published private(set) var isScanning = false
    @Published private(set) var bluetoothUnavailable = false

    private(set) var samples: [Sample] = []
    private var samplingStart: Date?

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?

    // Keep at most ~4h of 1Hz samples
    private static let maxSamples = 15_000

    // MARK: - Public control

    /// Begin scanning for a heart-rate broadcaster and start a fresh sample log.
    func startScanning() {
        samples = []
        samplingStart = Date()
        currentBPM = nil
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil)
        } else {
            scanIfPoweredOn()
        }
    }

    /// Stop scanning/disconnect but keep the recorded samples for the caller.
    func stopAndDisconnect() {
        isScanning = false
        central?.stopScan()
        if let peripheral {
            central?.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil
        isConnected = false
        currentBPM = nil
    }

    /// Samples encoded as JSON for persistence, nil if nothing was recorded.
    func samplesJSON() -> String? {
        guard !samples.isEmpty else { return nil }
        guard let data = try? JSONEncoder().encode(samples) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    var averageBPM: Int? {
        guard !samples.isEmpty else { return nil }
        return samples.map(\.bpm).reduce(0, +) / samples.count
    }

    var maxBPM: Int? {
        samples.map(\.bpm).max()
    }

    // MARK: - Internals

    private func scanIfPoweredOn() {
        guard let central, central.state == .poweredOn else { return }
        isScanning = true
        bluetoothUnavailable = false
        central.scanForPeripherals(withServices: [heartRateServiceUUID])
        hrLog.info("Scanning for BLE heart-rate broadcasters")
    }

    private func record(bpm: Int) {
        currentBPM = bpm
        guard let samplingStart, samples.count < Self.maxSamples else { return }
        samples.append(Sample(t: Date().timeIntervalSince(samplingStart), bpm: bpm))
    }
}

extension HeartRateManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                self.scanIfPoweredOn()
            case .unauthorized, .unsupported, .poweredOff:
                self.bluetoothUnavailable = true
                self.isScanning = false
            default:
                break
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            guard self.peripheral == nil else { return }
            self.peripheral = peripheral
            self.deviceName = peripheral.name
            central.stopScan()
            central.connect(peripheral)
            hrLog.info("Connecting to HR broadcaster: \(peripheral.name ?? "unknown")")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.isConnected = true
            self.isScanning = false
            peripheral.delegate = self
            peripheral.discoverServices([heartRateServiceUUID])
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            self.isConnected = false
            self.currentBPM = nil
            self.peripheral = nil
            // Watch broadcasts stop between exercises — quietly rescan so we
            // reattach if the broadcast comes back mid-run.
            self.scanIfPoweredOn()
        }
    }
}

extension HeartRateManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == heartRateServiceUUID }) else { return }
        peripheral.discoverCharacteristics([heartRateMeasurementUUID], for: service)
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard let ch = service.characteristics?.first(where: { $0.uuid == heartRateMeasurementUUID }) else { return }
        peripheral.setNotifyValue(true, for: ch)
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == heartRateMeasurementUUID,
              let data = characteristic.value, data.count >= 2 else { return }
        // Standard HR Measurement: flag bit 0 selects UInt8 vs UInt16 value
        let bpm: Int
        if data[0] & 0x01 == 0 {
            bpm = Int(data[1])
        } else {
            guard data.count >= 3 else { return }
            bpm = Int(UInt16(data[1]) | (UInt16(data[2]) << 8))
        }
        guard bpm > 0 else { return }
        Task { @MainActor in
            self.record(bpm: bpm)
        }
    }
}
