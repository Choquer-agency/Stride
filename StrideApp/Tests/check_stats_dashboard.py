"""Regression checks for training-week boundaries, trends, and real-vs-planned achievements."""
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
enum WorkoutType { case easyRun, recovery, longRun, intervals, race, rest, gym, crossTraining }
struct CodableHRSample { let t: Double; let bpm: Int }
final class RunLog {
    var completedAt: Date
    var distanceKm: Double
    var durationSeconds: Double
    var avgPaceSecPerKm: Double
    var plannedWorkoutType: WorkoutType?
    var avgHeartRate: Int?
    var feedbackRating: Int?
    var decodedHRSamples: [CodableHRSample] = []
    init(_ date: Date, _ km: Double, type: WorkoutType? = .easyRun, hr: Int? = nil, rating: Int? = nil, pace: Double = 390) {
        completedAt = date; distanceKm = km; durationSeconds = km * pace
        avgPaceSecPerKm = pace; plannedWorkoutType = type; avgHeartRate = hr; feedbackRating = rating
    }
'''
code += declaration('Models/RunLog.swift', 'var isValidForStats: Bool') + '\n}\n'
for name in ['struct WeeklyDistanceStats', 'enum StatsTrainingData', 'struct TrainingTrendWeek', 'struct TrainingInsightSummary']:
    code += declaration('ViewModels/StatsViewModel.swift', name) + '\n'
code += '''
final class Workout {
    let date: Date; let workoutType: WorkoutType; let distanceKm: Double?
    init(_ date: Date, _ type: WorkoutType, _ km: Double) { self.date = date; workoutType = type; distanceKm = km }
}
final class Week {
    let weekNumber: Int; let workouts: [Workout]
    var mondayStart: Date? { workouts.first.map { StatsTrainingData.week(containing: $0.date).start } }
    init(_ n: Int, _ workouts: [Workout]) { weekNumber = n; self.workouts = workouts }
}
final class Plan {
    let sortedWeeks: [Week]; let raceDate: Date
    init(_ weeks: [Week], race: Date) { sortedWeeks = weeks; raceDate = race }
}
final class StatsHarness {
    static var trainingCalendar: Calendar { StatsTrainingData.calendar() }
    let plan: Plan; let runLogs: [RunLog]
    init(_ plan: Plan, _ runs: [RunLog]) { self.plan = plan; runLogs = runs }
'''
for signature in ['static func weeklyDistanceForCurrentCalendarWeek', 'static func rolling4WeekAverage',
                  'var longRunProgression:', 'var longRunActualProgression:', 'var longestRunEver:', 'var peakLongRunWeek:']:
    code += declaration('ViewModels/StatsViewModel.swift', signature) + '\n'
code += r'''
}
var sundayCalendar = Calendar(identifier: .gregorian)
sundayCalendar.timeZone = TimeZone(identifier: "America/Vancouver")!
sundayCalendar.firstWeekday = 1
func date(_ day: Int, hour: Int = 12) -> Date { sundayCalendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))! }
let sunday = date(18)
let interval = StatsTrainingData.week(containing: sunday, calendar: sundayCalendar)
assert(interval.start == date(12, hour: 0) && interval.end == date(19, hour: 0))
let runs = [RunLog(date(13), 12.02), RunLog(date(14), 6), RunLog(date(15), 14), RunLog(date(17), 4),
            RunLog(date(19, hour: 0), 10), RunLog(date(11), 20)]
let week = StatsHarness.weeklyDistanceForCurrentCalendarWeek(runLogs: runs, now: sunday, calendar: sundayCalendar)
assert(abs(week.completed - 36.02) < 0.001)
let monday = StatsHarness.weeklyDistanceForCurrentCalendarWeek(runLogs: runs, now: date(19), calendar: sundayCalendar)
assert(monday.completed == 10) // Exact next-Monday midnight never belongs to the preceding week.
let rangeRun = RunLog(date(14), 6, hr: 140)
rangeRun.durationSeconds = 60
rangeRun.decodedHRSamples = [.init(t: 0, bpm: 140), .init(t: 5, bpm: 160), .init(t: 30, bpm: 140)]
let zone = StatsTrainingData.inEasyRangeSeconds(rangeRun)
assert(zone.recorded == 25 && zone.inside == 15) // Twenty-five missing seconds are not invented.
let now = Date()
let currentStart = StatsTrainingData.week(containing: now).start
let currentLogs = [RunLog(now.addingTimeInterval(-3600), 6, hr: 140, rating: 0),
                   RunLog(now.addingTimeInterval(-7200), 6, hr: 142, rating: nil),
                   RunLog(now.addingTimeInterval(-10800), 12, type: .intervals, hr: 180, rating: 4),
                   RunLog(now.addingTimeInterval(86400), 6, hr: 99, rating: 5)]
let insight = TrainingInsightSummary(runLogs: currentLogs, now: now)
assert(insight.recentHR == 141 && insight.recentHRCount == 2) // Hard workouts and future data are excluded.
assert(insight.recentFeeling == 2 && insight.ratedCount == 2) // Zero is real feedback, nil is missing.
let recovery = RunLog(now.addingTimeInterval(-3600), 4, type: .recovery, hr: 130)
recovery.decodedHRSamples = [.init(t: 0, bpm: 130)]
let recoveryInsight = TrainingInsightSummary(runLogs: currentLogs + [recovery], now: now, heartRateType: .recovery)
assert(recoveryInsight.recentHR == 130 && recoveryInsight.heartRateRange == 120...135)
assert(recoveryInsight.inRangePercent == 100)
assert(insight.inRangePercent == nil) // Averages alone cannot establish time in zone.
let cal = StatsTrainingData.calendar()
let previous = cal.date(byAdding: .weekOfYear, value: -1, to: currentStart)!
let raceDay = cal.date(byAdding: .day, value: 20, to: currentStart)!
let plan = Plan([Week(1, [Workout(previous, .longRun, 24)]),
                 Week(2, [Workout(currentStart, .longRun, 32)]),
                 Week(3, [Workout(raceDay, .longRun, 42.195)])], race: raceDay)
let actual = [RunLog(previous.addingTimeInterval(3600), 20, type: .longRun), RunLog(now, 14, type: .longRun)]
let vm = StatsHarness(plan, actual)
assert(vm.longestRunEver == 20)
assert(vm.peakLongRunWeek == 2)
assert(vm.longRunProgression.last!.distance == 0) // Even a misclassified race is excluded by its date.
assert(vm.longRunActualProgression.count == 2)
let averageRuns = (1...4).map { offset in RunLog(cal.date(byAdding: .weekOfYear, value: -offset, to: currentStart)!.addingTimeInterval(3600), 20) }
let average = StatsHarness.rolling4WeekAverage(from: averageRuns + [RunLog(now, 100)], now: now)
assert(average == 20) // An incomplete current week must not skew the four-completed-week average.
print("PASS: Sunday/Monday boundary, 36.02 km week, half-open intervals, stale HR coverage, easy-only trends, zero/missing feedback, future exclusion, race-free peak, actual achievements and completed-week average")
'''
with tempfile.TemporaryDirectory(prefix='stride-stats-dashboard-') as directory:
    path = Path(directory) / 'main.swift'
    path.write_text(code)
    binary = Path(directory) / 'check'
    subprocess.run(['swiftc', str(path), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
