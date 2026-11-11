"""Exercise shipped day filtering, mixed-session selection and week boundaries."""
from pathlib import Path
import subprocess, tempfile
source = (Path(__file__).resolve().parents[1] / 'Views/Plan/PlanView.swift').read_text()
helper = source[source.index('enum TrainingSessionSelection {'):]
code = r'''
import Foundation
enum WorkoutType { case rest, gym, crossTraining, mobility, easyRun, intervals }
struct Workout {
    var id = UUID()
    var date: Date
    var workoutType: WorkoutType
    var isCompleted = false
}
'''+helper+r'''
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "America/Vancouver")!
let today = cal.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 12))!
let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
let run = Workout(date: today, workoutType: .intervals)
let gym = Workout(date: today, workoutType: .gym)
let next = Workout(date: tomorrow, workoutType: .easyRun)
let done = Workout(date: yesterday, workoutType: .easyRun, isCompleted: true)
let rest = Workout(date: today, workoutType: .rest)
let all = [gym, next, done, rest, run]
let day = TrainingSessionSelection.onDay(today, workouts: all, calendar: cal)
assert(Set(day.map(\.id)) == Set([gym.id, rest.id, run.id]))
let lobby = TrainingSessionSelection.lobby(workouts: all, flexible: false, today: today, calendar: cal)
assert(lobby.map(\.id) == [run.id, gym.id])
assert(TrainingSessionSelection.preferred(in: lobby, selectedID: gym.id, fallbackID: nil)?.id == gym.id)
assert(TrainingSessionSelection.preferred(in: lobby, selectedID: UUID(), fallbackID: nil)?.id == run.id)
let flex = TrainingSessionSelection.lobby(workouts: all, flexible: true, today: today, calendar: cal)
assert(Set(flex.map(\.id)) == Set([run.id, next.id, gym.id]))
assert(!flex.contains { $0.id == done.id })
assert(TrainingSessionSelection.onDay(tomorrow, workouts: all, calendar: cal).map(\.id) == [next.id])
assert(TrainingSessionSelection.preferred(in: [], selectedID: nil, fallbackID: nil) == nil)
let completed = Workout(date: today, workoutType: .intervals, isCompleted: true)
assert(TrainingSessionSelection.preferred(in: [completed, gym], selectedID: nil, fallbackID: nil)?.id == gym.id)
assert(TrainingSessionSelection.adjacentWeek(current: 13, weeks: [15, 13, 14], forward: true) == 14)
assert(TrainingSessionSelection.adjacentWeek(current: 14, weeks: [13, 14], forward: true) == nil)
assert(TrainingSessionSelection.adjacentWeek(current: 13, weeks: [13, 14], forward: false) == nil)
assert(TrainingSessionSelection.adjacentWeek(current: 15, weeks: [13, 15], forward: false) == 13)
let pastRest = Workout(date: yesterday, workoutType: .rest)
let todayRest = Workout(date: today, workoutType: .rest)
let futureRest = Workout(date: tomorrow, workoutType: .rest)
assert(TrainingSessionSelection.isDayComplete(yesterday, workouts: [pastRest], today: today, calendar: cal))
assert(!TrainingSessionSelection.isDayComplete(today, workouts: [todayRest], today: today, calendar: cal))
assert(!TrainingSessionSelection.isDayComplete(tomorrow, workouts: [futureRest], today: today, calendar: cal))
assert(!TrainingSessionSelection.isDayComplete(yesterday, workouts: [], today: today, calendar: cal))
assert(!TrainingSessionSelection.isDayComplete(yesterday, workouts: [pastRest, Workout(date: yesterday, workoutType: .easyRun)], today: today, calendar: cal))
assert(TrainingSessionSelection.isDayComplete(yesterday, workouts: [pastRest, done], today: today, calendar: cal))
// A Vancouver midnight workout is still the same scheduled day after travel to Hawaii.
var hawaii = Calendar(identifier: .gregorian)
hawaii.timeZone = TimeZone(identifier: "Pacific/Honolulu")!
let hawaiiWednesday = hawaii.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))!
let scheduledUTC = ISO8601DateFormatter().date(from: "2026-11-04T07:00:00Z")!
let travellingRun = Workout(date: scheduledUTC, workoutType: .easyRun)
assert(TrainingSessionSelection.onDay(hawaiiWednesday, workouts: [travellingRun], calendar: hawaii).map(\.id) == [travellingRun.id])
assert(TrainingSessionSelection.lobby(workouts: [travellingRun], flexible: false, today: hawaiiWednesday, calendar: hawaii).map(\.id) == [travellingRun.id])
print("PASS: selected-day scope, run/gym paging, completed/stale/empty selection, flexible schedule, week navigation boundaries")
'''
with tempfile.TemporaryDirectory(prefix='stride-sessions-') as tmp:
    path = Path(tmp) / 'main.swift'; path.write_text(code)
    binary = Path(tmp) / 'check'
    subprocess.run(['swiftc', str(path), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
