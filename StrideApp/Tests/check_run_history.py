"""Verify timestamp alignment and missing-data behavior in completed-run history."""
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

code = 'import Foundation\n'
for file, signature in [('Models/Workout.swift', 'struct CodableKilometerSplit'),
                        ('ViewModels/RunViewModel.swift', 'struct CodableHRSample'),
                        ('Models/RunLog.swift', 'enum RunHistoryMetrics')]:
    code += declaration(file, signature) + '\n'
code += r'''
assert(RunHistoryMetrics.elapsedSeconds("6:25") == 385)
assert(RunHistoryMetrics.elapsedSeconds("01:19:28") == 4768)
assert(RunHistoryMetrics.elapsedSeconds("69:00") == 4140)
for invalid in ["", "6", "6:99", "1:60:00", "-1:20", "x:22", "6:", ":22"] {
    assert(RunHistoryMetrics.elapsedSeconds(invalid) == nil)
}
let samples = [CodableHRSample(t: 0, bpm: 100), CodableHRSample(t: 5, bpm: 200),
               CodableHRSample(t: 10, bpm: 140), CodableHRSample(t: 15, bpm: 160)]
assert(RunHistoryMetrics.averageHeartRate(samples, from: 0, to: 10) == 150)
assert(RunHistoryMetrics.averageHeartRate(samples, from: 5, to: 10) == 200)
assert(RunHistoryMetrics.averageHeartRate(samples, from: 10, to: 20) == 150)
assert(RunHistoryMetrics.averageHeartRate(Array(samples.reversed()), from: 0, to: 10) == 150)
let splits = [CodableKilometerSplit(kilometer: 1, pace: "0:10", time: "0:10", isFastest: true),
              CodableKilometerSplit(kilometer: 2, pace: "0:10", time: "0:20", isFastest: false)]
assert(RunHistoryMetrics.splitHeartRate(splits[0], allSplits: splits, samples: samples) == 150)
assert(RunHistoryMetrics.splitHeartRate(splits[1], allSplits: splits, samples: samples) == 150)
assert(RunHistoryMetrics.splitHeartRate(splits[1], allSplits: [splits[1]], samples: samples) == nil)
assert(RunHistoryMetrics.splitHeartRate(splits[0], allSplits: splits, samples: []) == nil)
// Expired readings cannot become invented heart rate in a later split.
assert(RunHistoryMetrics.averageHeartRate([.init(t: 0, bpm: 140)], from: 20, to: 30) == nil)
assert(RunHistoryMetrics.averageHeartRate([.init(t: .nan, bpm: 140), .init(t: 1, bpm: 0)], from: 0, to: 10) == nil)
assert(RunHistoryMetrics.averageHeartRate(samples, from: 20, to: 10) == nil)
assert(RunHistoryMetrics.averageHeartRate(samples, from: 0, to: .infinity) == nil)
// Weighted elapsed-time averaging avoids bias when samples have irregular spacing.
assert(RunHistoryMetrics.averageHeartRate([.init(t: 0, bpm: 100), .init(t: 1, bpm: 200)], from: 0, to: 10) == 190)
print("PASS: elapsed time parsing, exact split boundaries, time-weighted HR, unsorted readings, missing splits, empty/invalid samples, stale gaps, and irregular sampling")
'''
with tempfile.TemporaryDirectory(prefix='stride-run-history-') as directory:
    path = Path(directory) / 'main.swift'
    path.write_text(code)
    binary = Path(directory) / 'check'
    subprocess.run(['swiftc', str(path), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
