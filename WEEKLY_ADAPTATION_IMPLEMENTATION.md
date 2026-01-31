# Weekly Plan Adaptation Engine - Implementation Complete

## Overview

The Weekly Plan Adaptation Engine has been successfully implemented. This system automatically analyzes workout performance every Sunday and adjusts the training plan based on key metrics including pace variance, HR drift, RPE, fatigue levels, and injury flags.

## What Was Implemented

### 1. Data Tracking
- Added `fatigueLevel`, `injuryFlag`, and `injuryNotes` fields to `WorkoutSession` model
- Enhanced `WorkoutCompletionSheet` with:
  - Fatigue slider (1-5 scale)
  - Injury checkbox with optional notes field
  - All data captured when user completes a workout

### 2. Analysis Engine
- **WeeklyAnalyzer** (`Stride/Utilities/WeeklyAnalyzer.swift`)
  - Analyzes past 7 days of workouts
  - Calculates pace variance, HR drift, average RPE, average fatigue
  - Tracks injury count and completion rate
  - Determines overall status (excellent, good, needs recovery, needs rest)

### 3. Adaptation Logic
- **PlanAdapter** (`Stride/Utilities/PlanAdapter.swift`)
  - Applies adaptation protocols based on analysis:
    - **Rest Protocol**: 15% volume reduction, convert high-intensity to easy runs
    - **Recovery Protocol**: 10% volume reduction, 5% intensity reduction
    - **Maintenance Protocol**: Minor pace adjustments
    - **Progression Protocol**: 5% volume increase (when all metrics positive)
  - Generates coach-style explanation messages
  - Only modifies next 7 days (preserves future weeks)

### 4. Orchestration
- **WeeklyAdaptationManager** (`Stride/Managers/WeeklyAdaptationManager.swift`)
  - Coordinates analysis and adaptation process
  - Checks if adaptation should run (every Sunday)
  - Saves adaptation records for history
  - Publishes banner notifications
  - Handles both automatic and manual triggers

### 5. Plan Updates
- **TrainingPlanManager** enhancements
  - `applyWeeklyAdaptation()` method applies changes to plan
  - Preserves completed workouts
  - Updates volume, intensity, and workout types
  - Only modifies future workouts (next 7 days)

### 6. User Interface
- **AdaptationBannerView** (`Stride/Views/Components/AdaptationBannerView.swift`)
  - Displays at top of Plan calendar
  - Shows coach message with severity indicator
  - Expandable to view full details
  - Shows volume/intensity change percentages
  - Dismissible by user

### 7. Integration
- **PlanCalendarView** updated to:
  - Create and manage `WeeklyAdaptationManager`
  - Display adaptation banner when available
  - Check and run adaptation on view appear
  - Manual trigger button (DEBUG mode only)

### 8. Background Scheduling
- **StrideApp** updated to:
  - Register background task for weekly adaptation
  - Schedule for every Sunday at 6 AM
  - Fallback: check on app launch if Sunday was missed
  - Re-schedule when app enters background

### 9. Storage
- **AdaptationRecord** model tracks adaptation history
- **StorageManager** methods:
  - `saveAdaptationRecord()`
  - `loadAdaptationHistory()`
  - `loadLatestAdaptation()`
  - Keeps last 26 weeks (6 months) of history

## Required Xcode Configuration

### Add Background Task Capability

To enable the Sunday background task, you need to add the background task identifier to your Xcode project:

1. Open `Stride.xcodeproj` in Xcode
2. Select the Stride target
3. Go to "Signing & Capabilities" tab
4. Click "+ Capability" and add "Background Modes"
5. Check "Background fetch"
6. Go to the "Info" tab
7. Add a new item to "Permitted background task scheduler identifiers":
   - Type: Array
   - Add item: `com.stride.weeklyAdaptation` (String)

### Alternative: Manual Info.plist Entry

