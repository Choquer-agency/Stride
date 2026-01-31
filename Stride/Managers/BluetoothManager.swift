import Foundation
import CoreBluetooth
import Combine

/// Manages all Bluetooth Low Energy operations with FTMS focus
class BluetoothManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var isScanning: Bool = false
    @Published var connectedDevice: DiscoveredDevice?
    @Published var connectionState: String = "Disconnected"
    @Published var isFTMSSupported: Bool = false
    @Published var ftmsCharacteristic: CBCharacteristic?
    
    // MARK: - Private Properties
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var workoutManager: WorkoutManager?
    
    // Auto-connect management
    private var shouldAutoConnect: Bool = true
    private let preferredKeywords = ["ASSAULT", "AIRRUNNER", "RUNNER"]
    
    // Reconnection management
    private var lastConnectedPeripheralId: UUID?
    private var lastConnectedPeripheral: CBPeripheral?
    private var reconnectionAttempts: Int = 0
    private var maxReconnectionAttempts: Int = 5
    private var reconnectionTimer: Timer?
    private var lastKnownDistance: Double = 0
    
    // FTMS Service and Characteristic UUIDs
    private let ftmsServiceUUID = CBUUID(string: "1826")
    private let treadmillDataUUID = CBUUID(string: "2ACD")
    
    // Background processing queue for BLE data
    private let bleProcessingQueue = DispatchQueue(label: "com.stride.ble-processing", qos: .userInitiated)
    
    // Throttling for UI updates
    private var lastUIUpdateTime: Date = Date.distantPast
    private let uiUpdateInterval: TimeInterval = 0.4 // 2.5 Hz (every 400ms)
    private var pendingSample: ParsedTreadmillSample?
    
    // UserDefaults keys for persistent storage
    private let lastConnectedDeviceUUIDKey = "LastConnectedAssaultRunnerUUID"
    
    // MARK: - Initialization
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    /// Set workout manager for forwarding parsed data
    func setWorkoutManager(_ manager: WorkoutManager) {
        self.workoutManager = manager
    }
    
    // MARK: - Public Methods
    
    /// Retrieve and connect to system-paired Assault Runner
    func connectToSystemPairedDevice() {
        guard centralManager.state == .poweredOn else {
            print("Bluetooth is not powered on")
            connectionState = "Bluetooth Off"
            return
        }
        
        // Try to retrieve last connected device first
        if let savedUUID = UserDefaults.standard.string(forKey: lastConnectedDeviceUUIDKey),
           let uuid = UUID(uuidString: savedUUID) {
            print("🔍 Attempting to retrieve last connected device: \(uuid)")
            let peripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])
            
            if let peripheral = peripherals.first {
                print("✅ Found last connected device: \(peripheral.name ?? "Unknown")")
                connectToPeripheral(peripheral)
                return
            }
        }
        
        // Look for any connected peripherals with FTMS service
        print("🔍 Checking for connected FTMS peripherals...")
        let connectedPeripherals = centralManager.retrieveConnectedPeripherals(withServices: [ftmsServiceUUID])
        
        for peripheral in connectedPeripherals {
            let upperName = (peripheral.name ?? "").uppercased()
            if preferredKeywords.contains(where: { upperName.contains($0) }) {
                print("✅ Found connected Assault Runner: \(peripheral.name ?? "Unknown")")
                connectToPeripheral(peripheral)
                return
            }
        }
        
        print("❌ No system-paired Assault Runner found")
        connectionState = "No Paired Device"
    }
    
    /// Start manual scanning for BLE devices (fallback for Settings)
    func startManualScanning() {
        guard centralManager.state == .poweredOn else {
            print("Bluetooth is not powered on")
            return
        }
        
        discoveredDevices.removeAll()
        // Remove CBCentralManagerScanOptionAllowDuplicatesKey to reduce callbacks
        centralManager.scanForPeripherals(withServices: [ftmsServiceUUID], options: nil)
        isScanning = true
        print("Started manual scanning for FTMS devices")
    }
    
    /// Stop scanning for BLE devices
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        print("Stopped scanning")
    }
    
    /// Internal method to connect to a peripheral
    private func connectToPeripheral(_ peripheral: CBPeripheral) {
        stopScanning()
        connectedPeripheral = peripheral
        connectedPeripheral?.delegate = self
        lastConnectedPeripheralId = peripheral.identifier
        lastConnectedPeripheral = peripheral
        reconnectionAttempts = 0
        
        // Save to UserDefaults for future quick connection
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: lastConnectedDeviceUUIDKey)
        
        centralManager.connect(peripheral, options: nil)
        connectionState = "Connecting..."
        print("Connecting to \(peripheral.name ?? "Unknown")")
    }
    
    /// Connect to a discovered device (used in manual scanning mode)
    func connect(to device: DiscoveredDevice) {
        connectToPeripheral(device.peripheral)
    }
    
    /// Disconnect from the current device
    func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        // Cancel any pending reconnection attempts
        reconnectionTimer?.invalidate()
        reconnectionTimer = nil
        reconnectionAttempts = 0
        centralManager.cancelPeripheralConnection(peripheral)
        print("Disconnecting...")
    }
    
    // MARK: - Reconnection Logic
    
    /// Attempt to reconnect to the last connected device
    private func attemptReconnection() {
        guard let peripheral = lastConnectedPeripheral,
              let workoutManager = workoutManager,
              workoutManager.isRecording,
              reconnectionAttempts < maxReconnectionAttempts else {
            if reconnectionAttempts >= maxReconnectionAttempts {
                print("❌ Max reconnection attempts reached")
                connectionState = "Reconnection Failed"
            }
            return
        }
        
        reconnectionAttempts += 1
        
        // Calculate exponential backoff delay (1s, 2s, 4s, 8s, 16s)
        let delay = pow(2.0, Double(reconnectionAttempts - 1))
        
        print("🔄 Scheduling reconnection attempt \(reconnectionAttempts)/\(maxReconnectionAttempts) in \(delay)s...")
        connectionState = "Reconnecting (\(reconnectionAttempts)/\(maxReconnectionAttempts))..."
        
        reconnectionTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            print("🔄 Attempting to reconnect...")
            self.centralManager.connect(peripheral, options: nil)
        }
    }
    
}

