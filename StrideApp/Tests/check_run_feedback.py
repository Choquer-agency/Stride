"""Behavior checks for full-run speed capture and display-only graph smoothing."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]


def declaration(file, signature):
    source = (root / file).read_text()
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


code = "import SwiftUI\n"
code += declaration("ViewModels/RunViewModel.swift", "struct RunSpeedSample")
code += r"""
final class CaptureHarness {
    var isPaused = false
    var runStopped = false
    var speedKmh = 0.0
    var elapsedTime = 0.0
    var speedSamples: [RunSpeedSample] = []
"""
code += declaration("ViewModels/RunViewModel.swift", "private func recordSpeedSample").replace("private func", "func")
code += "\n}\n"
code += declaration("Views/Run/Components/PaceBandGraphView.swift", "enum RunGraphPath")
code += r"""
let capture = CaptureHarness()
capture.recordSpeedSample(10 / 3.6)
assert(capture.speedSamples.count == 1)
assert(abs(capture.speedSamples[0].kmh - 10) < 0.0001)
capture.elapsedTime = 0.4
capture.recordSpeedSample(11 / 3.6)
assert(capture.speedSamples.count == 1)
capture.elapsedTime = 1
capture.recordSpeedSample(0)
assert(capture.speedSamples.last!.kmh == 0)
capture.elapsedTime = 2
capture.recordSpeedSample(.nan)
capture.recordSpeedSample(.infinity)
capture.recordSpeedSample(-1)
assert(capture.speedSamples.count == 2)
capture.isPaused = true
capture.recordSpeedSample(3)
assert(capture.speedSamples.count == 2)
capture.isPaused = false
for second in 2...3600 {
    capture.elapsedTime = Double(second)
    capture.recordSpeedSample(3)
}
assert(capture.speedSamples.count == 3601)
assert(capture.speedSamples.first!.t == 0)
assert(capture.speedSamples.last!.t == 3600)
capture.runStopped = true
capture.elapsedTime = 3601
capture.recordSpeedSample(3)
assert(capture.speedSamples.count == 3601)

assert(RunGraphPath.rounded([]).isEmpty)
let original = (0..<100).map { index in
    CGPoint(x: Double(index) * 5, y: 100 + (index % 2 == 0 ? 10.0 : -10.0))
}
let filtered = RunGraphPath.displayPoints(original, bucketWidth: 1)
assert(original[10].y == 110) // Source measurements remain untouched.
assert(filtered.first!.x == original.first!.x)
assert(filtered.last! == original.last!) // Latest reading stays current.
let interior = filtered.dropFirst(3).dropLast(3).map(\.y)
assert(interior.max()! - interior.min()! < 2) // Actual noise reduction, not just round joins.
let repeated = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 10),
                CGPoint(x: 0, y: 20), CGPoint(x: 10, y: 20), CGPoint(x: 20, y: 30)]
let bucketed = RunGraphPath.displayPoints(repeated)
assert(bucketed.count == 3)
assert(bucketed.first!.y == 10)
for index in 1..<bucketed.count { assert(bucketed[index].x > bucketed[index - 1].x) }
assert(RunGraphPath.displayPoints([CGPoint(x: CGFloat.nan, y: 1)]).isEmpty)
var curves = 0
var lines = 0
RunGraphPath.rounded(original).forEach { item in
    if case .quadCurve = item { curves += 1 }
    if case .line = item { lines += 1 }
}
assert(curves > 1 && lines > 1) // Partial corner rounding preserves more of each edge.
let bounds = RunGraphPath.rounded(original).boundingRect
assert(bounds.minY >= 90 && bounds.maxY <= 110) // Curve cannot invent an overshoot.
print("PASS: full-run speed timeline, stop values, invalid samples, pause/finish gates, duplicate-distance buckets, noise reduction, smooth curves, and unchanged raw data")
"""
with tempfile.TemporaryDirectory(prefix="stride-run-feedback-") as temporary:
    source = Path(temporary) / "main.swift"
    source.write_text(code)
    binary = Path(temporary) / "check"
    subprocess.run(["swiftc", str(source), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
