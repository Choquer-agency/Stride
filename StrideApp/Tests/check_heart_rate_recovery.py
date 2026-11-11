"""Exercise the production watchdog's stale-reading and connection retry paths."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]

def method(signature):
    source = (root / 'Services/HeartRateManager.swift').read_text()
    start = source.index(signature)
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end].replace('private func', 'func')

code = '''import Foundation
final class Peripheral {}
final class Central {
    var cancellations = 0
    func cancelPeripheralConnection(_ peripheral: Peripheral) { cancellations += 1 }
}
final class Harness {
    struct Sample { let t: TimeInterval; let bpm: Int }
    var owners: Set<String> = ["app", "run"]
    var lastReading: Date?
    var connectionStartedAt: Date?
    var peripheral: Peripheral? = Peripheral()
    var central: Central? = Central()
    var isConnected = false
    var currentBPM: Int?
    var samples: [Sample] = []
    var samplingStart: Date? = Date()
    static let maxSamples = 15000
    var scans = 0
    func scanIfPoweredOn() { if !owners.isEmpty && peripheral == nil { scans += 1 } }
'''
for signature in ['private func checkConnection', 'private func retryConnection', 'private func record(bpm:']:
    code += method(signature) + '\n'
code += '''
}
let hr = Harness()
let now = Date()
hr.connectionStartedAt = now
hr.checkConnection(now: now.addingTimeInterval(15))
assert(!hr.isConnected && hr.central!.cancellations == 0)
hr.checkConnection(now: now.addingTimeInterval(21))
assert(hr.peripheral == nil && hr.scans == 1 && hr.central!.cancellations == 1)
hr.peripheral = Peripheral()
hr.connectionStartedAt = now
hr.record(bpm: 142)
assert(hr.isConnected && hr.currentBPM == 142 && hr.samples.last!.bpm == 142)
let last = hr.lastReading!
hr.checkConnection(now: last.addingTimeInterval(11))
assert(!hr.isConnected && hr.currentBPM == nil) // FTMS fallback can now be used.
assert(hr.peripheral != nil)
hr.checkConnection(now: last.addingTimeInterval(21))
assert(hr.peripheral == nil && hr.scans == 2 && hr.central!.cancellations == 2)
hr.peripheral = Peripheral()
hr.record(bpm: 145)
assert(hr.isConnected && hr.samples.count == 2)
hr.owners = []
hr.record(bpm: 150)
hr.checkConnection(now: last.addingTimeInterval(500))
assert(hr.samples.count == 2 && hr.central!.cancellations == 2)
print("PASS: stalled connection timeout, fresh measurement status, stale HR removal, automatic retry, resumed readings, and inactive-owner guard")
'''
with tempfile.TemporaryDirectory(prefix='stride-hr-recovery-') as temporary:
    source = Path(temporary) / 'main.swift'
    source.write_text(code)
    binary = Path(temporary) / 'check'
    subprocess.run(['swiftc', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
