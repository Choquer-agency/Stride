"""Replay Michelle's plan through the real parser and completion-only backfill."""
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

code = '''import Foundation
enum WorkoutType: String {
    case easyRun, longRun, tempoRun, intervals, hillRepeats, fartlek, recovery, race, drills, rest, gym, crossTraining, mobility
    var displayName: String { rawValue }
'''
code += declaration('Models/Enums.swift', 'var isRunnable: Bool') + '\n}\n'
code += (root / 'Services/PlanParser.swift').read_text() + '\n'
code += '''
final class Workout {
    let date: Date; let workoutType: WorkoutType; let title: String; let details: String?
    var isCompleted = false; var isCoachConfirmedCompletion = false
    var completedAt: Date?; var notes: String?
    var actualDistanceKm: Double?; var actualDurationSeconds: Double?; var actualAvgPaceSecPerKm: Double?
    init(_ value: ParsedWorkout) { date = value.date; workoutType = value.workoutType; title = value.title; details = value.details }
'''
code += declaration('Models/Workout.swift', 'var isPeloton: Bool') + '\n'
code += declaration('Models/Workout.swift', 'var isPelotonStrength: Bool') + '\n}\n'
code += '''
final class Week {
    let weekNumber: Int; let workouts: [Workout]
    init(_ value: ParsedWeek) { weekNumber = value.weekNumber; workouts = value.workouts.map(Workout.init) }
}
final class TrainingPlan {
    let weeks: [Week]; let rawPlanContent: String?
    init(_ values: [ParsedWeek], _ content: String) { weeks = values.map(Week.init); rawPlanContent = content }
}
'''
code += declaration('Services/PlanSyncService.swift', 'enum CoachReportedCompletions') + '\n'
code += r'''
let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
let start = formatter.date(from: "2026-09-14")!, race = formatter.date(from: "2027-01-17")!
let now = formatter.date(from: "2026-10-18")!
let content = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
let parsed = PlanParser.parse(content: content, startDate: start, raceDate: race)
assert(parsed.count == 18)
let peak = parsed.first { $0.weekNumber == 15 }!.workouts.first { $0.workoutType == .longRun }!
assert(peak.distanceKm == 18, "Coaching mention of the future 21.1 km race must not override Total: 18 km")
let raceRun = parsed.flatMap(\.workouts).filter { $0.workoutType == .race }
assert(raceRun.count == 1 && raceRun[0].distanceKm == 21.1 && raceRun[0].date == race)
assert(parsed.first { $0.weekNumber == 12 }!.workouts.contains { $0.workoutType == .longRun && $0.distanceKm == 14 })
for week in parsed { assert(week.workouts.filter { $0.workoutType.isRunnable }.count == 3, "Every week has three runs, including the restless-leg shake-out") }
let prose = "WEEK 1 [PEAK]\n- Saturday: Long Run – race day is still ahead; later you will run 21.1 km. Total: 18 km\n"
let prosePlan = PlanParser.parse(content: prose, startDate: start, raceDate: race, appendRaceDay: false)
assert(prosePlan[0].workouts[0].distanceKm == 18 && prosePlan[0].workouts[0].workoutType == .longRun)
let plan = TrainingPlan(parsed, content)
let recorded = plan.weeks[0].workouts.first { $0.workoutType.isRunnable }!
recorded.isCompleted = true; recorded.actualDistanceKm = 3.94; recorded.actualDurationSeconds = 2310
recorded.actualAvgPaceSecPerKm = 2310 / 3.94; recorded.completedAt = start
assert(CoachReportedCompletions.apply(to: plan, now: now) == 17)
let completed = plan.weeks.flatMap(\.workouts).filter { $0.isCoachConfirmedCompletion }
assert(completed.filter { $0.workoutType.isRunnable }.count == 14)
assert(completed.filter { $0.isPelotonStrength }.count == 3)
for week in plan.weeks {
    let runs = week.workouts.filter { $0.workoutType.isRunnable }
    if week.weekNumber <= 4 { assert(runs.count == 3 && runs.allSatisfy { $0.isCompleted }) }
    if week.weekNumber == 3 || week.weekNumber == 4 {
        assert(week.workouts.filter { $0.isPelotonStrength }.allSatisfy { !$0.isCompleted })
    }
    if week.weekNumber == 5 {
        assert(runs.filter { $0.isCompleted }.count == 2)
        assert(runs.filter { $0.workoutType == .longRun }.allSatisfy { !$0.isCompleted })
    }
    if week.weekNumber > 5 { assert(week.workouts.allSatisfy { !$0.isCompleted }) }
}
assert(recorded.actualDistanceKm == 3.94 && recorded.actualDurationSeconds == 2310 && recorded.completedAt == start)
assert(completed.filter { $0 !== recorded }.allSatisfy { $0.actualDurationSeconds == nil && $0.actualAvgPaceSecPerKm == nil && $0.completedAt == nil })
assert(CoachReportedCompletions.apply(to: plan, now: now) == 0) // Idempotent, including weeks older than 30 days.
let noReport = TrainingPlan(parsed, "No completion report")
assert(CoachReportedCompletions.apply(to: noReport, now: now) == 0)
let future = TrainingPlan(parsed, content)
assert(CoachReportedCompletions.apply(to: future, now: start.addingTimeInterval(-86400)) == 0)
print("PASS: 14 runs, 3 Peloton completions, pending long run, old weeks, idempotence, future protection, preserved actuals, and explicit-total distance priority")
'''
with tempfile.TemporaryDirectory() as folder:
    source = Path(folder) / 'Check.swift'
    binary = Path(folder) / 'check'
    source.write_text(code)
    subprocess.run(['swiftc', '-enable-bare-slash-regex', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(root.parent / 'output/michelle-plan-update/plan.txt')], check=True)
