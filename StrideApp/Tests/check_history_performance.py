"""Regression checks for bounded history charts and day-scroll targets."""
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

code = 'import SwiftUI\n'
for file, signature in [
    ('ViewModels/RunViewModel.swift', 'struct CodableHRSample'),
    ('ViewModels/RunViewModel.swift', 'struct RunSpeedSample'),
    ('Views/Run/Components/PaceBandGraphView.swift', 'enum RunGraphPath'),
    ('Views/Run/Components/HeartRateGraphView.swift', 'enum RunTimelineData'),
    ('Views/Plan/PlanView.swift', 'enum PlanDayScrollTarget'),
]:
    code += declaration(file, signature) + '\n'
code += r'''
let heart = (0..<15000).map { CodableHRSample(t: Double($0), bpm: 130 + $0 % 20) }
let speed = (0..<15000).map { RunSpeedSample(t: Double($0), kmh: 9 + Double($0 % 10) / 10) }
let json = String(data: try JSONEncoder().encode(heart), encoding: .utf8)!
let started = Date()
let hr = RunTimelineData.heartRate(json: json, target: 130...147)
let pace = RunTimelineData.speed(samples: speed, target: 9.2...10)
let elapsed = Date().timeIntervalSince(started)
assert(hr.points.count <= 240 && pace.points.count <= 240)
assert(hr.points.first!.x == 0 && abs(hr.points.last!.x - 14999 / 60.0) < 0.001)
assert(pace.points.first!.x == 0 && abs(pace.points.last!.x - 14999 / 60.0) < 0.001)
assert(hr.domain.contains(130) && hr.domain.contains(147))
assert(pace.domain.contains(9.2) && pace.domain.contains(10))
assert(elapsed < 2) // Preparing a four-hour recording must not introduce multi-second stalls.
let empty = RunTimelineData.heartRate(json: "", target: nil)
assert(empty.points.isEmpty && empty.domain.lowerBound.isFinite)
let bad = RunTimelineData.speed(samples: [.init(t: .nan, kmh: 10), .init(t: 0, kmh: .infinity)], target: nil)
assert(bad.points.isEmpty && bad.domain.lowerBound.isFinite)
let stopped = RunTimelineData.speed(samples: [.init(t: 0, kmh: 10), .init(t: 1, kmh: 0)], target: nil)
assert(stopped.domain.contains(0) && stopped.points.last!.y == 0)
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "America/Vancouver")!
let days = (12...18).map { calendar.date(from: DateComponents(year: 2026, month: 10, day: $0, hour: 12))! }
assert(PlanDayScrollTarget.date(in: days, today: days[5], calendar: calendar) == days[5])
assert(PlanDayScrollTarget.date(in: days, today: days[6], calendar: calendar) == days[6])
assert(PlanDayScrollTarget.date(in: days.reversed(), today: days[0].addingTimeInterval(-86400), calendar: calendar) == days[0])
assert(PlanDayScrollTarget.date(in: [], today: days[6], calendar: calendar) == nil)
print("PASS: four-hour HR/speed preparation in \(Int(elapsed * 1000)) ms, bounded charts, target domains, stop/invalid/empty recordings, and Saturday/Sunday return-to-today targets")
'''
with tempfile.TemporaryDirectory(prefix='stride-history-performance-') as directory:
    source = Path(directory) / 'main.swift'
    source.write_text(code)
    binary = Path(directory) / 'check'
    subprocess.run(['swiftc', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
