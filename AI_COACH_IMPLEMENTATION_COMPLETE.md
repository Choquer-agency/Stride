# AI Coach Implementation Complete

## Summary

Successfully transformed Stride from a rule-based training plan generator to an **AI-first coaching system** where Claude acts as the primary coach, making real training decisions about paces, workouts, and progression.

## What Changed

### Before (Old Architecture)
- Rule-based system generated 100% of training plans
- Claude only polished workout titles/descriptions (cosmetic)
- No intelligence in pace progression or goal alignment
- Plans ignored ambitious goals (e.g., sub-20 5K with VDOT 45)

### After (New Architecture)
- **Claude is the coach** - generates complete training plans from scratch
- Claude sees your baseline fitness AND your goal
- Claude creates progressive pace strategies to bridge fitness gaps
- Rule-based system is now just a safety validator and fallback
- Plans include safety warnings if aggressive

## Files Created

1. **`AITrainingPlanGenerator.swift`** - Core AI coaching engine
   - Generates complete training plans using Claude API
   - Builds comprehensive coaching prompts with:
     - Current fitness (VDOT, baseline paces)
     - Goal details and gap analysis
     - Training constraints and preferences
   - Parses JSON responses into TrainingPlan objects
   - Handles API errors with graceful fallbacks

2. **`PlanSafetyValidator.swift`** - Post-generation safety checks
   - Validates weekly mileage progression (<10% increases)
   - Checks for back-to-back hard workouts
   - Validates paces aren't dangerously fast (>20% faster than baseline)
   - Ensures proper long run distances and taper structure
   - Returns warnings (shown to user) and critical issues (triggers fallback)

## Files Modified

1. **`TrainingPlanManager.swift`**
   - Now uses AI-first generation logic
   - Tries AI coach first, falls back to rule-based if:
     - API call fails
     - Safety validation finds critical issues
   - Stores warnings in `planWarnings` array for UI display
   - Changed from `llmRefiner` to `aiGenerator` throughout

2. **`StrideApp.swift`**
   - Updated initialization to create `AITrainingPlanGenerator`
   - Reads `ANTHROPIC_API_KEY` from environment
   - Passes AI generator to TrainingPlanManager

## How It Works

### AI-First Generation Flow

```
1. User creates goal (e.g., sub-20 5K)
2. User completes baseline test (e.g., VDOT 45, 5:00/km tempo)
3. System calls Claude with:
   - "Current fitness: 5:00/km tempo pace"
   - "Goal: 4:00/km race pace (20% faster)"
   - "Create progressive 12-week plan"
4. Claude generates JSON plan with:
   - Week-by-week workouts
   - Progressive tempo paces: 5:00 → 4:45 → 4:30 → 4:15
   - Race pace practice at 4:00/km in peak phase
5. Safety validator checks plan
6. Plan saved and shown to user
```

### Safety Validation

After Claude generates a plan, the validator checks:
- **Critical Issues** (trigger fallback):
  - Weekly mileage increases >15%
  - Hard workout immediately after long run
  - Tempo pace >20% faster than baseline
  - Long runs >42km
  
- **Warnings** (shown but allowed):
  - Weekly mileage increases 10-15%
  - Back-to-back hard workouts
  - Tempo pace 15-20% faster than baseline
  - >3 hard workouts per week
  - Insufficient taper

### Fallback Strategy

The system gracefully falls back to rule-based plans if:
1. No API key configured → rule-based (silent)
2. API call fails (network, rate limit) → rule-based + warning
3. Invalid JSON response → rule-based + warning
4. Critical safety issues → rule-based + warning
5. User always gets a valid plan

## API Usage & Cost

- Model: `claude-3-5-sonnet-20241022`
- Tokens per plan: ~2000-3000 input, ~4000-6000 output
- Cost estimate: ~$0.10-0.20 per plan generation
- Rate: 1 plan generation per user goal creation

## Testing Your Sub-20 5K Scenario

With your Claude API key configured:

1. **Create Goal**: 5K in <20:00 (4:00/km pace)
2. **Baseline Test**: Shows VDOT 45, 5:00/km tempo pace
3. **Generate Plan**: Claude will see the 1:00/km gap
4. **Expected Result**:
   - Base phase: 5:00/km tempo (build aerobic base)
   - Build phase: 4:45-4:30/km tempo (progressive overload)
   - Peak phase: 4:15/km tempo + 4:00/km race intervals
   - Taper phase: Goal pace practice at 4:00/km
5. **Safety Check**: May show warning "aggressive progression" but will allow plan

## How to Enable AI Coach

### Option 1: Environment Variable (Recommended)
In Xcode: Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables
- Name: `ANTHROPIC_API_KEY`
- Value: `sk-ant-...your-key...`

### Option 2: Hardcode (Quick Testing)
Edit `StrideApp.swift` line 30:
```swift
return AITrainingPlanGenerator(apiKey: "sk-ant-your-key-here", provider: .anthropic)
```

## Verification

To verify AI coach is working:
1. Generate a plan with ambitious goal
2. Check console logs for:
   - `🤖 AI Coach: Generating training plan with Claude...`
   - `✅ AI Coach: Successfully generated N-week plan`
   - `🛡️ Validating AI-generated plan for safety...`
3. Check plan has progressive paces (not all baseline paces)
4. If you see `📋 Falling back to rule-based plan...`, check API key

## Benefits of AI Coach

1. **Intelligent**: Understands fitness gaps and creates realistic progressions
2. **Personalized**: Considers your baseline, goal, availability, equipment
3. **Adaptive**: Can adjust strategy based on aggressive vs. achievable goals
4. **Safe**: Validated for injury prevention rules
5. **Reliable**: Falls back to rule-based if AI unavailable

## What Rule-Based System Still Does

- **Gym workout exercise selection** (too complex for JSON API)
- **Movement blocks** (warmup/cooldown routines)
- **Fallback plans** (when AI fails)
- **Safety validation** (checks AI plans)

The rule-based system is now a safety net, not the primary coach.

## Next Steps

1. Add your Claude API key to enable AI coaching
2. Test with your sub-20 5K goal + baseline
3. Review the generated plan's progressive paces
4. Check for any safety warnings in the UI
5. Enjoy having an intelligent AI coach! 🎉