If your project uses Info.plist, add this entry:

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.stride.weeklyAdaptation</string>
</array>
```

## How It Works

### Weekly Cycle

1. **Sunday 6 AM**: Background task triggers (or on app launch if missed)
2. **Analysis**: System reviews past 7 days:
   - Completion rate
   - Pace vs targets
   - HR drift
   - RPE scores
   - Fatigue levels
   - Injury flags

3. **Decision**: Based on overall status:
   - **Excellent** → Small progression (+5% volume)
   - **Good** → Maintain current plan (minor tweaks)
   - **Needs Recovery** → Reduce load (−10% volume, −5% intensity)
   - **Needs Rest** → Significant reduction (−15% volume, lower intensity)

4. **Application**: Updates next week's workouts only
5. **Notification**: Banner appears on Plan tab with explanation

### User Experience

- After completing a workout, user provides:
  - Effort rating (1-10)
  - Fatigue level (1-5)
  - Injury flag (yes/no with optional notes)

- Every Sunday, plan automatically adapts
- User sees banner on Plan tab explaining changes
- Can tap banner to expand for full details
- Can dismiss when acknowledged

### Manual Testing

For development/testing, a manual trigger button is available in DEBUG mode:
- Open Plan tab
- Tap "•••" menu in navigation bar
- Select "Run Adaptation (Debug)"
- This triggers adaptation immediately regardless of day

## Adaptation Rules Summary

### High Fatigue or Injury (Needs Rest)
- 15% volume reduction across all workouts
- Convert tempo/interval workouts to easy runs
- Add extra rest day mid-week if injury is concerning
- Priority: Recovery over fitness

### Moderate Issues (Needs Recovery)
- 10% volume reduction
- 5% intensity reduction (slower paces)
- Maintain workout types but ease off
- Priority: Balance recovery with maintenance

### Good Performance (Maintain)
- Minor pace adjustments if targets are off
- No major changes
- Continue as planned

### Excellent Performance (Progress)
- 5% volume increase on easy/long runs only
- Conservative progression
- Only when: 90%+ completion, good pace, low fatigue, no injury

## Files Created/Modified

### New Files
1. `Stride/Utilities/WeeklyAnalyzer.swift`
2. `Stride/Utilities/PlanAdapter.swift`
3. `Stride/Managers/WeeklyAdaptationManager.swift`
4. `Stride/Models/AdaptationRecord.swift`
5. `Stride/Views/Components/AdaptationBannerView.swift`

### Modified Files
1. `Stride/Models/WorkoutSession.swift` - Added fatigue/injury fields
2. `Stride/Views/Components/WorkoutCompletionSheet.swift` - Added UI for fatigue/injury
3. `Stride/Managers/StorageManager.swift` - Added adaptation history methods
4. `Stride/Managers/TrainingPlanManager.swift` - Added applyWeeklyAdaptation()
5. `Stride/Views/PlanTab/PlanCalendarView.swift` - Integrated adaptation manager
6. `Stride/Views/MainTabView.swift` - Pass storageManager to PlanCalendarView
7. `Stride/StrideApp.swift` - Background task registration and scheduling

## Testing Checklist

- [ ] Complete a workout and verify fatigue/injury fields save correctly
- [ ] Manually trigger adaptation from DEBUG menu
- [ ] Verify banner appears on Plan tab after adaptation
- [ ] Tap banner to expand and view details
- [ ] Dismiss banner and verify it doesn't reappear
- [ ] Check that only next 7 days are modified
- [ ] Verify completed workouts are never changed
- [ ] Test with different scenarios:
  - [ ] High fatigue (4-5) → Should reduce volume
  - [ ] Injury flag → Should trigger rest protocol
  - [ ] Excellent performance → Should increase volume slightly
  - [ ] Low completion rate → Should simplify schedule
- [ ] Verify adaptation history is saved and loadable
- [ ] Test background task registration (check device settings)

## Notes

- Background tasks on iOS Simulator may not work reliably - test on physical device
- Background refresh must be enabled in device settings for app
- First adaptation may not run until second Sunday (iOS limitation)
- Adaptation records are kept for 6 months, then automatically pruned
- All adaptations are conservative - prioritizes injury prevention over aggressive training

## Future Enhancements

Potential improvements for future versions:
- User preference for adaptation aggressiveness (conservative vs aggressive)
- View adaptation history timeline
- Undo/revert last adaptation
- Custom adaptation rules per user
- Integration with heart rate zones for more precise recovery assessment
- ML-based prediction of optimal training load
