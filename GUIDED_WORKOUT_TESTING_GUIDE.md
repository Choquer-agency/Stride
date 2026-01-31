# Daily Workout Engine - Testing Guide

## Overview

This guide provides comprehensive testing procedures for the Daily Workout Engine feature, which provides guided interval workouts with step-by-step progression, pace targets, and completion tracking.

## Test Environment Setup

### Prerequisites
1. Xcode with iOS Simulator or physical iOS device
2. Bluetooth treadmill (optional - can use Test Mode)
3. Active training plan with scheduled workouts (optional - can use test data)

### Test Mode
The app includes a Test Mode that simulates treadmill data without requiring actual hardware:
- Accessible via "Test" button in Run tab toolbar
- Simulates realistic pace, distance, and heart rate data
- 10x speed for faster testing

## Testing Checklist

### 1. Empty State Testing

#### Test 1.1: No Workout Scheduled
**Steps:**
1. Navigate to Workout tab
2. Ensure no workout is scheduled for today
3. Verify empty state displays:
   - Icon: figure.run
   - Message: "No workout scheduled for today"
   - Button: "View Training Plan"

**Expected:** Clean, informative empty state with action to create plan

#### Test 1.2: Rest Day
**Steps:**
1. Create/schedule a rest day workout for today
2. Navigate to Workout tab
3. Verify rest day state displays:
   - Icon: bed.double.fill
   - Message: "Rest day — recovery is part of training"
   - Subtext about recovery
   - NO action button (encourages actual rest)

**Expected:** Positive, supportive rest day message

### 2. Workout Preview Testing

#### Test 2.1: Structured Workout Preview
**Steps:**
1. Create a workout with intervals using `TestDataGenerator.generateTestGuidedWorkout()`
2. Navigate to Workout tab
3. Verify preview shows:
   - Workout title and description
   - Total stats (distance, duration, interval count)
   - All intervals in order with type badges
   - Each interval shows: distance/time, target pace, description
   - "Start Workout" button

**Expected:** Clear overview of entire workout structure

#### Test 2.2: Simple Workout (No Intervals)
**Steps:**
1. Create workout without intervals
2. Verify simplified view shows overall targets
3. Verify "Start Workout" button present

**Expected:** Simplified view for non-structured workouts

#### Test 2.3: Connection Warning
**Steps:**
1. Disconnect Bluetooth treadmill
2. Verify warning appears: "Connect your treadmill to start"
3. Verify Start button is disabled
4. Connect treadmill
5. Verify warning disappears and button enables

**Expected:** Clear connection status feedback

### 3. Interval Progression Testing

#### Test 3.1: Manual Progression
**Steps:**
1. Start test guided workout
2. Complete first interval distance/time
3. Verify "Interval complete — tap Next when ready" appears
4. Verify haptic feedback triggers
5. Tap "Next Interval" button
6. Verify advances to next interval
7. Verify "What's Next" preview updates

**Expected:** User maintains control, hints are helpful not automatic

#### Test 3.2: Early Advancement
**Steps:**
1. During an interval, tap "Next" before completion
2. Verify interval advances immediately
3. Verify partial completion is recorded

**Expected:** User can advance early if needed

#### Test 3.3: Completion Hint Timing
**Steps:**
1. Monitor progress percentage during interval
2. At 100% completion, verify:
   - Message appears: "Interval complete — tap Next when ready"
   - Subtle haptic (light impact) triggers
   - Message persists until user advances

**Expected:** Clear, persistent completion indication

#### Test 3.4: Countdown Warning
**Steps:**
1. Monitor progress during interval
2. At 80-90% completion, verify:
   - Warning appears: "10 seconds left" or "200m remaining"
   - Soft haptic triggers
   - Message displays briefly (3 seconds)

**Expected:** Heads-up before interval completion

### 4. Pace Feedback Testing

#### Test 4.1: Warmup Interval Tolerance (Wide)
**Steps:**
1. Start workout, begin warmup interval (target: 6:00/km)
2. Run at 5:45/km (within ±15 sec) → Verify GREEN feedback
3. Run at 5:30/km (±15-25 sec off) → Verify YELLOW feedback
4. Run at 5:00/km (>±25 sec off) → Verify RED feedback