// MARK: - CBCentralManagerDelegate
extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth is powered on")
            // Automatically try to connect to system-paired device if not already connected
            if connectedDevice == nil && shouldAutoConnect {
                connectToSystemPairedDevice()
            }
        case .poweredOff:
            print("Bluetooth is powered off")
            connectionState = "Bluetooth Off"
        case .unauthorized:
            print("Bluetooth is unauthorized")
            connectionState = "Unauthorized"
        case .unsupported:
            print("Bluetooth is not supported")
            connectionState = "Not Supported"
        default:
            print("Bluetooth state: \(central.state.rawValue)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let rssiValue = RSSI.intValue
        
        // Only process discovered devices during manual scanning (in Settings)
        // Update existing device or add new one
        if let index = discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
            discoveredDevices[index].updateRSSI(rssiValue)
        } else {
            let device = DiscoveredDevice(peripheral: peripheral, rssi: rssiValue)
            discoveredDevices.append(device)
            print("📱 Discovered device: \(device.name) (RSSI: \(rssiValue))")
        }
    }
    
    private func isConnecting() -> Bool {
        return connectionState == "Connecting..."
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to \(peripheral.name ?? "Unknown")")
        connectionState = "Connected"
        
        // Successfully reconnected - reset counter
        if reconnectionAttempts > 0 {
            print("✅ Reconnection successful after \(reconnectionAttempts) attempts")
            reconnectionAttempts = 0
            reconnectionTimer?.invalidate()
            reconnectionTimer = nil
            
            // Resume workout if it was paused due to disconnection
            if let workoutManager = workoutManager, workoutManager.isPaused && workoutManager.isRecording {
                workoutManager.resumeWorkout()
                print("Resumed workout after reconnection")
            }
        }
        
        // Update connected device - create DiscoveredDevice if not in discoveredDevices
        if let device = discoveredDevices.first(where: { $0.peripheral == peripheral }) {
            connectedDevice = device
        } else {
            // Create a device entry for system-paired peripherals
            let device = DiscoveredDevice(peripheral: peripheral, rssi: 0)
            connectedDevice = device
        }
        
        // Reset FTMS state
        isFTMSSupported = false
        ftmsCharacteristic = nil
        
        // Discover services - prioritize FTMS
        peripheral.discoverServices([ftmsServiceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from \(peripheral.name ?? "Unknown")")
        connectionState = "Disconnected"
        
        if let error = error {
            print("Disconnection error: \(error.localizedDescription)")
        }
        
        // Check if workout is active and should auto-reconnect
        if let workoutManager = workoutManager, workoutManager.isRecording && !workoutManager.isPaused {
            print("⚠️ Workout active - pausing and attempting reconnection")
            
            // Pause the workout (don't stop it)
            workoutManager.pauseWorkout()
            
            // Store the last known distance for recovery
            lastKnownDistance = workoutManager.liveStats.totalDistanceMeters
            
            // Attempt to reconnect
            attemptReconnection()
        } else {
            // Not recording or manually disconnected - clear state normally
            connectedDevice = nil
            connectedPeripheral = nil
            isFTMSSupported = false
            ftmsCharacteristic = nil
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect to \(peripheral.name ?? "Unknown")")
        connectionState = "Connection Failed"
        
        if let error = error {
            print("Connection error: \(error.localizedDescription)")
        }
        
        // If this was a reconnection attempt during an active workout, try again
        if let workoutManager = workoutManager, workoutManager.isRecording, reconnectionAttempts > 0 {
            attemptReconnection()
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("Error discovering services: \(error.localizedDescription)")
            connectionState = "Error discovering services"
            return
        }
        
        guard let services = peripheral.services else { return }
        
        print("Discovered \(services.count) services")
        
        // Check for FTMS service
        if let ftmsService = services.first(where: { $0.uuid == ftmsServiceUUID }) {
            print("✅ FTMS service found!")
            isFTMSSupported = true
            connectionState = "Connected (FTMS)"
            
            // Discover characteristics for FTMS service
            peripheral.discoverCharacteristics([treadmillDataUUID], for: ftmsService)
        } else {
            print("❌ FTMS service not found")
            connectionState = "Connected (No FTMS)"
            isFTMSSupported = false
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("Error discovering characteristics: \(error.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else { return }
        
        print("Discovered \(characteristics.count) characteristics for service \(service.uuid)")
        
        // Look for Treadmill Data characteristic (0x2ACD)
        if service.uuid == ftmsServiceUUID {
            if let treadmillChar = characteristics.first(where: { $0.uuid == treadmillDataUUID }) {
                print("✅ Found Treadmill Data characteristic (0x2ACD)")
                ftmsCharacteristic = treadmillChar
                
                // Subscribe to notifications
                if treadmillChar.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: treadmillChar)
                    print("Subscribed to Treadmill Data notifications")
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Error changing notification state: \(error.localizedDescription)")
            return
        }
        
        if characteristic.isNotifying {
            print("Notifications enabled for: \(characteristic.uuid)")
        } else {
            print("Notifications disabled for: \(characteristic.uuid)")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Error reading characteristic value: \(error.localizedDescription)")
            return
        }
        
        guard let data = characteristic.value, !data.isEmpty else {
            return
        }
        
        // Handle FTMS Treadmill Data (0x2ACD)
        if characteristic.uuid == treadmillDataUUID {
            // Process BLE data on background queue to avoid blocking main thread
            bleProcessingQueue.async { [weak self] in
                guard let self = self else { return }
                
                // Use autoreleasepool to release temporary parsing objects immediately
                autoreleasepool {
                    let parsed = FTMSTreadmillDataParser.parse(data: data, timestamp: Date())
                    
                    // Throttle UI updates to 2.5 Hz to reduce main thread load
                    let now = Date()
                    let timeSinceLastUpdate = now.timeIntervalSince(self.lastUIUpdateTime)
                    
                    if timeSinceLastUpdate >= self.uiUpdateInterval {
                        // Send update to workout manager on main thread
                        DispatchQueue.main.async {
                            self.workoutManager?.addSample(parsed)
                            self.lastUIUpdateTime = now
                        }
                        
                        // Optional: Debug logging (reduce frequency in production)
                        #if DEBUG
                        if let speed = parsed.instantaneousSpeedKmh, let distance = parsed.totalDistanceMeters {
                            print("📊 Speed: \(String(format: "%.1f", speed)) km/h, Distance: \(String(format: "%.0f", distance)) m")
                        }
                        #endif
                    } else {
                        // Store the most recent sample to send on next interval
                        self.pendingSample = parsed
                    }
                }
            }
        }
    }
}

