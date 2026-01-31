# Memory Optimization Testing Guide

## Quick Test (2-3 minutes)

### 1. Start Test Workout
1. Open the app
2. Go to "Run" tab
3. Tap "Start test workout" button
4. Open Xcode's Debug Navigator (⌘+7)
5. Watch the Memory graph

### 2. What to Look For

#### ✅ Success Indicators:
- Memory climbs initially to ~2 MB
- Memory **plateaus** (flat line) after 5-10 km
- No continued growth past 30 km
- App remains smooth and responsive
- Frame rate stays at 60 fps

#### ❌ Failure Indicators:
- Memory continuously climbing
- Slowdown after 27-30 km  
- App becomes laggy
- Frame drops

### 3. Monitor Console
Look for these logs every kilometer:
```
Split 1: 240.5 seconds (cleared 1000 samples from memory)
Split 2: 238.2 seconds (cleared 995 samples from memory)
Split 3: 242.1 seconds (cleared 1002 samples from memory)
```

This confirms samples are being deleted after each KM.

## Detailed Xcode Instruments Test

### Setup
1. In Xcode: Product → Profile (⌘+I)
2. Choose "Allocations" template
3. Click Record

### Test Steps
1. Start test workout in app
2. Let run to 35+ km (~3 minutes)
3. Stop workout
4. Stop recording in Instruments

### Analysis
1. Look at "All Heap & Anonymous VM" graph
2. **Expected**: Flat line after initial ramp-up
3. Click "Statistics" view
4. Search for "WorkoutSample"
5. **Expected**: Max ~1300 instances (300 recent + 1000 current KM)

### Memory Targets
- **Peak memory**: < 5 MB
- **Sustained memory**: ~2 MB
- **WorkoutSample instances**: < 1500 at any time
- **Growth rate**: 0 bytes/sec after 5 km

## Functional Verification Checklist

After running test workout to 30+ km, verify:

### Live Workout View
- [ ] Pace graph displays correctly (last 5 min window)
- [ ] Distance shows accurately  
- [ ] Time updates smoothly
- [ ] Splits table populates each kilometer
- [ ] Pace drift calculation shows percentage
- [ ] Heart rate zone displays (if available)
- [ ] No lag when scrolling splits

### Workout Summary (After Stopping)
- [ ] Total distance correct
- [ ] Total time correct
- [ ] Average pace calculated properly
- [ ] All splits listed with times
- [ ] Charts render (pace, distance, speed)
- [ ] Can save with title/notes

### History View
- [ ] Saved workout appears in list
- [ ] Opening workout shows all data
- [ ] Splits are preserved
- [ ] Charts display correctly
- [ ] Cadence shown (if available)

## Real Treadmill Test

If you have access to a Bluetooth treadmill:

1. Connect treadmill via Bluetooth settings
2. Start real workout
3. Run for 10+ km
4. Monitor memory in Xcode Debug Navigator
5. Verify all data captured correctly
6. Stop and save workout
7. Check saved workout has all metrics

## Performance Benchmarks

| Distance | Memory Usage | Frame Rate | Response Time |
|----------|--------------|------------|---------------|
| 0 km     | ~0.5 MB      | 60 fps     | Instant       |
| 10 km    | ~2 MB        | 60 fps     | Instant       |
| 20 km    | ~2 MB        | 60 fps     | Instant       |
| 30 km    | ~2 MB        | 60 fps     | Instant       |
| 42 km    | ~2 MB        | 60 fps     | Instant       |

All values should remain **constant** regardless of distance.

## Troubleshooting

### If Memory Still Growing:

1. Check console for "cleared X samples" messages
   - If missing: `checkForSplit()` not clearing samples
   
2. Search code for `.samples` references
   - Should only be in legacy fallback code
   
3. Verify `recentSamples` trimming
   - Should max out at ~300 samples
   - Check `addSample()` method

### If Data Missing:

1. Check splits have enhanced metrics
   - avgHeartRate, avgCadence, avgSpeed
   
2. Verify `calculateEnhancedSplits()` in TestDataGenerator
   - Should calculate from all samples before discarding

3. Check WorkoutDetailView fallback logic
   - Should use splits first, then recentSamples

## Success Criteria Summary

✅ **Memory**: Flat line at ~2 MB after 5 km  
✅ **Performance**: 60 fps maintained throughout  
✅ **Data**: All metrics preserved in splits  
✅ **Functionality**: Charts, splits, summary all work  
✅ **Storage**: Workouts < 50 KB each  

## Next Steps

Once testing confirms:
1. Delete this testing guide (or keep for documentation)
2. Consider adding analytics to track memory usage
3. Test on older devices (iPhone 8, etc.)
4. Profile battery usage during long workout
5. Consider ultramarathon scenarios (100+ km)

## Questions to Answer

- [ ] Does memory stay flat past 42 km (marathon)?
- [ ] Is 5-minute chart window sufficient for users?
- [ ] Should we make rolling window configurable?
- [ ] Do we need partial split data (current KM progress)?
- [ ] Should we export raw samples as option?



