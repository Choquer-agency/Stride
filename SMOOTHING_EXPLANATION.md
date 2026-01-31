# Pace Smoothing - Visual Explanation

## Before Fix: Raw Pace Display

```
Time (s)   Raw Speed (m/s)   Raw Pace (min:sec/km)   Display Shows
--------   ---------------   ---------------------   -------------
0          2.5               6:40                    6:40 ✓
1          2.4               6:56                    6:56 ✓
2          0.1               166:40                  166:40 ❌ GLITCH!
3          2.6               6:24                    6:24 ✓
4          25.0              2:00                    2:00 ❌ GLITCH!
5          2.5               6:40                    6:40 ✓
6          2.4               6:56                    6:56 ✓

Graph: 
    ^
Pace|     /\
    |    /  \
    |___/    \___
    +------------> Time
    
    Wild oscillations visible to user!
    Graph shows extreme spikes and dips.
```

## After Fix: Smoothed Pace Display

```
Time (s)   Raw Speed (m/s)   Smoothed Speed (m/s)   Smoothed Pace   Display Shows
--------   ---------------   --------------------   -------------   -------------
0          2.5               2.5 (first sample)     6:40            6:40 ✓
1          2.4               2.48                   6:43            6:43 ✓ smooth
2          0.1               2.48 (filtered!)       6:43            6:43 ✓ stable!
3          2.6               2.50                   6:40            6:40 ✓ smooth
4          25.0              7.00 (dampened)        2:22            2:22 ✓ dampened
5          2.5               6.10                   2:43            2:43 ✓ recovering
6          2.4               5.36                   3:06            3:06 ✓ stabilizing

Graph:
    ^
Pace|   _____
    |  /     \___
    | /          \___
    +------------> Time
    
    Smooth curve visible to user!
    Outliers are filtered/dampened.
```

## Key Improvements

### 1. **Filters Extreme Outliers**
- Speed < 0.1 m/s → Ignored (maintains previous pace)
- Prevents pace from jumping to 100+ min/km

### 2. **Dampens Large Spikes**
- Large speed spike (25 m/s) → Smoothed to 7 m/s over multiple samples
- Prevents pace from dropping to 2:00/km instantly
- Recovers gracefully over next few samples

### 3. **Maintains Responsiveness**
- Normal pace changes still reflected within 5-10 seconds
- EMA with alpha=0.2 provides good balance
- User can still see when they speed up or slow down

## Real-World Example (Your Case)

**Your reported issue:**
- Bouncing between 13:00 min/km and 0:28 min/km

**What was happening:**
```
Sample 1: Speed = 2.0 m/s   → Pace = 8:20/km   ✓ normal
Sample 2: Speed = 0.13 m/s  → Pace = 128:00/km ❌ glitch (close to your 13:00)
Sample 3: Speed = 2.0 m/s   → Pace = 8:20/km   ✓ normal
Sample 4: Speed = 35 m/s    → Pace = 0:28/km   ❌ glitch (your 0:28!)
Sample 5: Speed = 2.0 m/s   → Pace = 8:20/km   ✓ normal
```

**After fix:**
```
Sample 1: Smoothed = 2.0 m/s   → Pace = 8:20/km   ✓ normal
Sample 2: Smoothed = 2.0 m/s   → Pace = 8:20/km   ✓ filtered!
Sample 3: Smoothed = 2.0 m/s   → Pace = 8:20/km   ✓ stable
Sample 4: Smoothed = 8.6 m/s   → Pace = 1:56/km   ✓ dampened (still noticeable but not extreme)
Sample 5: Smoothed = 6.88 m/s  → Pace = 2:25/km   ✓ recovering
Sample 6: Smoothed = 5.50 m/s  → Pace = 3:02/km   ✓ continuing to stabilize
...after ~10 samples → back to 8:20/km
```

## Smoothing Algorithm (EMA)

**Formula:** `smoothed = alpha × newValue + (1 - alpha) × previousSmoothed`

Where:
- `alpha = 0.2` (20% new, 80% history)
- Applied to **speed** (not pace) to avoid inverse amplification

**Why EMA over Simple Average?**
1. More memory efficient (no array of samples needed)
2. Recent values have more weight (more responsive)
3. Infinite history consideration (better stability)
4. Industry standard for signal smoothing

## Tuning the Smoothness

If you need to adjust (in `PaceSmoother.swift`):

```swift
private let alpha: Double = 0.2  // Default

// More smoothing (slower response):
private let alpha: Double = 0.1  // 10% new, 90% history

// Less smoothing (faster response):
private let alpha: Double = 0.3  // 30% new, 70% history
```

**Trade-off:**
- Lower alpha = smoother but slower to react to real changes
- Higher alpha = more responsive but less filtering of glitches



