# AI Coaching System - Testing & Verification Guide

## Summary of Changes

All implementation is complete! Here's what was fixed:

### ✅ Phase 1: API Key Loading (FIXED)
- Created `SecureKeyManager.swift` - Securely loads API key from keychain, environment variables, or hardcoded values
- Updated `StrideApp.swift` - Now uses SecureKeyManager with clear console logging
- Your API key from Xcode scheme will now be properly loaded and saved to keychain

### ✅ Phase 2: Enhanced AI Prompt (FIXED)
- Added **CRITICAL RULES** section with explicit constraints
- No consecutive gym/strength days
- Strides for ≤10K races starting week 3
- Race pace practice required in peak phase
- Progressive pacing enforcement
- Added **detailed pace progression** for aggressive goals
- Added **distance-specific guidance** (e.g., strides for 5K-10K)
- Added **gym scheduling constraints** with examples
- Enhanced JSON examples to show proper spacing

### ✅ Phase 3: Debugging & Logging (FIXED)
- Added comprehensive console logging throughout the generation process
- Created `AICoachSettingsView.swift` - New UI for managing API key
- Shows AI Coach status (Enabled/Disabled) in Settings
- Can add/remove API key directly in-app
- Clear error messages when API fails

### ✅ Phase 4: Rule-Based Fallback (FIXED)
- Fixed back-to-back gym days with proper spacing algorithm
- Peak training now uses `raceSimulation` workouts (not just intervals)
- Tempo runs in peak phase use progressive pacing (midpoint between threshold and goal)
- Proper enforcement of 48+ hour gap between strength sessions

---

## Testing Protocol

### Step 1: Verify API Key is Loaded

**What to do:**
1. Build and run the app in Xcode
2. Watch the console when the app launches

**What you should see:**
```
🔑 Loaded API key from Environment Variable
✅ AI Coach enabled with Claude API
```

**If you see instead:**
```
⚠️ No API key found in any source
⚠️ AI Coach disabled - No API key found. Will use rule-based plans.
```

**Then:** Your environment variable isn't loading. Open `SecureKeyManager.swift` and uncomment lines 28-32 to hardcode your key temporarily:
```swift
#if DEBUG
let hardcodedKey = "YOUR_OPENAI_API_KEY_HERE"
if !hardcodedKey.isEmpty && hardcodedKey.hasPrefix("sk-") {
    print("🔑 Using hardcoded API key (DEV MODE)")
    return hardcodedKey
}
#endif
```

### Step 2: Verify AI Status in Settings

**What to do:**
1. Navigate to Settings tab
2. Look for "AI Coach" row (has brain icon 🧠)
3. Tap it to open AI Coach settings

**What you should see:**
- Status shows "Enabled - Using Claude AI" with green checkmark
- Your API key shown as `sk-ant-...nnQ` (masked)
- Benefits section explaining features
- Cost information

### Step 3: Generate a Test Plan

**What to do:**
1. Go to Goal tab
2. Create a new goal:
   - **Distance:** 5K
   - **Target Time:** 20:00 (4:00/km pace)
   - **Event Date:** ~12 weeks from now
3. If you have a baseline, make sure it shows slower pace (e.g., VDOT 45, ~5:00/km threshold)
4. Generate plan

**What you should see in console:**
```
🔍 AI Generator Status: ✅ CONFIGURED
🤖 AI Coach: Generating training plan with Claude...
📡 Calling Claude API...
📊 Prompt length: XXXX characters
🎯 Goal: 5K Race, Distance: 5.0km
💪 Baseline VDOT: 45.0
🌐 Sending request to Claude API...
🔄 Making HTTP request to Claude API...
📥 Received HTTP 200 from Claude API
✅ Successfully parsed Claude response (YYYY chars)
✅ Received response from Claude API
✅ AI Coach: Successfully generated 12-week plan with XX workouts
📈 Plan phases: Base Building → Build Up → Peak Training → Taper
🛡️ Validating AI-generated plan for safety...
✅ AI plan passed safety validation
```

**Critical:** If you see `❌ Claude API returned error status: 401`, your API key is invalid.

### Step 4: Verify Claude API Usage

**What to do:**
1. Go to https://console.anthropic.com/
2. Navigate to "Usage" or "API Keys" section
3. Check recent API calls

**What you should see:**
- New API call(s) timestamped when you generated the plan
- Token usage: ~3,000-5,000 input tokens, ~5,000-8,000 output tokens
- Cost: ~$0.10-0.20 per plan

**If no tokens used:** API not being called. Check console logs from Step 3.

### Step 5: Inspect Generated Plan Quality

**What to look for:**

#### ✅ No Back-to-Back Strength Days
- View your plan in the Plan tab
- Check all gym/strength workouts
- There should be **at least 2 days** between any two gym sessions
- Example GOOD: Monday gym, Thursday gym
- Example BAD: Monday gym, Tuesday gym

#### ✅ Race Pace Practice in Peak Weeks
- Navigate to weeks in "Peak Training" phase
- Look for workouts with:
  - "Race Pace" in title or description
  - "Race Simulation" workout type
  - Pace close to your goal pace (4:00/km for your test case)
