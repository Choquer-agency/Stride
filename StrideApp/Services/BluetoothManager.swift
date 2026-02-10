import Foundation
import CoreBluetooth
import Combine

class BluetoothManager: NSObject, ObservableObject {
    // MARK: - Published Properties (bind these to your UI)
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var isScanning: Bool = false
    @Published var connectedDevice: DiscoveredDevice?
    @Published var connectionState: String = "Disconnected"
    @Published var isFTMSSupported: Bool = false

    // MARK: - Callback for Parsed Data
    /// Set this closure to receive parsed treadmill samples.
    var onTreadmillData: ((ParsedTreadmillSample) -> Void)?

    // MARK: - Private Properties
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var ftmsCharacteristic: CBCharacteristic?

    // Auto-connect keywords (Assault Runner device names contain these)
    private let preferredKeywords = ["ASSAULT", "AIRRUNNER", "RUNNER"]

    // Reconnection
    private var lastConnectedPeripheral: CBPeripheral?
    private var reconnectionAttempts: Int = 0
    private let maxReconnectionAttempts: Int = 5
    private var reconnectionTimer: Timer?

    // FTMS Service and Characteristic UUIDs
    private let ftmsServiceUUID = CBUUID(string: "1826")
    private let treadmillDataUUID = CBUUID(string: "2ACD")

    // Background queue for BLE data parsing (keeps main thread free)
    private let bleProcessingQueue = DispatchQueue(
        label: "com.stride.ble-processing",
        qos: .userInitiated
    )

    // Throttle UI updates to 2.5 Hz (every 400ms)
    private var lastUIUpdateTime: Date = .distantPast
    private let uiUpdateInterval: TimeInterval = 0.4

    // Persist last connected device UUID for instant reconnection
    private let lastDeviceUUIDKey = "LastConnectedAssaultRunnerUUID"

    // MARK: - Init

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public API

