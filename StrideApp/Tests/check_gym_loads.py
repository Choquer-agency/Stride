"""Run pure Swift regressions for equipment units, load basis, and weighted holds."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
code = (root / "Services/GymSessionModel.swift").read_text() + r'''
func near(_ a: Double?, _ b: Double) { assert(a != nil && abs(a! - b) < 0.000001) }
let pounds = GymSessionModel.kilogramsPerPound
let db = GymSessionModel.parseExercise("DB Split Squat 3×8/side @ 20 kg/hand")
near(db.weightKg, 45 * pounds) // actual conversion followed by available 5 lb rounding
assert(db.weightSuffix == "lb each")
assert(db.perSide)
let oddPounds = GymSessionModel.parseExercise("Goblet squat 3×10 @ 12 lb DB")
near(oddPounds.weightKg, 10 * pounds)
near(GymSessionModel.parseExercise("Supported DB Wrist Extension 2×15 @ light DB load").weightKg, 5 * pounds)
near(GymSessionModel.parseExercise("Bench-Supported DB Row 2×15/side @ light DB load").weightKg, 5 * pounds)
assert(GymSessionModel.equipmentUnits(in: "Bench-Supported DB Row 2×15/side @ light DB load").contains("5 lb each (starting load)"))
let total = GymSessionModel.parseExercise("Back Squat 3×8 @ 40 kg")
near(total.weightKg, 40)
assert(total.weightSuffix == "kg total incl. bar")
near(GymSessionModel.barbellPlateKg(totalKg: 40, barKg: 20), 10)
near(GymSessionModel.barbellPlateKg(totalKg: 40, barKg: 15), 12.5)
near(GymSessionModel.barbellPlateKg(totalKg: 10, barKg: 20), 0)
let normalizedTotal = GymSessionModel.equipmentUnits(in: "Back Squat 3×8 @ 40 kg")
assert(GymSessionModel.parseExercise(normalizedTotal).weightSuffix == "kg total incl. bar")
assert(GymSessionModel.equipmentUnits(in: normalizedTotal) == normalizedTotal)
let side = GymSessionModel.parseExercise("Barbell RDL 3×8 @ 20 kg per side")
near(side.weightKg, 20)
assert(side.weightSuffix == "kg per side (plates only)")
assert(GymSessionModel.equipmentUnits(in: "Back Squat 3×8 @ 40 kg").contains("kg per side +"))
assert(GymSessionModel.equipmentUnits(in: "DB Split Squat 3×8 @ 20 kg/hand").contains("45 lb each"))
let holds = GymSessionModel.stages(fromPrescription: "Gym — Farmer Hold 2×30 sec @ light DB load; Side Plank 2×30 sec/side @ BW")
let farmers = holds.filter { $0.exerciseName == "Farmer Hold" }
assert(farmers.count == 2)
for hold in farmers {
    guard case .timed(let seconds) = hold.kind else { fatalError("Hold must stay timed") }
    assert(seconds == 30)
    near(hold.loadKg, 5 * pounds)
    assert(hold.loadSuffix == "lb each")
}
let planks = holds.filter { $0.exerciseName == "Side Plank" }
assert(planks.count == 4 && planks.allSatisfy { $0.loadKg == nil })
let bw = GymSessionModel.parseExercise("DB squat 3×8 @ BW")
assert(bw.weightKg == nil && bw.weightSuffix == "BW")
assert(GymSessionModel.isDumbbell("Single-leg RDL"))
assert(!GymSessionModel.isDumbbell("Barbell split squat"))
assert(!GymSessionModel.isDumbbell("Kettlebell goblet squat"))
let single = GymSessionModel.parseExercise("Single-leg RDL 3×8 @ 10 lb DB")
assert(single.weightSuffix == "lb each")
near(GymSessionModel.parseExercise("Medicine ball twist 3×10 @ 8 lb").weightKg, 8 * pounds)
print("PASS: canonical conversion, 5 lb increments, per-side bar math, qualitative DB starts, timed weighted holds, bodyweight")
'''
with tempfile.TemporaryDirectory() as directory:
    test = Path(directory) / "main.swift"
    test.write_text(code)
    subprocess.run(["swift", str(test)], check=True)

player = (root / "Views/Plan/GymWorkoutPlayerView.swift").read_text()
assert 'gym_weight_overrides_canonical_kg_v2' in player
assert 'stage.loadKg' in player and 'Loads used:' in player
log = (root / "Views/Strength/StrengthSessionView.swift").read_text()
assert 'd["weight_kg"] = GymSessionModel.roundedDumbbellKg' in log
