"""Replay the failed-recording copy repair against actual production code."""
from pathlib import Path
import subprocess
import tempfile
source = (Path(__file__).resolve().parents[1] / 'Services/RunPullService.swift').read_text()
start = source.index('    private func repairFailedRecordingCopies(')
opening = source.index('{', start)
end, depth = opening + 1, 1
while depth:
    depth += (source[end] == '{') - (source[end] == '}')
    end += 1
method = source[start:end].replace('private func', 'func')
code = r"""import Foundation
struct ServerRunDTO {
 var id: String
 var distanceKm: Double
 var durationSeconds: Double
 var completedAtDate: Date?
 var avgPaceSecPerKm = 390.0
 var kmSplitsJson: String? = nil
 var completionScore: Int? = nil
 var plannedWorkoutTitle: String? = nil
}
final class RunLog {
 var id: UUID
 var distanceKm: Double
 var durationSeconds: Double
 var completedAt: Date
 var avgPaceSecPerKm = 390.0
 var kmSplitsJSON: String? = nil
 var completionScore: Int? = nil
 var plannedWorkoutTitle: String? = nil
 var syncedToServer = true
 init(_ id: UUID, _ distance: Double, _ duration: Double, _ date: Date) {
  self.id = id; distanceKm = distance; durationSeconds = duration; completedAt = date
 }
}
final class Harness {
""" + method + r"""
}
let date = Date(timeIntervalSince1970: 1792350000)
let failedID = UUID(), realID = UUID()
let failed = ServerRunDTO(id: failedID.uuidString, distanceKm: 0.04, durationSeconds: 83006, completedAtDate: date)
let real = ServerRunDTO(id: realID.uuidString, distanceKm: 24, durationSeconds: 9356, completedAtDate: date)
let copy = RunLog(failedID, 24, 9356, date)
let original = RunLog(realID, 24, 9356, date)
let h = Harness(), calendar = Calendar.current
assert(!h.repairFailedRecordingCopies(serverRuns: [failed, real], localLogs: [copy], calendar: calendar))
assert(copy.distanceKm == 24) // Never discard the only local full recording.
assert(h.repairFailedRecordingCopies(serverRuns: [failed, real], localLogs: [copy, original], calendar: calendar))
assert(copy.distanceKm == 0.04 && copy.durationSeconds == 83006)
assert(original.distanceKm == 24 && original.durationSeconds == 9356)
assert(!h.repairFailedRecordingCopies(serverRuns: [failed, real], localLogs: [copy, original], calendar: calendar))
let distinct = RunLog(UUID(), 24, 9356, date)
assert(!h.repairFailedRecordingCopies(serverRuns: [failed, real], localLogs: [distinct, original], calendar: calendar))
assert(distinct.distanceKm == 24) // Same-distance independent runs are preserved.
print("PASS: confirmed duplicate recovery copy repaired, real run preserved, idempotence and ambiguous records protected")
"""
assert 'if run.distanceKm >= 0.2, !hasRealLocal,' in source
with tempfile.TemporaryDirectory() as directory:
    file = Path(directory) / 'main.swift'
    file.write_text(code)
    subprocess.run(['swift', str(file)], check=True)
