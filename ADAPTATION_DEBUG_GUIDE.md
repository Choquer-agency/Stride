# Weekly Adaptation Debug Guide

## Overview
This guide explains the enhanced debug logging for the Weekly Adaptation system, specifically for debugging the pain level checking in Rule 2.

## Debug Output Structure

When you click "Run Adaptation (Debug)", you'll see detailed console output:

### 1. **Week Analysis Header**
```
📊 WEEKLY ANALYSIS DEBUG
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Period: [start date] to [end date]
Planned: X, Completed: Y
Total feedback in system: Z
Feedback entries in week: W
```

**What to check:**
- Is the date range correct (last 7 days)?
- Are there completed workouts?
- Is there feedback data in the system?
- Is the feedback being filtered correctly for the week?

### 2. **Performance Metrics**
```
📈 Performance Metrics:
  Completion Rate: XX.X%
  Avg Pace Variance: XX.X%
  Avg HR Drift: XX.X%
  Avg RPE: X.X
  Avg Fatigue: X.X
  Injury Count: X
```

**What to check:**
- Does the completion rate make sense?
- Are RPE and Fatigue values being calculated from feedback?
- Is the injury count correct (counts feedback with painLevel >= 4)?

### 3. **Advanced Analysis: Injury Risk**
```
🔍 Advanced Analysis:
🔍 Analyzing injury risk from X feedback entries
  📅 Sorted feedback chronologically:
    [0] Date: [...], Pain: X, Session ID: [...]
    [1] Date: [...], Pain: X, Session ID: [...]
    ...
```

**What to check:**
- Are the feedback entries sorted chronologically?
- Are the pain levels correct?
- Are the dates sequential?

#### Rule 1: High Pain Detection
```
  ⚠️ Rule 1: Found X workout(s) with pain >= 7
```
**Triggers when:** Any workout has painLevel >= 7
**Result:** Adds "High pain level detected" flag

#### Rule 2: Consecutive Moderate Pain
```
  ⚠️ Rule 2: Consecutive moderate pain detected!
    Previous: Pain X on [date]
    Current: Pain X on [date]
```
**Triggers when:** Two consecutive workouts both have painLevel >= 4
**Result:** Adds "Consecutive moderate pain" flag

**Common issues:**
- Workouts must be consecutive in the sorted array
- Both must have painLevel >= 4
- Check that dates are truly consecutive days

#### Rule 3: Recurring Pain Areas
```
  📊 Pain area counts:
    - Knee: 2 occurrence(s)
    - Calf: 1 occurrence(s)
  ⚠️ Rule 3: Recurring pain in Knee
```
**Triggers when:** Same pain area appears 2+ times in 7 days
**Result:** Adds "Recurring pain: [area]" flag

### 4. **Overreaching Analysis**
```
🔍 Analyzing overreaching from X feedback entries
  ⚠️ Found X workout(s) with effort >= 8 AND fatigue >= 4
  ⚠️ Found X workout(s) stopped early
  ✅ Overreaching analysis complete: X flag(s) found
```

**What to check:**
- Are high-effort + high-fatigue workouts being detected?
- Are stopped-early workouts being counted?

### 5. **Gym Form Issues**
```
🔍 Analyzing gym form issues
  Feedback from last 14 days: X
  Form breakdown count: X
  ⚠️ Form breakdown detected X times in 14 days
```

**What to check:**
- Checks last 14 days (not just 7)
- Counts feedback where formBreakdown == true
- Triggers if count >= 2

### 6. **Flags Summary**
```
🚩 Flags Summary:
  Injury Risk Flags: Consecutive moderate pain, Recurring pain: Knee
  Overreaching Flags: High effort + high fatigue pattern
  Gym Form Issues: Yes
```

**What to check:**
- All detected flags are listed here
- These flags influence the injury status determination

### 7. **Status Categories**
```
📋 Status Categories:
  Pace Consistency: excellent/good/moderate/struggling/noData
  Fatigue Status: fresh/moderate/high/exhausted/noData
  Injury Status: none/minor/concerning
  Overall Status: excellent/good/needsRecovery/needsRest
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**What to check:**
- **Injury Status:** 
  - `none`: No injuries
  - `minor`: 1 injury flag
  - `concerning`: 2+ injury flags OR any injury risk flags detected
- **Overall Status:**
  - `needsRest`: Injury status is concerning
  - `needsRecovery`: Overreaching flags, gym form issues, high fatigue, etc.
  - `good`: Maintain current load
  - `excellent`: Ready for progression

## Debugging Rule 2: Consecutive Moderate Pain

If Rule 2 isn't triggering when you expect:

1. **Check feedback exists:**
   - Look at "Total feedback in system"
   - Look at "Feedback entries in week"

2. **Check pain levels:**
   - Look at the sorted feedback list
   - Verify painLevel values are >= 4 for the workouts in question

3. **Check chronological order:**
   - Feedback is sorted by date
   - Check that consecutive array indices are actually consecutive workouts

4. **Check the loop logic:**
   - The loop compares `sortedFeedback[i-1]` with `sortedFeedback[i]`
   - Both must have `painLevel >= 4`
   - It breaks after finding the first match

## Common Issues

### No Feedback Data
**Symptom:** "Feedback entries in week: 0"
**Cause:** No workout feedback has been saved
**Solution:** Complete workouts and fill out the feedback form

### Feedback Not in Week Range
**Symptom:** "Total feedback in system: 5" but "Feedback entries in week: 0"
**Cause:** Feedback dates are outside the 7-day analysis window
**Solution:** Check that workout completion dates are within the last 7 days

### Pain Level Too Low
**Symptom:** Pain levels showing but Rule 2 not triggering
**Cause:** painLevel < 4 on one or both workouts
**Solution:** Ensure painLevel >= 4 on consecutive workouts

### Non-Consecutive Workouts
**Symptom:** Two workouts with pain >= 4 but not triggering
**Cause:** Workouts are not consecutive in the sorted array (there's a workout between them)
**Solution:** The rule requires consecutive entries in the feedback array

## Testing Rule 2

To test the consecutive pain detection:

1. **Create test feedback:**
   - Complete 2 workouts on consecutive days
   - Set painLevel >= 4 on both
   - Save feedback for both

2. **Run adaptation:**
   - Go to Plan tab
   - Tap "•••" menu
   - Select "Run Adaptation (Debug)"

3. **Check console output:**
   - Look for "Rule 2: Consecutive moderate pain detected!"
   - Verify the dates and pain levels shown
   - Check that injury status becomes "concerning"
   - Verify overall status becomes "needsRest"

## Code Location

The enhanced debug logging is in:
- `/Stride/Utilities/WeeklyAnalyzer.swift`
  - Lines 231-294: `analyzeInjuryRisk()` - Rule 2 is here
  - Lines 296-317: `analyzeOverreaching()`
  - Lines 319-335: `analyzeGymFormIssues()`
  - Lines 66-169: Main `analyzeWeek()` method with debug output
