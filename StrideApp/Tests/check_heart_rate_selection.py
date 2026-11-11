"""Exercise the production account-scoped Bluetooth consent policy."""
from pathlib import Path
import subprocess
import tempfile
source = (Path(__file__).resolve().parents[1] / 'Services/HeartRateManager.swift').read_text()
policy = source[source.index('struct HeartRateDeviceSelection'):source.index('/// Live heart-rate')]
code = 'import Foundation\n' + policy + r'''
let defaults = UserDefaults(suiteName: "stride.hr.test." + UUID().uuidString)!
let bryce = HeartRateDeviceSelection(accountID: "bryce", defaults: defaults)
let michelle = HeartRateDeviceSelection(accountID: "michelle", defaults: defaults)
let mine = UUID(), hers = UUID()
assert(!bryce.allows(hers, accountID: "bryce")) // Nearby alone is not consent.
bryce.save(id: mine, name: "My watch")
michelle.save(id: hers, name: "Her watch")
assert(bryce.allows(mine, accountID: "bryce"))
assert(!bryce.allows(hers, accountID: "bryce"))
assert(!bryce.allows(mine, accountID: "michelle")) // Stale account callbacks.
assert(!bryce.allows(mine, accountID: nil))
let restored = HeartRateDeviceSelection(accountID: "bryce", defaults: defaults)
assert(restored.deviceID == mine && restored.name == "My watch")
bryce.forget()
assert(!bryce.allows(mine, accountID: "bryce"))
assert(michelle.allows(hers, accountID: "michelle"))
michelle.forget()
print("PASS: explicit selection, account isolation, persistence, sign-out and forget")
'''
# Ensure discovery routes through consent rather than directly connecting.
discovery = source[source.index('didDiscover peripheral:'):source.index('nonisolated func centralManager(_ central: CBCentralManager, didConnect')]
assert 'central.connect(' not in discovery
assert 'self.connectIfSelected(peripheral)' in discovery
with tempfile.TemporaryDirectory() as folder:
    swift = Path(folder) / 'selection.swift'
    swift.write_text(code)
    subprocess.run(['swift', str(swift)], check=True)
