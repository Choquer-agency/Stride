"""Exercise the actual Bluetooth provider with pre-start walking, gaps, reset and pause."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
code = '''import Foundation
struct Sample {
    var timestamp = Date()
    var speedMps: Double? = 3
    var totalDistanceMeters: Double?
    var elapsedTime: Int? = 600
    var heartRate: Int? = nil
}
struct RunSample {
    var timestamp: Date
    var speedMps: Double?
    var totalDistanceMeters: Double?
    var elapsedTime: TimeInterval?
    var heartRate: Int?
    var coordinate: Int?
    var altitudeMeters: Double?
}
protocol RunDataProvider {}
final class BluetoothManager {
    struct Device { var name: String }
    var connectedDevice: Device? = nil
    var latestDistanceMeters: Double? = 500
    var onTreadmillData: ((Sample) -> Void)?
    func send(_ total: Double?) {
        if let total { latestDistanceMeters = total }
        onTreadmillData?(Sample(totalDistanceMeters: total))
    }
}
'''
code += (root / 'Services/BluetoothRunDataProvider.swift').read_text()
code += '''
let manager = BluetoothManager()
let provider = BluetoothRunDataProvider(bluetoothManager: manager)
var distance = -1.0
provider.onRunSample = { distance = $0.totalDistanceMeters ?? distance }
provider.start()
manager.send(510)
assert(distance == 10) // excludes the 500 metres walked before Start
manager.send(nil)
manager.send(600)
assert(distance == 100) // retains the baseline across continuation packets
manager.send(900)
assert(distance == 400) // odometer catches up after a connection gap
manager.send(0)
manager.send(50)
assert(distance == 450) // console reset does not erase the run
provider.pause()
manager.send(100)
assert(distance == 450)
provider.resume()
manager.send(150)
assert(distance == 500) // paused distance is excluded
provider.stop()
provider.start()
manager.send(160)
assert(distance == 10) // new workout gets a fresh baseline
print("PASS: pre-start walking, continuation packets, connection gap, console reset, pause and restart")
'''
with tempfile.TemporaryDirectory() as directory:
    source = Path(directory) / 'main.swift'
    source.write_text(code)
    subprocess.run(['swift', str(source)], check=True)
