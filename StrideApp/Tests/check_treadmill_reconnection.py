"""Replay treadmill lifecycle failures through the actual manager with deterministic BLE/timers."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
code = r'''import Foundation
@propertyWrapper struct Published<T> { var wrappedValue: T }
protocol ObservableObject {}
protocol CBCentralManagerDelegate: AnyObject {}
protocol CBPeripheralDelegate: AnyObject {}
struct CBUUID: Equatable { let uuidString: String; init(string: String) { uuidString = string } }
enum CBManagerState: Int { case unknown, resetting, unsupported, unauthorized, poweredOff, poweredOn }
enum CBPeripheralState { case disconnected, connecting, connected, disconnecting }
struct CBCharacteristicProperties: OptionSet {
    let rawValue: UInt
    static let notify = Self(rawValue: 16), indicate = Self(rawValue: 32)
}
final class CBCharacteristic {
    var uuid = CBUUID(string: "2ACD")
    var properties: CBCharacteristicProperties = [.notify]
    var isNotifying = true
    var value: Data? = Data([0, 0])
}
final class CBService {
    var uuid = CBUUID(string: "1826")
    var characteristics: [CBCharacteristic]? = [CBCharacteristic()]
}
final class CBPeripheral: NSObject {
    var name: String? = "AssaultRunner752753"
    let identifier = UUID()
    var state = CBPeripheralState.disconnected
    weak var delegate: AnyObject?
    var services: [CBService]? = [CBService()]
    func discoverServices(_ services: [CBUUID]?) {}
    func discoverCharacteristics(_ characteristics: [CBUUID]?, for service: CBService) {}
    func setNotifyValue(_ value: Bool, for characteristic: CBCharacteristic) {}
}
final class CBCentralManager {
    var state = CBManagerState.poweredOn
    var connectCalls = 0, scanCalls = 0, cancellations = 0
    init(delegate: CBCentralManagerDelegate?, queue: DispatchQueue?) {}
    func retrievePeripherals(withIdentifiers ids: [UUID]) -> [CBPeripheral] { [] }
    func retrieveConnectedPeripherals(withServices ids: [CBUUID]) -> [CBPeripheral] { [] }
    func scanForPeripherals(withServices ids: [CBUUID]?, options: [String: Any]?) { scanCalls += 1 }
    func stopScan() {}
    func connect(_ peripheral: CBPeripheral, options: [String: Any]?) {
        connectCalls += 1; peripheral.state = .connecting
    }
    func cancelPeripheralConnection(_ peripheral: CBPeripheral) {
        cancellations += 1; peripheral.state = .disconnected
    }
}
final class Timer {
    var valid = true
    let block: (Timer) -> Void
    let repeats: Bool
    init(repeats: Bool, block: @escaping (Timer) -> Void) { self.repeats = repeats; self.block = block }
    static func scheduledTimer(withTimeInterval: TimeInterval, repeats: Bool, block: @escaping (Timer) -> Void) -> Timer {
        Timer(repeats: repeats, block: block)
    }
    func invalidate() { valid = false }
    func fire() { guard valid else { return }; if !repeats { valid = false }; block(self) }
}
final class BLEDiagnosticsLog {
    static let shared = BLEDiagnosticsLog()
    var lines: [String] = []
    func log(_ text: String) { lines.append(text) }
}
struct ParsedTreadmillSample {
    var totalDistanceMeters: Double? = 100
    var instantaneousSpeedKmh: Double? = 9
    var rawHex = "0000"
    var flags = 0
}
enum FTMSTreadmillDataParser {
    static func parse(data: Data, timestamp: Date) -> ParsedTreadmillSample { ParsedTreadmillSample() }
}
let defaultsSuite = "stride-ble-test-\(UUID().uuidString)"
let TestDefaults = UserDefaults(suiteName: defaultsSuite)!
defer { TestDefaults.removePersistentDomain(forName: defaultsSuite) }
'''
for file in ['Models/DiscoveredDevice.swift', 'Services/BluetoothManager.swift']:
    source = (root / file).read_text()
    source = '\n'.join(line for line in source.splitlines() if not line.startswith('import '))
    source = source.replace('private(set) ', '').replace('private ', '')
    source = source.replace('UserDefaults.standard', 'TestDefaults')
    code += source + '\n'
code += r'''
func discover(_ manager: BluetoothManager, _ peripheral: CBPeripheral) {
    manager.centralManager(manager.centralManager, didDiscover: peripheral, advertisementData: [:], rssi: -40)
}
let manager = BluetoothManager(), treadmill = CBPeripheral()
manager.connect(to: DiscoveredDevice(peripheral: treadmill, rssi: -40))
assert(manager.centralManager.connectCalls == 1 && manager.connectTimeoutTimer!.valid)
treadmill.state = .connected
manager.centralManager(manager.centralManager, didConnect: treadmill)
assert(manager.connectTimeoutTimer!.valid) // GATT setup must also have a deadline.
let characteristic = CBCharacteristic()
manager.peripheral(treadmill, didUpdateNotificationStateFor: characteristic, error: nil)
manager.peripheral(treadmill, didUpdateValueFor: characteristic, error: nil)
RunLoop.current.run(until: Date().addingTimeInterval(0.1))
assert(manager.packetCount == 1 && manager.lastPacketAt != nil)
assert(!manager.connectTimeoutTimer!.valid)
// Saturday: data arrived, then the OS reported a dropped link.
treadmill.state = .disconnected
manager.centralManager(manager.centralManager, didDisconnectPeripheral: treadmill, error: nil)
assert(manager.connectedPeripheral == nil && manager.connectedDevice == nil)
assert(manager.reconnectionTimer!.valid)
manager.reconnectionTimer!.fire()
assert(manager.centralManager.connectCalls == 2 && manager.connectTimeoutTimer!.valid)
// Previously this automatic retry had no deadline and could block rediscovery forever.
manager.connectTimeoutTimer!.fire()
assert(manager.connectedPeripheral == nil && manager.isScanning)
manager.centralManager(manager.centralManager, didDisconnectPeripheral: treadmill, error: nil)
assert(manager.isScanning && manager.reconnectionTimer == nil) // Cancel ack cannot undo fresh scan.
discover(manager, treadmill)
assert(manager.centralManager.connectCalls == 3 && !manager.isScanning)
assert(manager.connectedPeripheral === treadmill && manager.connectTimeoutTimer!.valid)
// A failure for another, obsolete peripheral cannot clear the live attempt.
let obsolete = CBPeripheral()
manager.centralManager(manager.centralManager, didFailToConnect: obsolete, error: nil)
assert(manager.connectedPeripheral === treadmill)
// Connected but discovery/subscription never completes: setup deadline still recovers.
treadmill.state = .connected
manager.centralManager(manager.centralManager, didConnect: treadmill)
manager.connectTimeoutTimer!.fire()
assert(manager.isScanning && manager.connectedPeripheral == nil)
// Discoveries during a scheduled backoff must win over the delayed retry.
discover(manager, treadmill)
treadmill.state = .disconnected
manager.centralManager(manager.centralManager, didDisconnectPeripheral: treadmill, error: nil)
let retry = manager.reconnectionTimer!
discover(manager, treadmill)
let calls = manager.centralManager.connectCalls
retry.fire()
assert(manager.centralManager.connectCalls == calls && !retry.valid)
// Explicit disconnect clears status and suppresses automatic rediscovery.
manager.disconnect()
assert(manager.connectedDevice == nil && manager.connectedPeripheral == nil && !manager.isScanning)
discover(manager, treadmill)
assert(manager.centralManager.connectCalls == calls)
manager.connect(to: DiscoveredDevice(peripheral: treadmill, rssi: -40))
assert(manager.centralManager.connectCalls == calls + 1) // Explicit Connect reenables recovery.
assert(!BLEDiagnosticsLog.shared.lines.contains { $0.contains("likely asleep") })
print("PASS: real manager replay — initial data, dropped link, bounded automatic retry, fresh scan, rediscovery, setup timeout, stale callbacks, backoff race, manual disconnect/reconnect, and truthful diagnostics")
'''
with tempfile.TemporaryDirectory(prefix='stride-ble-recovery-') as directory:
    source = Path(directory) / 'main.swift'
    source.write_text(code)
    binary = Path(directory) / 'check'
    subprocess.run(['swiftc', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
