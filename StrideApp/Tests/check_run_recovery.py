"""Exercise actual Swift checkpoint encoding and deferred-auth methods."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]

def declaration(file, signature):
    source = (root / file).read_text()
    start = source.index(signature)
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

code = 'import Foundation\nenum WorkoutType: String, Codable { case longRun }\n'
for file, name in [
    ('Views/Run/RunView.swift', 'struct KilometerSplit'),
    ('ViewModels/RunViewModel.swift', 'struct RunSpeedSample'),
    ('ViewModels/RunViewModel.swift', 'struct RunResult'),
    ('ViewModels/RunViewModel.swift', 'enum RunRecoveryStore'),
]:
    code += declaration(file, name) + '\n'
code += '''
final class AuthHarness {
    var protectedWorkouts = Set<UUID>()
    var needsReauthentication = false
    var signOutCount = 0
    var currentUserID: String? = nil
    func signOut() {
        signOutCount += 1
        protectedWorkouts.removeAll()
        needsReauthentication = false
    }
'''
for name in ['func beginWorkoutProtection', 'func endWorkoutProtection', 'func handleUnauthorized']:
    code += declaration('Services/AuthService.swift', name) + '\n'
code += '''
}
let auth = AuthHarness()
let session = UUID(), otherSession = UUID()
auth.beginWorkoutProtection(session)
auth.beginWorkoutProtection(otherSession)
auth.handleUnauthorized()
assert(auth.signOutCount == 0 && auth.needsReauthentication)
auth.endWorkoutProtection(session)
assert(auth.signOutCount == 0)
auth.endWorkoutProtection(otherSession)
assert(auth.signOutCount == 1)
auth.handleUnauthorized()
assert(auth.signOutCount == 2)
let valid = AuthHarness()
valid.beginWorkoutProtection(session)
valid.endWorkoutProtection(session)
assert(valid.signOutCount == 0)

let owner = UUID().uuidString, otherOwner = UUID().uuidString
let split = KilometerSplit(kilometer: 12, pace: "6:11", time: "1:19:28", isFastest: false, diffFromFastest: nil)
let result = RunResult(sessionID: session, completedAt: Date(timeIntervalSince1970: 1792098000),
    distanceKm: 14, durationSeconds: 5478, avgPaceSecPerKm: 5478 / 14,
    kmSplits: [split], plannedWorkoutId: UUID(), plannedWorkoutTitle: "Medium-Long Run",
    plannedWorkoutType: .longRun, targetDistanceKm: 14, targetPaceDescription: "6:00–6:30",
    targetDurationMinutes: nil, dataSource: "bluetooth_ftms", treadmillBrand: "Assault",
    routeJSON: nil, elevationGainMeters: nil, elevationLossMeters: nil,
    avgHeartRate: 140, maxHeartRate: 150, hrSamplesJSON: "[{\\"t\\":1,\\"bpm\\":140}]",
    speedSamples: [RunSpeedSample(t: 1, kmh: 10)], totalPauseDurationSeconds: 20,
    completedPauseDurations: [20])
assert(RunRecoveryStore.load(ownerID: owner) == nil)
try RunRecoveryStore.save(result, ownerID: owner)
let coldAuth = AuthHarness()
coldAuth.currentUserID = owner
coldAuth.handleUnauthorized()
assert(coldAuth.signOutCount == 0 && coldAuth.protectedWorkouts.contains(session))
coldAuth.endWorkoutProtection(session)
assert(coldAuth.signOutCount == 1)
let loaded = RunRecoveryStore.load(ownerID: owner.lowercased())!.result
assert(loaded.sessionID == session && loaded.completedAt == result.completedAt)
assert(loaded.kmSplits.first!.id == split.id && loaded.kmSplits.first!.time == "1:19:28")
assert(loaded.durationSeconds == 5478 && loaded.distanceKm == 14)
assert(loaded.hrSamplesJSON == result.hrSamplesJSON && loaded.speedSamples.first!.kmh == 10)
assert(loaded.completedPauseDurations == [20] && loaded.plannedWorkoutId == result.plannedWorkoutId)
assert(RunRecoveryStore.load(ownerID: otherOwner) == nil)
assert(RunRecoveryStore.load(ownerID: "../invalid") == nil)
// A corrupt or truncated snapshot must fail closed, without crashing launch.
let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    .appendingPathComponent("stride-run-\\(owner.lowercased()).json")
try Data("{broken".utf8).write(to: url, options: .atomic)
assert(RunRecoveryStore.load(ownerID: owner) == nil)
RunRecoveryStore.remove(ownerID: owner)
RunRecoveryStore.remove(ownerID: owner)
assert(!FileManager.default.fileExists(atPath: url.path))
print("PASS: deferred sign-out, multiple protected sessions, normal sign-out, durable account-scoped run recovery, timestamps, split IDs, HR/speed/pause fidelity, corrupt-file handling, and cleanup")
'''
with tempfile.TemporaryDirectory(prefix='stride-run-recovery-') as temporary:
    source = Path(temporary) / 'main.swift'
    source.write_text(code)
    binary = Path(temporary) / 'check'
    subprocess.run(['swiftc', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
