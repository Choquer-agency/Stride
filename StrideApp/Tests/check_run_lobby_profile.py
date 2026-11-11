"""Execute the native session profile with real prescription formats."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
source = (root / 'Services/IntervalWorkoutParser.swift').read_text()
source += r'''
func profile(_ text: String?, _ km: Double? = 7, steady: Bool = true) -> [Double] {
    RunSessionProfile.levels(details: text, totalKm: km, easyPace: "6:00–6:30/km", allowSteady: steady)
}
let easy = profile("Easy conversational effort", 6)
assert(easy.count == 48 && Set(easy).count == 1)
assert(profile("Unreadable custom speed session", steady: false).isEmpty)
let strides = profile("Easy Run + Strides — 4 × 20 sec strides included in the final 2 km", 7)
var workGroups = 0
for i in strides.indices where strides[i] > 0.8 {
    if i == 0 || strides[i - 1] <= 0.8 { workGroups += 1 }
}
assert(workGroups == 4, "Every short stride must remain visible")
assert(strides.contains(where: { $0 < 0.25 }), "Recoveries must be shown")
let progression = profile("First 21 km at 6:00–6:30/km, final 3 km at 5:30/km", 24)
assert(progression.first! < progression.last!, "Faster finish must be higher")
let reps = profile("Warm-up: 2 km at 6:00/km; 5 × 1 km at 4:45/km with 400 m jog at 6:30/km; Cool-down: 2 km at 6:00/km", 12, steady: false)
assert(!reps.isEmpty && reps.max()! > 0.8 && reps.min()! < 0.25)
print("Native lobby profiles: easy, short strides, recoveries, progression and intervals pass")
'''
with tempfile.TemporaryDirectory() as tmp:
    p = Path(tmp) / 'main.swift'; p.write_text(source)
    binary = Path(tmp) / 'check'
    subprocess.run(['swiftc', str(p), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
