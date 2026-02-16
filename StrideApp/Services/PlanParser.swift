import Foundation

// MARK: - Plan Parser
/// Parses the AI-generated training plan text into structured Week/Workout models
class PlanParser {
    
    /// Parse raw plan content into weeks and workouts
    static func parse(content: String, startDate: Date, raceDate: Date) -> [ParsedWeek] {
        var weeks: [ParsedWeek] = []
        let lines = content.components(separatedBy: .newlines)
        let calendar = Calendar.current
        
        // Anchor all week calculations to the Monday of the week containing startDate.
        // The AI generates weeks as Monday→Sunday, so weekStart must always be a Monday.
        let startWeekday = calendar.component(.weekday, from: startDate)
        // Convert to Monday-based offset: Monday=0, Tue=1, ..., Sun=6
        let mondayOffset = (startWeekday == 1) ? -6 : -(startWeekday - 2)
        let mondayOfStartWeek = calendar.date(byAdding: .day, value: mondayOffset, to: startDate)!
        
        // Use startOfDay for reliable date comparisons when skipping pre-start workouts
        let startDateStart = calendar.startOfDay(for: startDate)
        
        var currentWeek: ParsedWeek?
        var currentDate = mondayOfStartWeek
        
        // Track continuation lines for multi-line workout descriptions
        // The AI generates workouts like:
        //   Tuesday: Threshold – Build lactate tolerance
        //   Total: 12 km
        //   Warm-up: 2 km at 6:15/km
        //   Main: 3 × 2 km at 4:55/km
        //   Cool-down: 2 km at 6:15/km
        var pendingContinuationLines: [String] = []
        var lastWorkoutIndex: Int? = nil
        
        // Patterns to detect week headers and day entries
        // Week patterns like "WEEK 1 [BUILD]", "Week 1:", etc.
        let weekPattern = /[Ww][Ee][Ee][Kk]\s*(\d+)/
        // Day patterns - can start with bullet points, dashes, or directly with day name
        // Matches: "- Monday:", "Monday:", "• Monday:", "  - Monday:", etc.
        // Now handles: colon, en-dash, hyphen, em-dash, horizontal bar, figure dash, or optional separator
        // The separator is optional to handle cases like "Monday Easy Run" (no punctuation)
        let dayPattern = /(?i)^[\s\-•*]*?(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\s*(?:[:–\-\u{2014}\u{2015}\u{2012}]\s*)?/
        
        /// Flush any accumulated continuation lines into the last workout's details,
        /// and re-extract distance if the day line didn't have one.
        /// Gym continuation lines (e.g. "Gym (PM): Lower-body strength") are split
        /// into separate ParsedWorkout entries on the same date so they appear as
        /// their own cards in the plan view.
        func flushContinuationLines() {
            guard let weekIdx = lastWorkoutIndex,
                  !pendingContinuationLines.isEmpty,
                  currentWeek != nil else {
                pendingContinuationLines.removeAll()
                lastWorkoutIndex = nil
                return
            }
            
            let workoutCount = currentWeek!.workouts.count
            guard weekIdx < workoutCount else {
                pendingContinuationLines.removeAll()
                lastWorkoutIndex = nil
                return
            }
            
            // Detect gym continuation lines and separate them from regular lines.
            // Patterns: "Gym (PM): Lower-body strength", "Gym: Maintenance only", etc.
            let gymLinePattern = /^(?i)Gym\s*(?:\((?:AM|PM)\))?\s*[:–\-\u{2014}\u{2015}\u{2012}]\s*(.*)/
            
            var regularLines: [String] = []
            var gymDescriptions: [(full: String, focus: String)] = []
            
            for line in pendingContinuationLines {
                if let match = line.firstMatch(of: gymLinePattern) {
                    let focus = String(match.1).trimmingCharacters(in: .whitespaces)
                    gymDescriptions.append((full: line, focus: focus))
                } else {
                    regularLines.append(line)
                }
            }
            
            // --- Process regular (non-gym) continuation lines as before ---
            var workout = currentWeek!.workouts[weekIdx]
            
            if !regularLines.isEmpty {
                let combinedContinuation = regularLines.joined(separator: "\n")
                
                // Append continuation lines to details
                if let existingDetails = workout.details, !existingDetails.isEmpty {
                    workout.details = existingDetails + "\n" + combinedContinuation
                } else {
                    workout.details = combinedContinuation
                }
                
                // If the day line didn't capture a distance, try extracting from the full text
                if workout.distanceKm == nil {
                    let fullText = (workout.details ?? "") + "\n" + combinedContinuation
                    if let distance = extractDistance(from: fullText) {
                        workout.distanceKm = distance
                        #if DEBUG
                        print("  📏 Found distance \(distance) km from continuation lines for: \(workout.title)")
                        #endif
                    }
                }
            }
            
            currentWeek!.workouts[weekIdx] = workout
            
            // --- Create separate workouts for each gym continuation line ---
            for gym in gymDescriptions {
                let title = gym.focus.isEmpty ? "Gym" : gym.focus
                let duration = extractDuration(from: gym.focus)
                
                let gymWorkout = ParsedWorkout(
                    date: workout.date,
                    workoutType: .gym,
                    title: title,
                    details: gym.full,
                    distanceKm: nil,
                    durationMinutes: duration,
                    paceDescription: nil
                )
                currentWeek!.workouts.append(gymWorkout)
                
                #if DEBUG
                if let currentWeekNum = currentWeek?.weekNumber {
                    print("  🏋️ Week \(currentWeekNum): Created gym workout '\(title)' on same date as '\(workout.title)'")
                }
                #endif
            }
            
            pendingContinuationLines.removeAll()
            lastWorkoutIndex = nil
        }
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines
            guard !trimmedLine.isEmpty else { continue }

            // Detect end-of-plan markers (summary sections, etc.)
            // Only trigger after we've parsed at least one week — these keywords
            // commonly appear in the coaching overview before any WEEK headers.
            if !weeks.isEmpty || currentWeek != nil {
                let summaryPattern = /(?i)^\s*(plan\s+summary|training\s+summary|(?:weekly\s+)?volume\s+summary|(?:volume\s+)?progression\s+summary)/
                if trimmedLine.firstMatch(of: summaryPattern) != nil {
                    #if DEBUG
                    print("📋 Hit end-of-plan marker: \(trimmedLine)")
                    #endif
                    break
                }
            }

            // Check for week header
            if let weekMatch = trimmedLine.firstMatch(of: weekPattern) {
                let weekNumber = Int(weekMatch.1) ?? (weeks.count + 1)

                // Skip duplicate week numbers BEFORE appending currentWeek
                // (e.g., from summary sections that slip through)
                if weeks.contains(where: { $0.weekNumber == weekNumber }) || currentWeek?.weekNumber == weekNumber {
                    continue
                }

                // Flush any pending continuation lines before starting a new week
                flushContinuationLines()

                // Save previous week if exists
                if let week = currentWeek {
                    weeks.append(week)
                }

                let theme = extractWeekTheme(from: trimmedLine)
                currentWeek = ParsedWeek(weekNumber: weekNumber, theme: theme)
                
                #if DEBUG
                print("📅 Parsed Week \(weekNumber) header: \(trimmedLine)")
                #endif
                
                // Update current date to the Monday of this week
                // (anchored to mondayOfStartWeek so weekStart is always a Monday)
                currentDate = calendar.date(
                    byAdding: .day,
                    value: (weekNumber - 1) * 7,
                    to: mondayOfStartWeek
                ) ?? mondayOfStartWeek
                
            } else if let dayMatch = trimmedLine.firstMatch(of: dayPattern) {
                // Flush continuation lines from the previous workout before starting a new one
                flushContinuationLines()
                
                // Extract the day name to calculate the correct date
                let dayName = String(dayMatch.1).lowercased()
                
                // Calculate date based on day of week within current week
                if let weekDate = calculateDateForDay(dayName, weekStart: currentDate, calendar: calendar) {
                    // Skip workouts that fall before the plan's start date
                    // (e.g., Mon-Fri of Week 1 when plan starts on Saturday)
                    let weekDateStart = calendar.startOfDay(for: weekDate)
                    guard weekDateStart >= startDateStart else {
                        #if DEBUG
                        if let currentWeekNum = currentWeek?.weekNumber {
                            print("  ⏭ Week \(currentWeekNum) - \(dayName): Skipping (before plan start date)")
                        }
                        #endif
                        continue
                    }
                    
                    // Parse workout(s) for this day (may return multiple if gym is embedded)
                    let parsedWorkouts = parseWorkoutLine(trimmedLine, date: weekDate)
                    if !parsedWorkouts.isEmpty {
                        for workout in parsedWorkouts {
                            currentWeek?.workouts.append(workout)
                        }
                        // Track the index of the primary (first) workout for continuation lines
                        lastWorkoutIndex = (currentWeek?.workouts.count ?? parsedWorkouts.count) - parsedWorkouts.count
                        #if DEBUG
                        if let currentWeekNum = currentWeek?.weekNumber {
                            let primary = parsedWorkouts[0]
                            print("  ✓ Week \(currentWeekNum) - \(dayName): \(primary.title) (\(primary.distanceKm.map { "\($0) km" } ?? "no distance yet"))")
                            if parsedWorkouts.count > 1 {
                                print("    + \(parsedWorkouts.count - 1) additional workout(s) extracted from same line")
                            }
                        }
                        #endif
                    } else {
                        #if DEBUG
                        if let currentWeekNum = currentWeek?.weekNumber {
                            print("  ⚠ Week \(currentWeekNum) - \(dayName): Failed to parse workout from: \(trimmedLine)")
                        }
                        #endif
                    }
                } else {
                    #if DEBUG
                    if let currentWeekNum = currentWeek?.weekNumber {
                        print("  ⚠ Week \(currentWeekNum) - \(dayName): Failed to calculate date for: \(trimmedLine)")
                    }
                    #endif
                }
            } else {
                // This is a continuation line (Total, Warm-up, Main, Cool-down, Gym, etc.)
                // or a line we don't recognize. If we're inside a week and have a recent workout,
                // accumulate it as a continuation line.
                if currentWeek != nil && lastWorkoutIndex != nil {
                    pendingContinuationLines.append(trimmedLine)
                }
                
                #if DEBUG
                // Log lines that don't match any pattern (potential parsing issues)
                if currentWeek != nil && !trimmedLine.isEmpty {
                    // Only log if we're in a week context (not just random text)
                    // Check if line looks like it might be a day entry (contains day name)
                    let dayNameCheck = /(?i)(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)/
                    if trimmedLine.firstMatch(of: dayNameCheck) != nil {
                        if let currentWeekNum = currentWeek?.weekNumber {
                            print("  ❌ Week \(currentWeekNum): Unmatched line (might be formatting issue): \(trimmedLine)")
                        }
                    }
                }
                #endif
            }
        }
        
        // Flush any remaining continuation lines
        flushContinuationLines()
        
        // Don't forget the last week
        if let week = currentWeek {
            weeks.append(week)
        }
        
        #if DEBUG
        print("📊 Parsed \(weeks.count) weeks total")
        for week in weeks {
            print("  Week \(week.weekNumber): \(week.workouts.count) workouts")
        }
        #endif
        
        // If parsing failed to extract structure, create a basic structure
        if weeks.isEmpty {
            weeks = createBasicStructure(from: content, startDate: startDate, raceDate: raceDate)
        }
        
        // Add race day to the week that contains the race date
        // Find the week whose date range includes the race date
        var raceWeekIndex: Int? = nil
        
        for (index, week) in weeks.enumerated() {
            // Calculate this week's date range based on week number
            // Anchored to mondayOfStartWeek so ranges are always Mon→Sun
            let weekStartOffset = (week.weekNumber - 1) * 7
            guard let weekStart = calendar.date(byAdding: .day, value: weekStartOffset, to: mondayOfStartWeek),
                  let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
                continue
            }
            
            // Check if race date falls within this week's range (inclusive)
            if raceDate >= weekStart && raceDate <= weekEnd {
                raceWeekIndex = index
                
                #if DEBUG
                print("🏁 Race date \(raceDate) falls in Week \(week.weekNumber) (range: \(weekStart) to \(weekEnd))")
                #endif
                break
            }
        }
        
