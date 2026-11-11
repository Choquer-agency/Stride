"""Exercise gym recovery's durable, account/workout/prescription-scoped checkpoints."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
source = (root / 'Services/GymSessionModel.swift').read_text()
source += r'''
let owner = UUID().uuidString, otherOwner = UUID().uuidString
let workout = UUID(), otherWorkout = UUID(), session = UUID()
let started = Date(timeIntervalSince1970: 1792188000)
let prescription = "Back Squat 3×8 @ 60 kg; Plank 3×30 sec @ BW"
let saved = GymSessionRecoveryStore.Checkpoint(ownerID: owner, workoutID: workout,
    prescription: prescription, sessionID: session, sessionStart: started,
    stageIndex: 4, remainingSeconds: 17, weights: ["Back Squat": 65])
assert(GymSessionRecoveryStore.load(ownerID: owner, workoutID: workout, prescription: prescription, stageCount: 6) == nil)
try GymSessionRecoveryStore.save(saved)
let loaded = GymSessionRecoveryStore.load(ownerID: owner.lowercased(), workoutID: workout,
    prescription: prescription, stageCount: 6)!
assert(loaded.stageIndex == 4 && loaded.remainingSeconds == 17)
assert(loaded.weights["Back Squat"] == 65 && loaded.sessionID == session && loaded.sessionStart == started)
assert(GymSessionRecoveryStore.load(ownerID: otherOwner, workoutID: workout, prescription: prescription, stageCount: 6) == nil)
assert(GymSessionRecoveryStore.load(ownerID: owner, workoutID: otherWorkout, prescription: prescription, stageCount: 6) == nil)
assert(GymSessionRecoveryStore.load(ownerID: owner, workoutID: workout, prescription: "Changed plan", stageCount: 6) == nil)
assert(GymSessionRecoveryStore.load(ownerID: owner, workoutID: workout, prescription: prescription, stageCount: 3) == nil)
assert(GymSessionRecoveryStore.load(ownerID: "../invalid", workoutID: workout, prescription: prescription, stageCount: 6) == nil)
// All exercises done still requires an explicit Finish; the draft survives until then.
try GymSessionRecoveryStore.save(.init(ownerID: owner, workoutID: workout,
    prescription: prescription, sessionID: session, sessionStart: started,
    stageIndex: 6, remainingSeconds: 0, weights: ["Back Squat": 65]))
assert(GymSessionRecoveryStore.load(ownerID: owner, workoutID: workout, prescription: prescription, stageCount: 6)!.stageIndex == 6)
// Malformed data cannot crash the workout player or initialize arbitrary progress.
let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    .appendingPathComponent("stride-gym-\(owner.lowercased())-\(workout.uuidString.lowercased()).json")
try Data("{truncated".utf8).write(to: url, options: .atomic)
assert(GymSessionRecoveryStore.load(ownerID: owner, workoutID: workout, prescription: prescription, stageCount: 6) == nil)
GymSessionRecoveryStore.remove(ownerID: owner, workoutID: workout)
GymSessionRecoveryStore.remove(ownerID: owner, workoutID: workout)
assert(!FileManager.default.fileExists(atPath: url.path))
print("PASS: durable gym progress, hold countdown, weights, stable session/start, account/workout isolation, changed-plan protection, bounds, pending finish, corrupt-file handling, and discard cleanup")
'''
with tempfile.TemporaryDirectory(prefix='stride-gym-recovery-') as directory:
    path = Path(directory) / 'main.swift'
    path.write_text(source)
    binary = Path(directory) / 'check'
    subprocess.run(['swiftc', str(path), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