**Expected:** Wide tolerance for easy pacing

#### Test 4.2: Work Interval Tolerance (Tight)
**Steps:**
1. Advance to work interval (target: 4:40/km)
2. Run at 4:38/km (within ±5 sec) → Verify GREEN feedback
3. Run at 4:48/km (±5-10 sec off) → Verify YELLOW feedback
4. Run at 4:25/km (>±10 sec off) → Verify RED feedback

**Expected:** Tight tolerance for work intervals

#### Test 4.3: Pace Feedback During Pause
**Steps:**
1. During any interval, tap "Pause"
2. Verify pace comparison disappears
3. Verify "PAUSED" displays in gray
4. Verify NO red/yellow feedback while paused

**Expected:** No negative feedback during pause

### 5. Pause/Resume Testing

#### Test 5.1: Basic Pause/Resume
**Steps:**
1. During interval, tap "Pause"
2. Verify:
   - Timer stops
   - Distance stops accumulating
   - "PAUSED" displays
   - Button changes to "Resume"
3. Tap "Resume"
4. Verify interval progress unchanged
5. Verify timer and distance resume

**Expected:** Clean pause/resume with no progress loss

#### Test 5.2: Long Pause Reassurance
**Steps:**
1. Pause workout
2. Wait >3 minutes (or adjust system time)
3. Verify message appears: "Resume when ready — interval progress unchanged"

**Expected:** Reassuring message for long pauses

#### Test 5.3: Pause Duration Not Counted
**Steps:**
1. Note interval elapsed time
2. Pause for 30 seconds
3. Resume
4. Verify elapsed time hasn't increased by 30 seconds

**Expected:** Paused time excluded from interval time

### 6. Skip Interval Testing

#### Test 6.1: Skip Confirmation
**Steps:**
1. During interval, tap "Skip"
2. Verify confirmation alert: "Skip this interval?"
3. Tap "Cancel" → Verify stays in current interval
4. Tap "Skip" again, then "Skip" in alert
5. Verify advances to next interval

**Expected:** Confirmation prevents accidental skips

#### Test 6.2: Skip Recording
**Steps:**
1. Skip an interval
2. Complete workout
3. In completion sheet, verify skipped interval shows:
   - Status: "Skipped" in orange
   - NOT marked as failed

**Expected:** Skipped intervals logged correctly

### 7. "What's Next" Preview Testing

#### Test 7.1: Preview Display
**Steps:**
1. During any interval (except last), verify preview shows:
   - "Next: [distance] [type] @ [pace]"
   - Example: "Next: 400m Recovery @ Easy Pace"

**Expected:** Clear preview of upcoming interval

#### Test 7.2: Last Interval
**Steps:**
1. Advance to final interval
2. Verify "What's Next" preview does NOT appear

**Expected:** No preview on last interval

### 8. Live Metrics Testing

#### Test 8.1: Metrics Display
**Steps:**
1. During workout, verify live metrics show:
   - Current pace (large, colored by tolerance)
   - Distance (total workout distance)
   - Time (total workout time)
   - Heart rate (if available)

**Expected:** All metrics update in real-time

#### Test 8.2: Overall Progress
**Steps:**
1. Verify "X / Y intervals complete" displays
2. Advance through intervals
3. Verify count updates correctly

**Expected:** Accurate interval completion count

### 9. Workout Completion Testing

#### Test 9.1: Complete All Intervals
**Steps:**
1. Complete all intervals in workout
2. Tap "End Workout" (or system handles final interval)
3. Verify WorkoutCompletionSheet appears with:
   - Effort rating slider
   - Fatigue level slider
   - Injury flag toggle
   - Notes field
   - **Interval Performance section**

**Expected:** Completion sheet with interval comparison

#### Test 9.2: Interval Performance Display
**Steps:**
1. In completion sheet, verify Interval Performance shows:
   - Each interval with type badge
   - Completed intervals: actual vs target pace with color
   - Skipped intervals: "Skipped" in orange
   - Overall adherence score percentage

