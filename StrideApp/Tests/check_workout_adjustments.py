"""Run parser and interval-engine regressions with the actual Swift source."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
def method(signature):
    source = (root / 'ViewModels/RunViewModel.swift').read_text()
    start = source.index(signature)
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end].replace('private func', 'func')

code = (root / 'Services/IntervalWorkoutParser.swift').read_text()
code += (root / 'Services/GymSessionModel.swift').read_text()
code += '''
struct UIImpactFeedbackGenerator {
    enum Style { case heavy }
    init(style: Style) {}
    func impactOccurred() {}
}
struct UINotificationFeedbackGenerator {
    enum Kind { case success }
    func notificationOccurred(_ kind: Kind) {}
}
struct VoiceCoachService {
    static func spokenDistance(_ km: Double) -> String { String(km) }
    var announcements = 0
    mutating func announcePacePhase(paceText: String, distanceKm: Double) { announcements += 1 }
}
final class Engine {
    var progressionSegments: [IntervalSegment] = [], progressionIndex = 0
    var lastPacePhaseChangeTime = -Double.infinity
    var pacePhaseAnnouncement: String?, targetPaceDescription: String?
    var voiceCoach = VoiceCoachService()
    var candidateZone = Zone.noTarget, candidateZoneSince = 0.0, distanceOnlyMode = false
    var isStrideWorkout = false
    var basePaceMin: Double?, basePaceMax: Double?
    var isPaused = false, runStopped = false, intervalComplete = false
    var intervalSegments: [IntervalSegment] = []
    var isIntervalWorkout: Bool { !intervalSegments.isEmpty }
    var intervalIndex = 0, lastCountdownTick = -1
    var elapsedTime = 0.0, distance = 0.0
    var segmentStartTime = 0.0, segmentStartDistance = 0.0
    var intervalPhaseRemaining = 0.0, intervalPhaseDistanceDone = 0.0
    var targetPaceMinSec: Double?, targetPaceMaxSec: Double?
    enum Zone { case noTarget }
    var paceZone = Zone.noTarget
'''
for signature in ['private func updateProgressionPace()', 'private func updateIntervalEngine()', 'private func advanceIntervalSegment()', 'private func applyIntervalPace(']:
    code += "\n" + method(signature) + "\n"
code += '''
}
let strides = IntervalWorkoutParser.strides("6 km with 4 × 20 sec strides included in the final 2 km", totalKm: 6, easyPace: "6:00–6:30")
assert(strides.count == 12 && strides[0].distanceKm == 4)
assert(strides[1].durationSec == 3 && strides[2].durationSec == 20)
assert(strides[3].durationSec == 60 && strides[2].paceBounds == nil)
assert(IntervalWorkoutParser.strides("Easy run", totalKm: 6, easyPace: nil).isEmpty)
let timed = IntervalWorkoutParser.parse("Warm-up: 2.5 km at 6:00–6:30/km; Main set: 10 × 1 min at roughly 4:45–5:00/km effort (RPE 7) with 1 min easy float between; Cool-down: 2.5 km at 6:00–6:30/km")
assert(timed.count == 21)
assert(timed[1].durationSec == 60 && timed[2].durationSec == 60)
let distance = IntervalWorkoutParser.parse("Warm-up: 2 km at 6:00/km (easy)\\nMain set: 3 × 2 km at 4:50/km (threshold) with 90 sec jog at 6:30/km between reps\\nCool-down: 2 km at 6:00/km (easy)")
assert(distance.count == 7)
assert(distance[1].distanceKm == 2 && distance[2].durationSec == 90)
assert(distance[2].paceText == "6:30")
assert(distance[0].paceBounds!.min == 345)
let metres = IntervalWorkoutParser.parse("Warm up: 10 minutes at 6:00/km; 6 x 400 m @ 4:30-4:45/km with 200 m jog; Cool down: 5 min at 6:30/km")
assert(metres.count == 13 && metres[0].durationSec == 600)
assert(metres[1].distanceKm == 0.4 && metres[2].distanceKm == 0.2)
let decimal = IntervalWorkoutParser.parse("4 X 1.5 MIN at 5:00/km with 30 SEC rest")
assert(decimal.count == 7 && decimal[0].durationSec == 90)
let tempo = IntervalWorkoutParser.parse("Total: 11 km\\nWarm-up: 2.5 km at 6:00–6:30/km\\nMain set: 6 km continuous at 5:00/km (RPE 7)\\nCool-down: 2.5 km at 6:00–6:30/km")
assert(tempo.count == 3 && tempo[1].distanceKm == 6 && tempo[1].paceText == "5:00")
let cruise = IntervalWorkoutParser.parse("Total: 9 km\\nWarm-up: 2 km at 6:00–6:30/km\\nMain set: 3 × 1.5 km at 5:00/km (RPE 7) with 90 sec jog at 6:30/km (0.25 km) between reps\\nCool-down: 2 km at 6:00–6:30/km")
assert(cruise.count == 7 && cruise[1].distanceKm == 1.5 && cruise[2].durationSec == 90)
assert(IntervalWorkoutParser.parse("Easy Run + Strides — Total: 7 km at 6:00–6:30/km, with 4 × 20 sec strides included in the final 2 km").isEmpty)
assert(IntervalWorkoutParser.parse("Easy run 9 km at 6:00/km").isEmpty)
assert(IntervalWorkoutParser.parse("6 x 1 min at 5:00/km").isEmpty)
assert(IntervalWorkoutParser.parse("0 x 1 min at 5:00/km with 1 min jog").isEmpty)
assert(IntervalWorkoutParser.parse(nil).isEmpty)
assert(IntervalWorkoutParser.parse("Warm-up: easy; 4 x 1 min at 5:00/km with 1 min jog").isEmpty)
assert(IntervalWorkoutParser.parse("4 x 1 min at 5:00/km with 1 min jog; 3 x 2 min at 4:30/km with 1 min jog").isEmpty)

let progression = IntervalWorkoutParser.progression("Long Run with MP Finish — Total: 24 km. First 21 km at 6:00–6:30/km, final 3 km at 5:30/km (adjusted MP, RPE 5–6).", totalKm: 24)
assert(progression.count == 2 && progression[0].distanceKm == 21)
assert(progression[0].paceBounds!.min == 360 && progression[1].paceBounds!.min == 315)
assert(IntervalWorkoutParser.progression("First 21 km at 6:00/km, final 3 km at 5:30/km", totalKm: 23).isEmpty)
assert(IntervalWorkoutParser.progression("Easy 24 km at 6:00/km", totalKm: 24).isEmpty)
let progressionEngine = Engine()
progressionEngine.progressionSegments = progression
progressionEngine.targetPaceMinSec = 360
progressionEngine.targetPaceMaxSec = 390
progressionEngine.distance = 20.99
progressionEngine.updateIntervalEngine()
assert(progressionEngine.targetPaceMinSec == 360 && progressionEngine.voiceCoach.announcements == 0)
progressionEngine.isPaused = true
progressionEngine.distance = 21.02
progressionEngine.updateIntervalEngine()
assert(progressionEngine.progressionIndex == 0)
progressionEngine.isPaused = false
progressionEngine.updateIntervalEngine()
assert(progressionEngine.targetPaceMinSec == 315 && progressionEngine.targetPaceMaxSec == 345)
assert(progressionEngine.targetPaceDescription == "5:30" && progressionEngine.pacePhaseAnnouncement != nil)
assert(progressionEngine.voiceCoach.announcements == 1 && !progressionEngine.intervalComplete)
progressionEngine.distance = 24
progressionEngine.updateIntervalEngine()
assert(progressionEngine.voiceCoach.announcements == 1)
let engine = Engine()
engine.intervalSegments = decimal
engine.elapsedTime = 89
engine.updateIntervalEngine()
assert(engine.intervalIndex == 0 && engine.intervalPhaseRemaining == 1)
engine.isPaused = true
engine.elapsedTime = 100
engine.updateIntervalEngine()
assert(engine.intervalIndex == 0)
engine.isPaused = false
engine.updateIntervalEngine()
assert(engine.intervalIndex == 1 && engine.intervalPhaseRemaining == 20)
assert(engine.targetPaceMinSec == nil)
engine.elapsedTime = 125
engine.updateIntervalEngine()
assert(engine.intervalIndex == 2 && engine.intervalPhaseRemaining == 85)
assert(engine.targetPaceMinSec == 285)
engine.elapsedTime = 1000
engine.updateIntervalEngine()
assert(engine.intervalComplete)
let strideEngine = Engine()
strideEngine.isStrideWorkout = true
strideEngine.basePaceMin = 360
strideEngine.basePaceMax = 390
strideEngine.intervalSegments = strides
strideEngine.distance = 4
strideEngine.updateIntervalEngine()
assert(strideEngine.intervalIndex == 1 && strideEngine.intervalPhaseRemaining == 3)
strideEngine.elapsedTime = 3
strideEngine.updateIntervalEngine()
assert(strideEngine.intervalIndex == 2 && strideEngine.intervalPhaseRemaining == 20)
strideEngine.elapsedTime = 23
strideEngine.updateIntervalEngine()
assert(strideEngine.intervalIndex == 3 && strideEngine.intervalPhaseRemaining == 60)
strideEngine.elapsedTime = 300
strideEngine.updateIntervalEngine()
assert(strideEngine.intervalComplete && strideEngine.targetPaceMinSec == 360)
let distEngine = Engine()
distEngine.intervalSegments = distance
distEngine.distance = 1.99
distEngine.updateIntervalEngine()
assert(distEngine.intervalIndex == 0)
distEngine.distance = 2
distEngine.updateIntervalEngine()
assert(distEngine.intervalIndex == 1 && distEngine.targetPaceMinSec == 275)
distEngine.distance = 4
distEngine.updateIntervalEngine()
assert(distEngine.intervalIndex == 2 && distEngine.intervalPhaseRemaining == 90)
assert(distEngine.targetPaceMinSec == 375)

for (item, unit) in [("DB Split Squat 3×8 @ 20 kg/hand", "lb each"),
                     ("Kettlebell swing 3×10 @ 25 kg", "lb"),
                     ("Medicine ball twist 3×12 @ 8 lbs", "kg"),
                     ("Med Ball twist 3×12 @ 8 lb", "kg"),
                     ("Back squat 3×8 @ 40 kg", "kg total incl. bar")] {
    let exercise = GymSessionModel.parseExercise(item)
    assert(exercise.weightSuffix == unit, item)
    assert(exercise.weightKg != nil, item)
}
assert(abs(GymSessionModel.parseExercise("DB Split Squat 3×8 @ 20 kg/hand").weightKg! - 45 * GymSessionModel.kilogramsPerPound) < 0.00001)
assert(abs(GymSessionModel.parseExercise("Barbell press 3×8 @ 40 lb").weightKg! - 40 * GymSessionModel.kilogramsPerPound) < 0.00001)
assert(GymSessionModel.equipmentUnits(in: "Landmine press 3×8 @ 20 kg") == "Landmine press 3×8 @ 20 kg plates on loaded end")
print("PASS: timed/distance intervals, recoveries, phase targets, pause, delayed ticks, completion, and equipment units")
'''
with tempfile.TemporaryDirectory() as directory:
    test = Path(directory) / 'main.swift'
    test.write_text(code)
    env = dict(os.environ, CLANG_MODULE_CACHE_PATH='/tmp/stride-swift-module-cache')
    subprocess.run(['swift', str(test)], check=True, env=env)
