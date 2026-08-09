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

    // Data-flow diagnostics: a run screen can tell "connected" from "actually
    // receiving packets" (connected-but-silent was invisible before).
    @Published var packetCount: Int = 0
    @Published var lastPacketAt: Date?
    @Published var subscriptionState: String = "—"   // "Subscribed" | failure reason

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

    // Persistent event log — readable in Settings → Treadmill Diagnostics
    private let diag = BLEDiagnosticsLog.shared

    // Connect-attempt timeout: CoreBluetooth's connect() never times out on its
    // own; a stale saved identifier would leave us in "Connecting..." forever.
    private var connectTimeoutTimer: Timer?
    private let connectTimeout: TimeInterval = 12

    // Data watchdog: "Subscribed" but silent is a dead link in disguise.
    private var watchdogTimer: Timer?
    private var recoveryStage = 0   // 0 fine, 1 resubscribed, 2 reconnected, 3 fresh-scanned

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
                diag.log("connect via saved UUID → \(peripheral.name ?? "unnamed") [\(peripheral.identifier)]")
                connectToPeripheral(peripheral)
                return
            }
            diag.log("saved UUID \(savedUUID) not retrievable — falling back")
        }

        // 2. Fallback: check system-connected peripherals with FTMS service
        let connected = centralManager.retrieveConnectedPeripherals(withServices: [ftmsServiceUUID])
        diag.log("system-connected FTMS peripherals: \(connected.map { $0.name ?? "unnamed" })")
        for peripheral in connected {
            let upperName = (peripheral.name ?? "").uppercased()
            if preferredKeywords.contains(where: { upperName.contains($0) }) {
                diag.log("connect via system-connected list → \(peripheral.name ?? "unnamed")")
                connectToPeripheral(peripheral)
                return
            }
        }

        connectionState = "No Paired Device"
        diag.log("no paired device found")
    }

    /// Nuclear option: drop everything, forget the saved identifier, and find
    /// the treadmill again by a fresh FTMS scan. Used by the watchdog's last
    /// escalation and exposed in the diagnostics screen.
    func forceFreshReconnect() {
        diag.log("FORCE fresh reconnect: clearing saved UUID, disconnecting, scanning")
        UserDefaults.standard.removeObject(forKey: lastDeviceUUIDKey)
        reconnectionTimer?.invalidate()
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        lastConnectedPeripheral = nil
        startScanning()
        // Auto-connect to the first Assault-named discovery
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, self.connectedPeripheral == nil else { return }
            let match = self.discoveredDevices.first {
                let n = $0.name.uppercased()
                return self.preferredKeywords.contains(where: { n.contains($0) })
            } ?? self.discoveredDevices.first
            if let match {
                self.diag.log("fresh scan found \(match.name) — connecting")
                self.connect(to: match)
            } else {
                self.diag.log("fresh scan found nothing after 6 s (is the console awake?)")
                self.connectionState = "Treadmill Not Found"
                self.stopScanning()
            }
        }
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
        diag.log("manual disconnect requested")
        reconnectionTimer?.invalidate()
        reconnectionTimer = nil
        reconnectionAttempts = 0
        stopWatchdog()
        connectTimeoutTimer?.invalidate()
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
        diag.log("connecting to \(peripheral.name ?? "unnamed") [\(peripheral.identifier)]")

        connectTimeoutTimer?.invalidate()
        connectTimeoutTimer = Timer.scheduledTimer(withTimeInterval: connectTimeout, repeats: false) { [weak self] _ in
            guard let self, self.connectionState == "Connecting..." else { return }
            self.diag.log("connect TIMEOUT after \(Int(self.connectTimeout)) s — cancelling, trying fresh scan")
            self.centralManager.cancelPeripheralConnection(peripheral)
            self.forceFreshReconnect()
        }
    }

    // MARK: - Data watchdog

    private func startWatchdog() {
        watchdogTimer?.invalidate()
        recoveryStage = 0
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.watchdogTick()
        }
    }

    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }

    private func watchdogTick() {
        guard connectedDevice != nil, subscriptionState == "Subscribed" else { return }
        let silentFor = lastPacketAt.map { Date().timeIntervalSince($0) } ?? Date().timeIntervalSince(subscribedAt ?? .distantPast)
        guard silentFor > 10 else {
            if recoveryStage != 0 { diag.log("watchdog: data flowing again — recovery stage reset") }
            recoveryStage = 0
            return
        }

        switch recoveryStage {
        case 0:
            recoveryStage = 1
            diag.log("watchdog: subscribed but silent \(Int(silentFor)) s — resubscribing to 2ACD")
            if let peripheral = connectedPeripheral, let char = ftmsCharacteristic {
                peripheral.setNotifyValue(false, for: char)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    peripheral.setNotifyValue(true, for: char)
                }
            }
        case 1:
            recoveryStage = 2
            diag.log("watchdog: still silent — full disconnect/reconnect")
            if let peripheral = connectedPeripheral {
                centralManager.cancelPeripheralConnection(peripheral)
            }
            // didDisconnect → attemptReconnection handles the rest
        default:
            recoveryStage = 3
            diag.log("watchdog: still silent after reconnect — forcing fresh scan")
            forceFreshReconnect()
        }
    }

    private var subscribedAt: Date?

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
        diag.log("central state → \(central.state.rawValue)")
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
        connectTimeoutTimer?.invalidate()
        diag.log("CONNECTED to \(peripheral.name ?? "unnamed") [\(peripheral.identifier)] — discovering FTMS")
        startWatchdog()

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
        diag.log("DISCONNECTED from \(peripheral.name ?? "unnamed") — error: \(error?.localizedDescription ?? "clean")")
        // Reflect reality — a stale connectedDevice let runs start against
        // a peripheral that was long gone.
        connectedDevice = nil
        isFTMSSupported = false
        subscriptionState = "—"
        subscribedAt = nil

        // Attempt to reconnect automatically
        attemptReconnection()
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        connectionState = "Connection Failed"
        diag.log("connect FAILED to \(peripheral.name ?? "unnamed") — \(error?.localizedDescription ?? "unknown")")
        if reconnectionAttempts > 0 {
            attemptReconnection()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {

    // Step 1: Services discovered -> look for FTMS (0x1826)
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else {
            diag.log("didDiscoverServices: nil (error: \(error?.localizedDescription ?? "none"))")
            return
        }
        diag.log("services: \(services.map { $0.uuid.uuidString }.joined(separator: ", "))")

        if let ftmsService = services.first(where: { $0.uuid == ftmsServiceUUID }) {
            isFTMSSupported = true
            connectionState = "Connected (FTMS)"
            // Discover ALL characteristics so the log shows what this console exposes
            peripheral.discoverCharacteristics(nil, for: ftmsService)
        } else {
            connectionState = "Connected (No FTMS)"
            subscriptionState = "No FTMS service — services: \(services.map { $0.uuid.uuidString }.joined(separator: ", "))"
            isFTMSSupported = false
        }
    }

    // Step 2: Characteristics discovered -> subscribe to 0x2ACD
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard let characteristics = service.characteristics else { return }
        diag.log("FTMS chars: \(characteristics.map { "\($0.uuid.uuidString)(props \($0.properties.rawValue))" }.joined(separator: ", "))")

        if let treadmillChar = characteristics.first(where: { $0.uuid == treadmillDataUUID }) {
            ftmsCharacteristic = treadmillChar
            // Some consoles expose Treadmill Data as indicate-only — accept both.
            if treadmillChar.properties.contains(.notify) || treadmillChar.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: treadmillChar)
            } else {
                subscriptionState = "2ACD not notifiable (props=\(treadmillChar.properties.rawValue))"
                diag.log("2ACD is not notify/indicate capable — props \(treadmillChar.properties.rawValue)")
            }
        } else {
            subscriptionState = "No Treadmill Data (2ACD) characteristic"
            diag.log("2ACD MISSING from FTMS service")
        }
    }

    // Step 3: Notification confirmed (or failed — pairing/encryption errors land here)
    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == treadmillDataUUID else { return }
        if let error {
            subscriptionState = "Subscribe failed: \(error.localizedDescription)"
            diag.log("subscribe FAILED: \(error.localizedDescription)")
        } else if characteristic.isNotifying {
            subscriptionState = "Subscribed"
            subscribedAt = Date()
            diag.log("SUBSCRIBED to Treadmill Data — waiting for packets")
        } else {
            subscriptionState = "Notifications off"
            diag.log("notifications reported OFF for 2ACD")
        }
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
                    self.packetCount += 1
                    self.lastPacketAt = now
                    if self.packetCount == 1 {
                        self.diag.log("FIRST PACKET hex=\(parsed.rawHex) flags=\(parsed.flags) speed=\(parsed.instantaneousSpeedKmh ?? -1) dist=\(parsed.totalDistanceMeters ?? -1)")
                    } else if self.packetCount % 150 == 0 {
                        self.diag.log("packet #\(self.packetCount) — speed=\(parsed.instantaneousSpeedKmh ?? -1) dist=\(parsed.totalDistanceMeters ?? -1)")
                    }
                    self.onTreadmillData?(parsed)
                }
            }
        }
    }
}
