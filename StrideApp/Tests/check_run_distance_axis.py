"""Compile the production distance-axis helper and verify representative runs."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "Views/Run/Components/HeartRateGraphView.swift").read_text()
helper = source[source.index("struct RunDistanceAxis {"):]
stubs = """
import Foundation
struct RoutePoint {
    let latitude: Double
    let longitude: Double
    let timestamp: Double
}
struct RunSpeedSample {
    let t: Double
    let kmh: Double
}
"""
checks = """
let treadmill = RunDistanceAxis(distanceKm: 10, duration: 3600, route: [],
    treadmillSpeeds: [RunSpeedSample(t: 0, kmh: 10), RunSpeedSample(t: 1800, kmh: 10),
        RunSpeedSample(t: 3600, kmh: 10)])
assert(abs(treadmill.km(at: 1800) - 5) < 0.01)
assert(treadmill.ticks == [0, 2, 4, 6, 8, 10])
let marathon = RunDistanceAxis(distanceKm: 42.2, duration: 15000, route: [], treadmillSpeeds: [])
assert(marathon.ticks.first == 0 && marathon.ticks.last == 42.2)
assert(marathon.ticks.contains(40) && marathon.label(for: 42.2) == "42.2")
let route = RunDistanceAxis(distanceKm: 2, duration: 1200,
    route: [RoutePoint(latitude: 49, longitude: -123, timestamp: 0),
            RoutePoint(latitude: 49.009, longitude: -123, timestamp: 600),
            RoutePoint(latitude: 49.018, longitude: -123, timestamp: 1200)], treadmillSpeeds: [])
assert(abs(route.km(at: 600) - 1) < 0.02)
assert(route.km(at: 1200) == 2)
let fallback = RunDistanceAxis(distanceKm: 8, duration: 2400, route: [], treadmillSpeeds: [])
assert(abs(fallback.km(at: 1200) - 4) < 0.01)
print("PASS: shared distance axis, treadmill, GPS, fallback, and readable ticks")
"""
with tempfile.TemporaryDirectory() as directory:
    swift = Path(directory) / "main.swift"
    executable = Path(directory) / "axis-test"
    swift.write_text(stubs + helper + checks)
    subprocess.run(["swiftc", str(swift), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