    /// Try to connect to a previously paired Assault Runner without scanning.
    /// Call this on app launch after Bluetooth powers on.
    func connectToSystemPairedDevice() {
        guard centralManager.state == .poweredOn else {
            connectionState = "Bluetooth Off"
            return
        }

        // 1. Try retrieving the last connected peripheral by saved UUID
        if let savedUUID = UserDefaults.standard.string(forKey: lastDeviceUUIDKey),
           let uuid = UUID(uuidString: savedUUID) {
            let peripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])
            if let peripheral = peripherals.first {
                connectToPeripheral(peripheral)
                return
            }
        }

        // 2. Fallback: check system-connected peripherals with FTMS service
        let connected = centralManager.retrieveConnectedPeripherals(withServices: [ftmsServiceUUID])
        for peripheral in connected {
            let upperName = (peripheral.name ?? "").uppercased()
            if preferredKeywords.contains(where: { upperName.contains($0) }) {
                connectToPeripheral(peripheral)
                return
            }
        }

        connectionState = "No Paired Device"
    }

    /// Start scanning for FTMS treadmills (for a manual device picker UI).
    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        discoveredDevices.removeAll()
        centralManager.scanForPeripherals(withServices: [ftmsServiceUUID], options: nil)
        isScanning = true
    }

    /// Stop scanning.
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
    }

    /// Connect to a device chosen from the discovered list.
    func connect(to device: DiscoveredDevice) {
        connectToPeripheral(device.peripheral)
    }

    /// Disconnect from the current device.
    func disconnect() {
        reconnectionTimer?.invalidate()
        reconnectionTimer = nil
        reconnectionAttempts = 0
        guard let peripheral = connectedPeripheral else { return }
        centralManager.cancelPeripheralConnection(peripheral)
    }

    // MARK: - Internal Connection

    private func connectToPeripheral(_ peripheral: CBPeripheral) {
        stopScanning()
        connectedPeripheral = peripheral
        connectedPeripheral?.delegate = self
        lastConnectedPeripheral = peripheral
        reconnectionAttempts = 0

        // Save UUID for future instant reconnection
        UserDefaults.standard.set(
            peripheral.identifier.uuidString,
            forKey: lastDeviceUUIDKey
        )

        centralManager.connect(peripheral, options: nil)
        connectionState = "Connecting..."
    }

    // MARK: - Reconnection (exponential backoff)

    private func attemptReconnection() {
        guard let peripheral = lastConnectedPeripheral,
              reconnectionAttempts < maxReconnectionAttempts else {
            if reconnectionAttempts >= maxReconnectionAttempts {
                connectionState = "Reconnection Failed"
            }
            return
        }

        reconnectionAttempts += 1
        let delay = pow(2.0, Double(reconnectionAttempts - 1)) // 1s, 2s, 4s, 8s, 16s
        connectionState = "Reconnecting (\(reconnectionAttempts)/\(maxReconnectionAttempts))..."

        reconnectionTimer = Timer.scheduledTimer(
            withTimeInterval: delay,
            repeats: false
        ) { [weak self] _ in
            self?.centralManager.connect(peripheral, options: nil)
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            // Auto-connect on Bluetooth power-on
            if connectedDevice == nil {
                connectToSystemPairedDevice()
            }
        case .poweredOff:
            connectionState = "Bluetooth Off"
        case .unauthorized:
            connectionState = "Unauthorized"
        case .unsupported:
            connectionState = "Not Supported"
        default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let rssiValue = RSSI.intValue
        if let index = discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
            discoveredDevices[index].updateRSSI(rssiValue)
        } else {
            discoveredDevices.append(DiscoveredDevice(peripheral: peripheral, rssi: rssiValue))
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionState = "Connected"
        reconnectionAttempts = 0
        reconnectionTimer?.invalidate()

        // Create or update connected device reference
        connectedDevice = discoveredDevices.first(where: { $0.peripheral == peripheral })
            ?? DiscoveredDevice(peripheral: peripheral, rssi: 0)

        // Reset FTMS state and discover the FTMS service
        isFTMSSupported = false
        ftmsCharacteristic = nil
        peripheral.discoverServices([ftmsServiceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        connectionState = "Disconnected"

        // Attempt to reconnect automatically
        attemptReconnection()
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        connectionState = "Connection Failed"
        if reconnectionAttempts > 0 {
            attemptReconnection()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {

    // Step 1: Services discovered -> look for FTMS (0x1826)
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }

        if let ftmsService = services.first(where: { $0.uuid == ftmsServiceUUID }) {
            isFTMSSupported = true
            connectionState = "Connected (FTMS)"
            // Discover the Treadmill Data characteristic
            peripheral.discoverCharacteristics([treadmillDataUUID], for: ftmsService)
        } else {
            connectionState = "Connected (No FTMS)"
            isFTMSSupported = false
        }
    }

    // Step 2: Characteristics discovered -> subscribe to 0x2ACD notifications
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard let characteristics = service.characteristics else { return }

        if let treadmillChar = characteristics.first(where: { $0.uuid == treadmillDataUUID }) {
            ftmsCharacteristic = treadmillChar
            if treadmillChar.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: treadmillChar)
            }
        }
    }

    // Step 3: Notification confirmed
    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        // Notifications are now active. Data will arrive via didUpdateValueFor.
    }

    // Step 4: DATA ARRIVES HERE -- this fires every time the treadmill pushes a packet
    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == treadmillDataUUID,
              let data = characteristic.value,
              !data.isEmpty else { return }

        // Parse on background queue to keep UI smooth
        bleProcessingQueue.async { [weak self] in
            guard let self = self else { return }

            let parsed = FTMSTreadmillDataParser.parse(data: data, timestamp: Date())

            // Throttle callbacks to 2.5 Hz
            let now = Date()
            if now.timeIntervalSince(self.lastUIUpdateTime) >= self.uiUpdateInterval {
                self.lastUIUpdateTime = now
                DispatchQueue.main.async {
                    self.onTreadmillData?(parsed)
                }
            }
        }
    }
}