**Expected:** Clear performance summary

#### Test 9.3: Adherence Score Calculation
**Steps:**
1. Complete workout with mixed performance:
   - Some intervals on-target (green)
   - Some slightly off (yellow)
   - One skipped
2. Verify adherence score reflects performance
3. Verify skipped intervals don't lower score unfairly

**Expected:** Fair, informative adherence metric

### 10. Edge Cases & Error Handling

#### Test 10.1: Bluetooth Disconnection Mid-Workout
**Steps:**
1. Start guided workout
2. Disconnect Bluetooth during interval
3. Verify app handles gracefully
4. Reconnect
5. Verify interval progress maintained

**Expected:** Robust handling of connection loss

#### Test 10.2: App Backgrounding
**Steps:**
1. Start guided workout
2. Background app (home button/swipe up)
3. Wait 30 seconds
4. Return to app
5. Verify interval progress maintained
6. Verify UI state correct

**Expected:** State persists through backgrounding

#### Test 10.3: Early Workout End
**Steps:**
1. Complete 2 of 5 intervals
2. Tap "End Workout", confirm
3. Verify completion sheet shows:
   - Completed intervals: "completed"
   - Current interval: "partial"
   - Remaining intervals: not shown

**Expected:** Partial workout tracked correctly

### 11. Integration Testing

#### Test 11.1: Workout from Training Plan
**Steps:**
1. Create training plan with scheduled workout
2. Navigate to Workout tab on scheduled day
3. Verify today's workout appears
4. Complete workout
5. Navigate to Plan tab
6. Verify workout marked as completed

**Expected:** Seamless plan integration

#### Test 11.2: Multiple Workouts Same Day
**Steps:**
1. Schedule multiple workouts for same day
2. Verify Workout tab shows first/primary workout
3. Complete it
4. Verify completion tracked to correct workout

**Expected:** Correct workout association

## Test Data Generation

### Creating Test Workouts

```swift
// In debug builds or test mode:

// 1. Structured interval workout
let intervalWorkout = TestDataGenerator.generateTestGuidedWorkout()
trainingPlanManager.activePlan?.addWorkout(intervalWorkout, for: Date())

// 2. Simple workout
let simpleWorkout = TestDataGenerator.generateTestSimpleWorkout()
trainingPlanManager.activePlan?.addWorkout(simpleWorkout, for: Date())

// 3. Rest day
let restDay = TestDataGenerator.generateTestRestDay()
trainingPlanManager.activePlan?.addWorkout(restDay, for: Date())
```

## Performance Testing

### 1. Memory Usage
- Monitor memory during long workouts (45+ minutes)
- Verify no leaks when advancing intervals
- Check memory after multiple workout sessions

### 2. Responsiveness
- Verify UI updates smoothly during intervals
- Check haptic feedback timing
- Verify no lag when updating progress indicators

### 3. Battery Impact
- Test extended workout session (30+ minutes)
- Monitor battery drain rate
- Compare with non-guided workout mode

## Known Limitations (v1)

1. **Audio Cues**: Not implemented in v1 (visual-only)
2. **Outdoor Mode**: Same UI as treadmill mode
3. **Custom Intervals**: Can't create intervals in-app (plan generation only)
4. **Heart Rate Zones**: Targets show pace only (not HR zones)

## Reporting Issues

When reporting issues, include:
1. Test step number
2. Expected behavior
3. Actual behavior
4. Screenshots/video if applicable
5. Device info (model, iOS version)
6. Test mode or real treadmill

## Success Criteria

✅ All empty states display correctly
✅ Interval progression works with manual control
✅ Completion hints trigger at correct time
✅ Pace tolerance adapts by interval type
✅ Pause semantics work as specified
✅ Skip functionality works with confirmation
✅ "What's Next" preview shows correctly
✅ Workout completion shows interval comparison
✅ App handles edge cases gracefully
✅ Performance acceptable during long workouts

---

Last Updated: January 2026