        // If we found the race week, add race day to it
        // Otherwise, fall back to the last week (shouldn't happen in normal cases)
        let targetWeekIndex = raceWeekIndex ?? (weeks.count - 1)
        
        if targetWeekIndex >= 0 && targetWeekIndex < weeks.count {
            var targetWeek = weeks[targetWeekIndex]
            if !targetWeek.workouts.contains(where: { $0.workoutType == .race }) {
                targetWeek.workouts.append(ParsedWorkout(
                    date: raceDate,
                    workoutType: .race,
                    title: "Race Day!",
                    details: "Give it everything you've got!",
                    distanceKm: nil,
                    durationMinutes: nil,
                    paceDescription: nil
                ))
                weeks[targetWeekIndex] = targetWeek
                
                #if DEBUG
                print("🏁 Added race day to Week \(targetWeek.weekNumber)")
                #endif
            } else {
                #if DEBUG
                print("🏁 Week \(targetWeek.weekNumber) already contains a race workout")
                #endif
            }
        }
        
        return weeks
    }
    
    // MARK: - Private Helpers
    
    private static func calculateDateForDay(_ dayName: String, weekStart: Date, calendar: Calendar) -> Date? {
        let dayMapping: [String: Int] = [
            "monday": 2,
            "tuesday": 3,
            "wednesday": 4,
            "thursday": 5,
            "friday": 6,
            "saturday": 7,
            "sunday": 1
        ]
        
        guard let targetWeekday = dayMapping[dayName] else { return nil }
        
        // Get the weekday of weekStart
        let startWeekday = calendar.component(.weekday, from: weekStart)
        
        // Calculate days offset (assuming week starts on Monday)
        // Monday = 2 in Calendar, but we want Monday = 0 offset
        let startOffset = (startWeekday == 1) ? 6 : startWeekday - 2  // Convert to Monday = 0
        let targetOffset = (targetWeekday == 1) ? 6 : targetWeekday - 2  // Convert to Monday = 0
        let daysToAdd = targetOffset - startOffset
        
        // Allow negative offsets — the caller will skip dates before startDate.
        // Previously max(0, daysToAdd) clamped Mon-Fri onto Saturday when
        // weekStart was a Saturday, causing all weekday workouts to collapse
        // onto a single day.
        return calendar.date(byAdding: .day, value: daysToAdd, to: weekStart)
    }
    
    private static func extractWeekTheme(from line: String) -> String? {
        // Try to extract theme from patterns like "Week 1: Base Building" or "Week 1 - Build Phase"
        let patterns = [
            /[Ww]eek\s*\d+\s*[:\-–]\s*(.+)/,
            /\((.+?)\)/
        ]
        
        for pattern in patterns {
            if let match = line.firstMatch(of: pattern) {
                return String(match.1).trimmingCharacters(in: .whitespaces)
            }
        }
        
        return nil
    }
    
    private static func parseWorkoutLine(_ line: String, date: Date) -> [ParsedWorkout] {
        // Remove leading bullet points, dashes, etc.
        let cleanedLine = line.replacingOccurrences(of: #"^[\s\-•*]*"#, with: "", options: .regularExpression)
        
        // Split on the first colon or dash/en-dash/em-dash to separate day from description
        // Format: "Monday: Easy Run – 8 km at 6:15/km"
        // Now handles: colon, en-dash, hyphen, em-dash, horizontal bar, figure dash, or optional separator
        // The separator is optional to handle cases like "Monday Easy Run" (no punctuation)
        let dayPattern = /(?i)^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\s*(?:[:–\-\u{2014}\u{2015}\u{2012}]\s*)?/
        
        guard let match = cleanedLine.firstMatch(of: dayPattern) else { return [] }
        
        // Get everything after the day name and separator
        let workoutDescription = String(cleanedLine[match.range.upperBound...]).trimmingCharacters(in: .whitespaces)
        
        // Handle empty description (just the day name)
        guard !workoutDescription.isEmpty else { return [] }
        
        // Check for embedded gym info within the day line itself.
        // The AI sometimes places gym info on the same line as the run, e.g.:
        //   "Easy Run – 8 km at 5:35/km (easy). Gym (PM): Upper-body/core strength"
        //   "Easy Run – 8 km at 5:35/km (easy); Gym (PM): Upper-body/core strength"
        // Split them into separate workouts so both appear as their own cards.
        let embeddedGymPattern = /(?i)(?:[\.;,]\s*|\s+)Gym\s*(?:\((?:AM|PM)\))?\s*[:–\-\u{2014}\u{2015}\u{2012}]\s*(.*)/
        
        var mainDescription = workoutDescription
        var gymWorkout: ParsedWorkout? = nil
        
        if let gymMatch = workoutDescription.firstMatch(of: embeddedGymPattern) {
            // Split: everything before the gym match is the run description
            mainDescription = String(workoutDescription[..<gymMatch.range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let gymFull = String(workoutDescription[gymMatch.range.lowerBound...])
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,; \t\n"))
            let gymFocus = String(gymMatch.1).trimmingCharacters(in: .whitespaces)
            let gymTitle = gymFocus.isEmpty ? "Gym" : gymFocus
            let gymDuration = extractDuration(from: gymFocus)
            
            gymWorkout = ParsedWorkout(
                date: date,
                workoutType: .gym,
                title: gymTitle,
                details: gymFull,
                distanceKm: nil,
                durationMinutes: gymDuration,
                paceDescription: nil
            )
            
            #if DEBUG
            print("  🏋️ Extracted embedded gym from day line: '\(gymTitle)'")
            #endif
        }
        
        let workoutType = inferWorkoutType(from: mainDescription)
        let distance = extractDistance(from: mainDescription)
        let duration = extractDuration(from: mainDescription)
        let pace = extractPace(from: mainDescription)
        
        // Extract a title from the description (text before any numeric/pace info)
        let title = extractTitle(from: mainDescription, type: workoutType)
        
        #if DEBUG
        // Log when running workouts are missing distance
        let isRunRelated = [WorkoutType.easyRun, .longRun, .tempoRun, .intervals, .hillRepeats, .recovery, .race].contains(workoutType)
        if isRunRelated && distance == nil {
            print("  ⚠️  Running workout missing distance: \(mainDescription)")
        }
        #endif
        
        var results: [ParsedWorkout] = []
        
        results.append(ParsedWorkout(
            date: date,
            workoutType: workoutType,
            title: title,
            details: mainDescription,
            distanceKm: distance,
            durationMinutes: duration,
            paceDescription: pace
        ))
        
        if let gym = gymWorkout {
            results.append(gym)
        }
        
        return results
    }
    
    private static func extractTitle(from description: String, type: WorkoutType) -> String {
        // Try to extract a meaningful title from the description
        // Common formats: "Easy Run – 8 km", "Threshold – Build lactate tolerance", "Rest"
        
        // First, try splitting on en-dash or regular dash with spaces
        let dashPattern = /^([^–\-]+?)\s*[–\-]/
        if let match = description.firstMatch(of: dashPattern) {
            let title = String(match.1).trimmingCharacters(in: .whitespaces)
            if !title.isEmpty && title.count < 50 {
                return title
            }
        }
        
        // Otherwise, use the workout type's display name
        return type.displayName
    }
    
    private static func inferWorkoutType(from description: String) -> WorkoutType {
        let lower = description.lowercased()
        
        if lower.contains("rest") || lower.contains("off") {
            return .rest
        } else if lower.hasPrefix("race day") || lower == "race" || lower.contains("race day") {
            return .race
        } else if lower.contains("long") {
            return .longRun
        } else if lower.contains("tempo") || lower.contains("threshold") {
            return .tempoRun
        } else if lower.contains("interval") || lower.contains("repeat") || lower.contains("speed") {
            return .intervals
        } else if lower.contains("hill") {
            return .hillRepeats
        } else if lower.contains("recovery") {
            return .recovery
        } else if lower.contains("gym") || lower.contains("strength") || lower.contains("weight") {
            return .gym
        } else if lower.contains("cross") || lower.contains("bike") || lower.contains("swim") || lower.contains("yoga") {
            return .crossTraining
        } else if lower.contains("easy") || lower.contains("aerobic") {
            return .easyRun
        }
        
        // Default to easy run for any running activity
        if lower.contains("run") || lower.contains("km") || lower.contains("mile") {
            return .easyRun
        }
        
        return .easyRun
    }
    
    private static func extractDistance(from description: String) -> Double? {
        // Match patterns like "10km", "10 km", "10.5km", "10.5 km", "Total: 12 km"
        // Also handles "8–10 km" by taking the first number
        let pattern = /(?i)(\d+\.?\d*)\s*km/
        if let match = description.firstMatch(of: pattern) {
            let distance = Double(match.1)
            #if DEBUG
            print("  📏 Extracted distance: \(distance ?? 0) km from: \(description)")
            #endif
            return distance
        }
        
        // Try matching patterns like "12k" (without the 'm')
        let shortPattern = /(?i)(\d+\.?\d*)\s*k\b/
        if let match = description.firstMatch(of: shortPattern) {
            let distance = Double(match.1)
            #if DEBUG
            print("  📏 Extracted distance: \(distance ?? 0) km from: \(description)")
            #endif
            return distance
        }
        
        // Try matching "Total: X km" format explicitly
        let totalPattern = /(?i)total[:\s]+(\d+\.?\d*)\s*km/
        if let match = description.firstMatch(of: totalPattern) {
            let distance = Double(match.1)
            #if DEBUG
            print("  📏 Extracted distance from 'Total': \(distance ?? 0) km from: \(description)")
            #endif
            return distance
        }
        
        #if DEBUG
        print("  ⚠️  No distance found in: \(description)")
        #endif
        
        return nil
    }
    
    private static func extractDuration(from description: String) -> Int? {
        // Match patterns like "45 min", "45min", "1hr 30min", "1:30"
        let minPattern = /(?i)(\d+)\s*min/
        if let match = description.firstMatch(of: minPattern) {
            return Int(match.1)
        }
        
        let hrMinPattern = /(?i)(\d+)\s*h(?:r|our)?s?\s*(\d+)?\s*m?/
        if let match = description.firstMatch(of: hrMinPattern) {
            let hours = Int(match.1) ?? 0
            let mins = match.2.flatMap { Int($0) } ?? 0
            return hours * 60 + mins
        }
        
        return nil
    }
    
    private static func extractPace(from description: String) -> String? {
        // Try range pattern first: "5:30-6:00/km", "at 5:30–6:00 /km"
        let rangePattern = /(?i)(?:at\s+)?(\d+:\d+)\s*[-–—]\s*(\d+:\d+)\s*(?:\/km)?/
        if let match = description.firstMatch(of: rangePattern) {
            return String(match.1) + "-" + String(match.2) + "/km"
        }

        // Single pace: "5:30/km", "at 5:30/km", "5:30 pace", "at 5:30"
        let pacePattern = /(?i)(?:at\s+)?(\d+:\d+)\s*(?:\/km)?/
        if let match = description.firstMatch(of: pacePattern) {
            return String(match.1) + "/km"
        }
        
        // Look for pace zone descriptions
        let paceDescriptions = [
            "easy pace", "easy", 
            "tempo pace", "tempo",
            "race pace", 
            "recovery pace", "recovery",
            "marathon pace", "mp",
            "threshold", "threshold pace",
            "steady", "steady pace",
            "interval pace"
        ]
        
        let lowerDesc = description.lowercased()
        for paceDesc in paceDescriptions {
            if lowerDesc.contains(paceDesc) {
                // Capitalize first letter of each word
                return paceDesc.split(separator: " ").map { $0.capitalized }.joined(separator: " ")
            }
        }
        
        return nil
    }
    
    private static func createBasicStructure(from content: String, startDate: Date, raceDate: Date) -> [ParsedWeek] {
        // Calculate number of weeks
        let days = Calendar.current.dateComponents([.day], from: startDate, to: raceDate).day ?? 84
        let numberOfWeeks = max(1, days / 7)
        
        var weeks: [ParsedWeek] = []
        let calendar = Calendar.current
        
        for weekNum in 1...numberOfWeeks {
            var week = ParsedWeek(weekNumber: weekNum, theme: nil)
            
            // Create 7 days for this week
            for dayOffset in 0..<7 {
                let totalDayOffset = (weekNum - 1) * 7 + dayOffset
                guard let workoutDate = calendar.date(byAdding: .day, value: totalDayOffset, to: startDate) else { continue }
                
                // Don't add workouts past race date
                if workoutDate > raceDate { break }
                
                let dayOfWeek = calendar.component(.weekday, from: workoutDate)
                
                // Simple default schedule: Rest on day before long run, long run on Sunday
                let workoutType: WorkoutType
                let title: String
                
                if workoutDate == raceDate {
                    workoutType = .race
                    title = "Race Day!"
                } else if dayOfWeek == 1 { // Sunday
                    workoutType = .longRun
                    title = "Long Run"
                } else if dayOfWeek == 7 { // Saturday
                    workoutType = .rest
                    title = "Rest Day"
                } else if dayOfWeek == 4 { // Wednesday
                    workoutType = .tempoRun
                    title = "Tempo Run"
                } else {
                    workoutType = .easyRun
                    title = "Easy Run"
                }
                
                week.workouts.append(ParsedWorkout(
                    date: workoutDate,
                    workoutType: workoutType,
                    title: title,
                    details: nil,
                    distanceKm: nil,
                    durationMinutes: nil,
                    paceDescription: nil
                ))
            }
            
            weeks.append(week)
        }
        
        return weeks
    }
}

// MARK: - Parsed Models (temporary before SwiftData)
struct ParsedWeek {
    let weekNumber: Int
    let theme: String?
    var workouts: [ParsedWorkout]
    
    init(weekNumber: Int, theme: String?) {
        self.weekNumber = weekNumber
        self.theme = theme
        self.workouts = []
    }
}

struct ParsedWorkout {
    let date: Date
    let workoutType: WorkoutType
    let title: String
    var details: String?
    var distanceKm: Double?
    let durationMinutes: Int?
    let paceDescription: String?
}
