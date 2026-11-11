"""Verify the shipped theme cycle and persisted-value compatibility."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
source = (root / 'App/Theme.swift').read_text()
start = source.index('enum RunLobbyAppearance:')
end = source.index('\nextension Font {', start)
source = 'import SwiftUI\n' + source[start:end] + '''
let defaults = UserDefaults(suiteName: "stride-lobby-appearance-test")!
defaults.removePersistentDomain(forName: "stride-lobby-appearance-test")
var mode = RunLobbyAppearance.black
for expected in [RunLobbyAppearance.white, .red, .black] {
    mode = mode.next
    defaults.set(mode.rawValue, forKey: RunLobbyAppearance.storageKey)
    assert(RunLobbyAppearance(rawValue: defaults.string(forKey: RunLobbyAppearance.storageKey)!) == expected)
}
assert(RunLobbyAppearance.white.colorScheme == .light)
assert(RunLobbyAppearance.red.colorScheme == .dark && RunLobbyAppearance.black.colorScheme == .dark)
assert(RunLobbyAppearance.white.imageName != RunLobbyAppearance.red.imageName)
defaults.removePersistentDomain(forName: "stride-lobby-appearance-test")
print("Native appearance cycle, persistence and image selection pass")
'''
with tempfile.TemporaryDirectory() as tmp:
    p = Path(tmp) / 'main.swift'; p.write_text(source)
    binary = Path(tmp) / 'check'
    subprocess.run(['swiftc', str(p), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
