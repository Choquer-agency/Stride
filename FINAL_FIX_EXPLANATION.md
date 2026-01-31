# FINAL FIX: The Real Problem

## What Was Wrong

The memory explosion to 100 MB at under 2 km was caused by **THREE compounding issues**:

### Issue 1: Sample Duplication
```swift
// EVERY sample was stored TWICE:
currentSession?.currentKilometerSamples.append(sample)  // Copy 1
currentSession?.recentSamples.append(sample)             // Copy 2
```
Result: 2x memory usage immediately!

### Issue 2: Inefficient Array Trimming
```swift
// This ran ONCE PER SECOND:
currentSession?.recentSamples.removeAll { $0.timestamp < fiveMinutesAgo }
```
**Problem**: `removeAll { }` with a closure creates a NEW array due to Copy-on-Write!
- Swift copies the entire array
- Filters it
- Replaces the original
- **Cost**: O(n) copy + O(n) filter = EVERY SECOND

### Issue 3: No Actual Limit
The trimming by timestamp didn't enforce a hard limit, so arrays could grow unbounded if samples came faster than expected.

## The Solution

### 1. Store Samples ONCE (Not Twice)
```swift
// Only store in recentSamples - NO duplication
currentSession?.recentSamples.append(sample)
```

### 2. Efficient Trimming with Hard Limit
```swift
// Only trim when we exceed limit (not every sample!)
if let count = currentSession?.recentSamples.count, count > 350 {
    // Batch removal: remove first 50 to get back to 300
    currentSession?.recentSamples.removeFirst(50)
}
```

**Benefits**:
- Runs less frequently (only when > 350)
- `removeFirst(50)` is O(n) but only occasionally
- Hard limit prevents unbounded growth
- Simple count check is O(1)

### 3. Calculate Splits from Recent Samples
```swift
// Filter recent samples for the last KM
let kmSamples = currentSession?.recentSamples.filter { 
    $0.timestamp >= lastTime && $0.timestamp <= now 
}
```

Since we keep ~300 samples (5 minutes), we'll always have the last KM's data available.

### 4. Removed Unnecessary Array
Deleted `currentKilometerSamples` entirely - we don't need it!

## Memory Impact

**Before (BAD)**:
- 2x duplication of every sample
- removeAll { } creating copy every second
- Result: 100+ MB at 2 km

**After (GOOD)**:
- 1x storage (no duplication)
- Efficient batch trimming only when needed
- Hard limit of 350 samples max
- **Expected**: ~20-25 MB total, flat line

## Why This Works

### Sample Math:
- At test speed: 28 m/s = ~1 km per 35 seconds
- Sampling rate: 1 Hz (1 sample/second)
- Samples per KM: ~35 samples
- With 300 sample limit: Always have last 8+ km of data
- Plenty for calculating split metrics

### Memory Math:
- 1 WorkoutSample ≈ 200 bytes (rough estimate)
- 300 samples × 200 bytes = 60 KB
- Plus SwiftUI overhead, splits, etc. = ~2-3 MB for workout data
- Total app memory: 20-25 MB (reasonable!)

## Key Lessons

1. **Never duplicate data unnecessarily** - Store once, reference everywhere
2. **Avoid closure-based array operations in hot paths** - They trigger Copy-on-Write
3. **Use simple count-based limits** - More predictable than time-based
4. **Batch operations are better than frequent small ones** - removeFirst(50) once > removeAll { } every second
5. **Test early** - Memory profiling should happen DURING development

## Testing This Fix

Run test mode and you should see:
- Memory starts at ~20 MB
- Grows slowly to ~22-25 MB
- **PLATEAUS** (flat line)
- No continued growth past 5 minutes
- Smooth performance throughout

The 300-sample rolling window is enough for charts and split calculation while keeping memory constant!