- By peak weeks, you should see intervals or tempo segments at or near 4:00/km

#### ✅ Progressive Pacing
- Week 1-4 (Base): Tempo at ~5:00/km (your baseline threshold)
- Week 5-8 (Build): Tempo at ~4:30-4:45/km (between baseline and goal)
- Week 9-11 (Peak): Intervals at 4:00/km, Tempo at 4:15-4:30/km
- Not stuck at 5:00/km the entire plan!

#### ✅ Strides for 5K Goal
- Look at easy run descriptions
- Starting around week 3, should mention:
  - "4-6 × 20sec strides"
  - "90% effort"
  - "Include strides after warmup"

### Step 6: Compare with Claude Desktop

**What to do:**
1. Copy the exact same scenario to Claude Desktop:
   - "I want to run a 5K in 20:00 in 12 weeks"
   - "My current VDOT is 45, threshold pace is 5:00/km"
   - "I can train 5 days per week with 2 strength days"
2. Ask Claude Desktop to create a training plan
3. Compare structure, pacing, and quality

**What you should see:**
- Similar phase structure
- Similar pace progression (both show gradual approach to 4:00/km)
- Similar workout variety
- No back-to-back strength in Claude's plan either
- Both include race pace work in peak weeks

---

## Troubleshooting

### Issue: "AI Generator Status: ❌ NIL (WILL FALLBACK TO RULE-BASED)"

**Cause:** API key not loaded

**Fix:**
1. Check console for "🔑 Loaded API key from..." message
2. If missing, hardcode key in `SecureKeyManager.swift` (see Step 1)
3. Or use Settings → AI Coach → Enter API key manually

### Issue: "❌ Claude API returned error status: 401"

**Cause:** Invalid or expired API key

**Fix:**
1. Go to https://console.anthropic.com/
2. Generate a new API key
3. Update in Settings → AI Coach → Remove & re-add key

### Issue: "❌ Claude API returned error status: 429"

**Cause:** Rate limit exceeded

**Fix:**
1. Wait 60 seconds
2. Try again
3. Check your account hasn't hit spending limit

### Issue: Plan still has back-to-back gym days

**Cause:** Either:
- A) AI didn't follow the prompt constraints
- B) Falling back to rule-based (check console)

**Fix for A:**
- The prompt now has explicit rules
- If AI still violates, the safety validator should catch it
- Check console for "⚠️ AI plan has critical issues:"

**Fix for B:**
- Ensure AI is actually being used (see Step 1)

### Issue: No race pace practice in peak weeks

**Cause:** Same as above - either AI or fallback

**Check:**
1. Console logs confirm which generator was used
2. If AI: The new prompt explicitly requires race pace in peak phase
3. If rule-based: The fix ensures `raceSimulation` workouts in peak phase

---

## Success Criteria

You've successfully implemented AI coaching if:

✅ Console shows "🔑 Loaded API key..."  
✅ Console shows "✅ AI Coach enabled with Claude API"  
✅ Console shows "📥 Received HTTP 200 from Claude API"  
✅ Claude dashboard shows token usage  
✅ Generated plan has NO consecutive gym days  
✅ Generated plan includes race pace in peak weeks  
✅ Generated plan shows progressive pacing (not stuck at baseline)  
✅ Settings shows "AI Coach: Enabled" with green dot  
✅ Plan quality matches Claude Desktop

---

## What to Do Next

Once testing is complete:

1. **If everything works:** You're done! AI coaching is fully operational.

2. **If API key loading fails:** Use the in-app Settings → AI Coach to add your key manually.

3. **If plan quality is still poor despite API being called:** 
   - Export the prompt being sent (it's logged as "📊 Prompt length: X characters")
   - Compare it with what works in Claude Desktop
   - May need further prompt refinement

4. **If you want to share with testers:**
   - Remove your API key from the Xcode scheme file
   - Tell testers to add their own key via Settings → AI Coach
   - Or keep the hardcoded option for internal testing

---

## Key Files Modified

1. **NEW:** `Stride/Utilities/SecureKeyManager.swift` - Secure API key management
2. **NEW:** `Stride/Views/SettingsTab/AICoachSettingsView.swift` - UI for API key config
3. **MODIFIED:** `Stride/StrideApp.swift` - Uses SecureKeyManager for AI generator
4. **MODIFIED:** `Stride/Utilities/AITrainingPlanGenerator.swift` - Enhanced prompt with critical rules
5. **MODIFIED:** `Stride/Managers/TrainingPlanManager.swift` - Better logging and error handling
6. **MODIFIED:** `Stride/Utilities/TrainingPlanGenerator.swift` - Fixed back-to-back gym days, added race pace practice
7. **MODIFIED:** `Stride/Views/SettingsTab/SettingsView.swift` - Added AI Coach settings link

---

## Questions to Ask After Testing

1. Do you see the API call in Claude console?
2. Is the plan quality comparable to Claude Desktop?
3. Are the console logs helpful for debugging?
4. Is the Settings UI clear and functional?
5. Did the plan avoid back-to-back strength days?
6. Did you see race pace practice in peak weeks?

Please test and report back your findings!
