"""Verify parsed karting exercise names resolve to complete, bundled technique guides."""
from pathlib import Path
import json
import struct
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Views/Plan/GymWorkoutPlayerView.swift').read_text()
catalog = source[source.index('private struct GymTechniqueGuide {'):]
code = (root / 'Services/GymSessionModel.swift').read_text() + '\n' + catalog
code += '''
let prescription = "Gym — Karting preparation — Bench-Supported DB Row (light, four reps in reserve) 2×15/side @ light DB load; Farmer Hold (relaxed shoulders) 2×30 sec @ light DB load; Seated Plate Steering (elbows bent, light plate) 2×30 sec @ 1.25 kg; Supported DB Wrist Extension (very light, no strain) 2×15 @ light DB load; Neck Isometric Front (gentle hand pressure, pain-free only) 2×5 sec @ BW; Neck Isometric Back (gentle hand pressure, pain-free only) 2×5 sec @ BW; Neck Isometric Left (gentle hand pressure, pain-free only) 2×5 sec @ BW; Neck Isometric Right (gentle hand pressure, pain-free only) 2×5 sec @ BW; Thoracic Rotation (gentle) 1×8/side @ BW"
var seen: Set<String> = []
for stage in GymSessionModel.stages(fromPrescription: prescription) {
    guard let guide = GymTechniqueGuide.forExercise(stage.exerciseName) else {
        fatalError("Missing guide: " + stage.exerciseName)
    }
    assert(!guide.cues.isEmpty && !guide.labels.isEmpty)
    if seen.insert(guide.slug).inserted {
        print(guide.slug + " " + String(guide.labels.count))
    }
}
assert(seen.count == 9)
assert(GymTechniqueGuide.forExercise("Bench-supported DB row")?.slug == "bench_supported_db_row")
assert(GymTechniqueGuide.forExercise("Neck Isometric Left")?.slug != GymTechniqueGuide.forExercise("Neck Isometric Right")?.slug)
assert(GymTechniqueGuide.forExercise("Back Squat") == nil) // retain the existing catalog fallback
'''
with tempfile.TemporaryDirectory() as directory:
    test = Path(directory) / 'main.swift'
    test.write_text(code)
    result = subprocess.run(['swift', str(test)], check=True, capture_output=True, text=True)

expected_assets = set()
for row in result.stdout.splitlines():
    slug, count = row.split()
    for step in range(1, int(count) + 1):
        name = f'{slug}_{step}'
        expected_assets.add(name)
        asset = root / 'Assets.xcassets' / f'{name}.imageset'
        metadata = json.loads((asset / 'Contents.json').read_text())
        image = asset / metadata['images'][0]['filename']
        header = image.read_bytes()[:24]
        assert header[:8] == b'\x89PNG\r\n\x1a\n', image
        width, height = struct.unpack('>II', header[16:24])
        assert min(width, height) >= 1024, (image, width, height)
assert len(expected_assets) == 13

# Verify these names are actually compiled into the app, not merely present on disk.
car = Path('/tmp/stride-fixes-build/Build/Products/Debug-iphonesimulator/StrideApp.app/Assets.car')
if car.exists():
    bundled = json.loads(subprocess.run(['xcrun', 'assetutil', '--info', str(car)],
                        check=True, capture_output=True, text=True).stdout)
    names = {entry.get('Name') for entry in bundled}
    assert expected_assets <= names, f'Missing bundled assets: {expected_assets - names}'
    print('PASS: all 9 parsed exercises map to 13 full-resolution images compiled into the app')
else:
    print('PASS: all 9 parsed exercises map to 13 full-resolution images; build required for bundle check')
