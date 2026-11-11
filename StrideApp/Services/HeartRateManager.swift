import Foundation
import CoreBluetooth
import os.log

private let hrLog = Logger(subsystem: "com.stride.app", category: "HeartRate")

// Standard Bluetooth SIG Heart Rate Profile identifiers
private let heartRateServiceUUID = CBUUID(string: "180D")
private let heartRateMeasurementUUID = CBUUID(string: "2A37")

/// A Bluetooth choice belongs to one Stride account; discovery never grants consent.
struct HeartRateDeviceSelection {
    let accountID: String
    let defaults: UserDefaults
    private var key: String { "heartRateMonitor.\(accountID)" }
    var deviceID: UUID? { defaults.string(forKey: key).flatMap(UUID.init(uuidString:)) }
    var name: String? { defaults.string(forKey: key + ".name") }
    func allows(_ id: UUID, accountID: String?) -> Bool {
        accountID == self.accountID && deviceID == id
    }
    func save(id: UUID, name: String) {
        defaults.set(id.uuidString, forKey: key)
        defaults.set(name, forKey: key + ".name")
    }
    func forget() {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: key + ".name")
    }
}

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

    struct DiscoveredDevice: Identifiable {
        let id: UUID
        let name: String
    }
    @Published private(set) var discoveredDevices: [DiscoveredDevice] = []
    @Published private(set) var selectedDeviceName: String?
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var selection: HeartRateDeviceSelection?

    func accountDidChange() {
        guard selection?.accountID != AuthService.shared.currentUserID else { return }
        owners.removeAll()
        stopAndDisconnect(owner: "app")
        samples = []
        discoveredDevices = []
        discoveredPeripherals = [:]
        deviceName = nil
        selection = AuthService.shared.currentUserID.map {
            HeartRateDeviceSelection(accountID: $0, defaults: .standard)
        }
        selectedDeviceName = selection?.name
    }

    func selectDevice(id: UUID) {
        accountDidChange()
        guard let selection, let device = discoveredPeripherals[id] else { return }
        selection.save(id: id, name: device.name ?? "Heart rate monitor")
        selectedDeviceName = selection.name
        samples = []
        samplingStart = Date()
        retryConnection()
        connectIfSelected(device)
    }

    func forgetSelectedDevice() {
        selection?.forget()
        selectedDeviceName = nil
        samples = []
        retryConnection()
    }

    private func connectIfSelected(_ device: CBPeripheral) {
        guard !owners.isEmpty, peripheral == nil,
              selection?.allows(device.identifier, accountID: AuthService.shared.currentUserID) == true,
              let central, central.state == .poweredOn else { return }
        peripheral = device
        connectionStartedAt = Date()
        lastReading = nil
        isScanning = false
        deviceName = device.name
        central.stopScan()
        central.connect(device)
    }

    private(set) var samples: [Sample] = []
    private var samplingStart: Date?

    private var owners = Set<String>()
    private var lastReading: Date?
    private var freshnessTimer: Timer?
    private var connectionStartedAt: Date?

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?

    // Keep at most ~4h of 1Hz samples
    private static let maxSamples = 15_000

    // MARK: - Public control

    /// Begin scanning for a heart-rate broadcaster and start a fresh sample log.
    func startScanning(owner: String = "run") {
        accountDidChange()
        guard selection != nil else { return }
        owners.insert(owner)
        guard freshnessTimer == nil else { return }
        freshnessTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkConnection()
            }
        }
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
    func stopAndDisconnect(owner: String = "run") {
        owners.remove(owner)
        guard owners.isEmpty else { return }
        freshnessTimer?.invalidate()
        freshnessTimer = nil
        lastReading = nil
        connectionStartedAt = nil
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
        guard !owners.isEmpty, peripheral == nil, let central, central.state == .poweredOn else { return }
        guard !central.isScanning else { return }
        isScanning = true
        bluetoothUnavailable = false
        central.scanForPeripherals(withServices: [heartRateServiceUUID])
        hrLog.info("Scanning for BLE heart-rate broadcasters")
    }

    private func checkConnection(now: Date = Date()) {
        guard !owners.isEmpty else { return }
        if let last = lastReading, now.timeIntervalSince(last) > 10 {
            isConnected = false
            currentBPM = nil
        }
        // A connected GATT link is not proof that measurements are arriving.
        // Retry stuck connection, service discovery and notification setup too.
        if let started = lastReading ?? connectionStartedAt,
           now.timeIntervalSince(started) > 20 {
            retryConnection()
        } else if peripheral == nil {
            scanIfPoweredOn()
        }
    }

    private func retryConnection() {
        let previous = peripheral
        peripheral = nil
        connectionStartedAt = nil
        lastReading = nil
        isConnected = false
        currentBPM = nil
        if let previous { central?.cancelPeripheralConnection(previous) }
        scanIfPoweredOn()
    }

    private func record(bpm: Int) {
        guard !owners.isEmpty else { return }
        lastReading = Date()
        isConnected = true
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
                self.currentBPM = nil
                self.isConnected = false
                self.peripheral = nil
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
            guard !self.owners.isEmpty,
                  self.selection?.accountID == AuthService.shared.currentUserID else { return }
            self.discoveredPeripherals[peripheral.identifier] = peripheral
            if !self.discoveredDevices.contains(where: { $0.id == peripheral.identifier }) {
                self.discoveredDevices.append(DiscoveredDevice(
                    id: peripheral.identifier,
                    name: peripheral.name ?? "Heart rate monitor"))
            }
            self.connectIfSelected(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            guard !self.owners.isEmpty, self.peripheral === peripheral, self.selection?.allows(peripheral.identifier, accountID: AuthService.shared.currentUserID) == true else { central.cancelPeripheralConnection(peripheral); return }
            self.isConnected = false
            self.isScanning = false
            peripheral.delegate = self
            peripheral.discoverServices([heartRateServiceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            guard self.peripheral === peripheral else { return }
            self.retryConnection()
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            guard self.peripheral === peripheral else { return }
            self.retryConnection()
        }
    }
}

extension HeartRateManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard self.peripheral === peripheral, !self.owners.isEmpty else { return }
            guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == heartRateServiceUUID }) else {
                self.retryConnection()
                return
            }
            peripheral.discoverCharacteristics([heartRateMeasurementUUID], for: service)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        Task { @MainActor in
            guard self.peripheral === peripheral, !self.owners.isEmpty else { return }
            guard error == nil, let ch = service.characteristics?.first(where: { $0.uuid == heartRateMeasurementUUID }) else {
                self.retryConnection()
                return
            }
            peripheral.setNotifyValue(true, for: ch)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateNotificationStateFor characteristic: CBCharacteristic,
                                error: Error?) {
        Task { @MainActor in
            guard self.peripheral === peripheral,
                  characteristic.uuid == heartRateMeasurementUUID else { return }
            if error != nil || !characteristic.isNotifying { self.retryConnection() }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, characteristic.uuid == heartRateMeasurementUUID,
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
            guard self.peripheral === peripheral,
                  self.selection?.allows(peripheral.identifier, accountID: AuthService.shared.currentUserID) == true else { return }
            self.record(bpm: bpm)
        }
    }
}
