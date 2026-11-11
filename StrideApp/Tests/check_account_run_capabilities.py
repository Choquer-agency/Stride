"""Execute account run policy cases without requiring the iOS SDK."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
lobby = (root / 'Views/Run/RunLobbyView.swift').read_text()
policy = lobby[lobby.index('enum RunMode:'):lobby.index('struct RunLobbyView:')]
harness = '''
let restricted = UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!
let other = UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!
let overrides = [restricted: AccountRunCapabilities.outdoorOnly]
let blocked = AccountRunCapabilities.forUserID(restricted.uuidString.lowercased(), overrides: overrides)
assert(!blocked.allowsIndoorRunning)
assert(blocked.resolvedMode(.treadmill) == .outdoor)
assert(blocked.resolvedMode(.outdoor) == .outdoor)
for id in [other.uuidString, "Nicole", "Carson", "", "not-a-uuid"] {
    let normal = AccountRunCapabilities.forUserID(id, overrides: overrides)
    assert(normal.allowsIndoorRunning)
    assert(normal.resolvedMode(.treadmill) == .treadmill)
}
assert(AccountRunCapabilities.forUserID(nil, overrides: overrides).allowsIndoorRunning)
assert(AccountRunCapabilities.forUserID(restricted.uuidString, overrides: [:]).allowsIndoorRunning)
let restored = AccountRunCapabilities.forUserID(restricted.uuidString, overrides: [restricted: .standard])
assert(restored.resolvedMode(.treadmill) == .treadmill)
// No guessed production identities: every unlisted account keeps indoor running.
assert(AccountRunCapabilities.forUserID(other.uuidString).allowsIndoorRunning)
print("Account run capability checks passed")
'''
with tempfile.TemporaryDirectory() as temp:
    source = Path(temp) / 'main.swift'
    binary = Path(temp) / 'checks'
    source.write_text('import Foundation\n' + policy + harness)
    subprocess.run(['swiftc', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
