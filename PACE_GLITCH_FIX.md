# Pace Glitch Fix - Documentation

## Problem Description

When the treadmill was connected, the pace display was bouncing wildly between extreme values (e.g., 13 minutes/km to 28 seconds/km), creating erratic oscillations visible in the pace graph. This was occurring even during steady walking.

## Root Cause

The app was displaying **raw, unfiltered pace data** directly from the treadmill's FTMS (Fitness Machine Service) Bluetooth characteristic. Treadmills can send noisy speed data due to:
- Sensor noise/jitter in the belt speed measurement
- Bluetooth transmission timing variations
- Momentary speed fluctuations as the belt adjusts
- Signal interference or dropped packets

Since pace is the **inverse** of speed (pace = 1000 / speed), small fluctuations in speed become amplified as large swings in pace. For example:
- Speed drops from 3 m/s to 0.5 m/s → Pace jumps from 5:33/km to 33:20/km
- Speed spikes from 3 m/s to 20 m/s → Pace drops from 5:33/km to 0:50/km

## Solution Implemented

### 1. **Exponential Moving Average (EMA) Smoothing**
Created `PaceSmoother.swift` - a dedicated utility that:
- Applies EMA smoothing to speed data before calculating pace
- Uses a smoothing factor (alpha) of 0.2:
  - 20% weight to new sample
  - 80% weight to historical average
- This provides stability while remaining responsive to actual pace changes

### 2. **Low-Speed Filtering**
- Filters out speeds below 0.1 m/s (~0.36 km/h)
- When encountering invalid/very low speeds, the smoother maintains the previous valid pace
- Prevents extreme pace values from glitched sensor readings

### 3. **Graph Smoothing**
Added moving average smoothing to the pace graph visualization:
- 5-sample sliding window average
- Reduces visual jitter while maintaining accurate trend representation

### 4. **Smart Data Preservation**
- **Raw distance values are preserved** - we trust the treadmill's distance sensor
- Only pace/speed values are smoothed for display
- Recorded samples still contain raw data for historical accuracy

## Technical Implementation

### Files Modified:
1. **`Stride/Utilities/PaceSmoother.swift`** (NEW)
   - Exponential moving average implementation
   - Low-speed filtering
   - Reset functionality for new workouts

2. **`Stride/Managers/WorkoutManager.swift`**
   - Integrated `PaceSmoother` instance
   - Applied smoothing in `updateLiveStats()`
   - Reset smoother on workout start/clear

3. **`Stride/Views/RunTab/LiveWorkoutView.swift`**
   - Added `smoothPaceData()` function to pace graph
   - Moving average filter for graph visualization

### Data Flow:
```
Treadmill → FTMS Parser → WorkoutSample (raw) → PaceSmoother → LiveStats (smoothed) → UI Display
                                               ↓
                                        Stored in session.recentSamples (raw for historical accuracy)
```

## Testing

Created `PaceSmootherTests.swift` with test cases covering:
- Reduction of wild fluctuations
- Convergence to stable pace with consistent input
- Low-speed filtering behavior
- Reset functionality

## Expected Behavior After Fix

✅ **Stable pace display** - No more wild oscillations between extreme values
✅ **Smooth graph** - Pace graph shows clean trend line without erratic jumps
✅ **Responsive** - Still reacts to actual pace changes within 5-10 seconds
✅ **Accurate distance** - Distance tracking remains unaffected (uses raw values)

## Smoothing Parameters (Tunable)

If the smoothing needs adjustment:
- **`alpha` in PaceSmoother.swift**: Currently 0.2
  - Lower = more smoothing, less responsive (e.g., 0.1)
  - Higher = less smoothing, more responsive (e.g., 0.3)
  
- **`minSpeedThreshold`**: Currently 0.1 m/s
  - Filters out extremely low speeds that would create invalid pace values

- **Graph window size**: Currently 5 samples
  - Increase for smoother graph line
  - Decrease for more detail

## Notes

- The smoother is reset at the start of each workout to ensure fresh data
- Pace drift calculations still use longer-term averages (unchanged)
- Heart rate and cadence data pass through without smoothing (they're already stable)



