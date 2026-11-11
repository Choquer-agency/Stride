"""Verify new history fields survive saving and reopening a real SwiftData store."""
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

code = 'import Foundation\nimport SwiftData\nenum WorkoutType: String { case easyRun = "easy_run" }\n'
code += declaration('Models/Workout.swift', 'struct CodableKilometerSplit') + '\n'
code += declaration('ViewModels/RunViewModel.swift', 'struct CodableHRSample') + '\n'
code += (root / 'Models/RunLog.swift').read_text()
code += r'''
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("stride-history-store-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let config = ModelConfiguration(url: directory.appendingPathComponent("history.store"))
let id = UUID()
func writeHistory() throws {
    let container = try ModelContainer(for: RunLog.self, configurations: config)
    let context = ModelContext(container)
    let log = RunLog(distanceKm: 6, durationSeconds: 2366, avgPaceSecPerKm: 2366 / 6,
        avgHeartRate: 142, hrSamplesJSON: "[{\"t\":0,\"bpm\":142}]", shoeName: "Indoor Zoom Fly")
    log.id = id
    log.speedSamplesJSON = "[{\"t\":0,\"kmh\":9.4},{\"t\":10,\"kmh\":9.5}]"
    log.coachNotes = "Keep the next easy run conversational."
    context.insert(log)
    context.insert(RunLog(distanceKm: 4, durationSeconds: 1620, avgPaceSecPerKm: 405))
    try context.save()
}
try writeHistory()
let reopened = try ModelContainer(for: RunLog.self, configurations: config)
let records = try ModelContext(reopened).fetch(FetchDescriptor<RunLog>())
assert(records.count == 2)
let restored = records.first { $0.id == id }!
assert(restored.speedSamplesJSON!.contains("9.4"))
assert(restored.coachNotes == "Keep the next easy run conversational.")
assert(restored.shoeName == "Indoor Zoom Fly" && restored.avgHeartRate == 142)
let legacy = records.first { $0.id != id }!
assert(legacy.speedSamplesJSON == nil && legacy.coachNotes == nil)
print("PASS: persisted/reopened SwiftData history preserves speed, coach notes, shoes and HR; missing optional history remains nil")
'''
with tempfile.TemporaryDirectory(prefix='stride-history-storage-') as directory:
    path = Path(directory) / 'main.swift'
    path.write_text(code)
    binary = Path(directory) / 'check'
    subprocess.run(['swiftc', str(path), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
