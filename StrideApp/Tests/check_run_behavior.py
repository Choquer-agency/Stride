"""Run focused Swift regression checks: python3 Tests/check_run_behavior.py."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]

def method(file, signature):
    source = (root / file).read_text()
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]

code = (root / "Services/PaceSmoother.swift").read_text()
code += """
struct Voice {
    func announceWorkoutCompleted() {}
}
final class CompletionHarness {
    var runStopped = false
    var isPaused = false
    var isStrideWorkout = false
    var isIntervalWorkout = false
    var intervalComplete = false
    var targetDistanceKm: Double?
    var targetDurationMinutes: Int?
    var distance = 0.0
    var elapsedTime = 0.0
    var workoutCompleted = false
    var stopCount = 0
    let voiceCoach = Voice()
    func stopRun() { runStopped = true; stopCount += 1 }
"""
code += method("ViewModels/RunViewModel.swift", "private func checkWorkoutCompletion()").replace("private func", "func")
code += "\n}\n"
code += method("Services/VoiceCoachService.swift", "static func spokenDistance(").replace("static func", "func")
code += """
let smoother = LiveSpeedSmoother()
let start = Date(timeIntervalSince1970: 0)
assert(abs(smoother.addSample(speedMps: 10 / 3.6, timestamp: start) - 360) < 0.001)
var values: [Double] = []
for tick in 1...100 {
    let speed = (tick % 2 == 0 ? 10.2 : 9.8) / 3.6
    values.append(smoother.addSample(speedMps: speed, timestamp: start.addingTimeInterval(Double(tick) * 0.4)))
}
assert(values.suffix(50).max()! - values.suffix(50).min()! < 3)
for tick in 101...116 {
    _ = smoother.addSample(speedMps: 12 / 3.6, timestamp: start.addingTimeInterval(Double(tick) * 0.4))
}
let changed = smoother.addSample(speedMps: 12 / 3.6, timestamp: start.addingTimeInterval(47))
assert(abs(changed - 300) < 2)
assert(smoother.addSample(speedMps: 0, timestamp: start.addingTimeInterval(48)) == 0)
assert(abs(smoother.addSample(speedMps: 10 / 3.6, timestamp: start.addingTimeInterval(49)) - 360) < 0.001)
assert(abs(smoother.addSample(speedMps: 12 / 3.6, timestamp: start.addingTimeInterval(60)) - 300) < 0.001)
assert(spokenDistance(2.5) == "2.5")
assert(spokenDistance(5.5) == "5.5")
assert(spokenDistance(10) == "10")
assert(spokenDistance(2.75) == "2.75")

let distanceRun = CompletionHarness()
distanceRun.targetDistanceKm = 5
distanceRun.targetDurationMinutes = 1
distanceRun.elapsedTime = 100
assert(!distanceRun.checkWorkoutCompletion())
distanceRun.distance = 5
assert(distanceRun.checkWorkoutCompletion())
assert(distanceRun.workoutCompleted && distanceRun.stopCount == 1)
assert(!distanceRun.checkWorkoutCompletion() && distanceRun.stopCount == 1)

let timedRun = CompletionHarness()
timedRun.targetDurationMinutes = 5
timedRun.elapsedTime = 299
assert(!timedRun.checkWorkoutCompletion())
timedRun.elapsedTime = 300
timedRun.isPaused = true
assert(!timedRun.checkWorkoutCompletion())
timedRun.isPaused = false
assert(timedRun.checkWorkoutCompletion())

let intervals = CompletionHarness()
intervals.isIntervalWorkout = true
intervals.targetDistanceKm = 5
intervals.distance = 6
assert(!intervals.checkWorkoutCompletion())
intervals.intervalComplete = true
assert(intervals.checkWorkoutCompletion())

let stridesRun = CompletionHarness()
stridesRun.isStrideWorkout = true
stridesRun.isIntervalWorkout = true
stridesRun.intervalComplete = true
stridesRun.targetDistanceKm = 6
stridesRun.distance = 5
assert(!stridesRun.checkWorkoutCompletion())
stridesRun.distance = 6
assert(stridesRun.checkWorkoutCompletion())
let freeRun = CompletionHarness()
freeRun.distance = 30
freeRun.elapsedTime = 10000
assert(!freeRun.checkWorkoutCompletion())
print("PASS: live pace, noise filtering, speed changes, stop/restart, gaps, fractional distance, and workout completion")
"""
with tempfile.TemporaryDirectory() as directory:
    test = Path(directory) / "main.swift"
    test.write_text(code)
    subprocess.run(["swift", str(test)], check=True)
