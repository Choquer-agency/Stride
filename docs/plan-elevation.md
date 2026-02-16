# Plan Elevation: Edit, Analyze, Archive

## Context

Users build great training plans but life changes — new jobs, injuries, or simply finding the plan too easy/hard. Currently there's no way to adjust a plan after creation (the "Re-run Plan" button is a stub), no performance analysis, and old plans are deleted when new ones are created. This work adds three capabilities: natural-language plan editing with approve/deny, AI performance analysis with actionable recommendations, and a previous plans archive.

---

## Phase 0 — Foundation (must complete first)

All three features depend on plan archiving infrastructure and new API schemas.

### 0.1: Add archive properties to TrainingPlan model
**File:** `StrideApp/Models/TrainingPlan.swift`
- Add `var isArchived: Bool = false`
- Add `var archivedAt: Date?`
- Add `var archiveReasonRaw: String?` (values: "completed", "replaced", "abandoned")
- Add computed `archiveReason: ArchiveReason?` property
- Update `init()` — `isArchived` defaults to `false` (SwiftData lightweight migration handles existing data)

### 0.2: Add ArchiveReason enum
**File:** `StrideApp/Models/Enums.swift`
- Add `enum ArchiveReason: String, Codable` with cases: `.completed`, `.replaced`, `.abandoned`
- Add `displayName` computed property

### 0.3: Update PlanTabContainer to filter archived plans
**File:** `StrideApp/Views/MainTabView.swift`
- Change `@Query` to filter `isArchived == false`
- Replace `cleanupExtraPlans()` with `archiveExtraPlans()` — sets `isArchived = true`, `archivedAt = Date()`, `archiveReason = .replaced` instead of deleting

### 0.4: New API schemas
**File:** `app/models/schemas.py`
- Add `PlanEditRequest`: `race_type`, `race_date`, `race_name`, `goal_time`, `start_date`, `current_plan_content` (str), `edit_instructions` (str)
- Add `CompletedWorkoutData`: `date`, `workout_type`, `planned_distance_km`, `actual_distance_km`, `planned_pace_description`, `actual_avg_pace_sec_per_km`, `completion_score`, `feedback_rating`
- Add `PerformanceAnalysisRequest`: `race_type`, `race_date`, `goal_time`, `current_weekly_mileage`, `fitness_level`, `completed_workouts` (list), `weeks_into_plan`, `total_plan_weeks`
- Add `PerformanceAnalysisResponse`: `overall_assessment`, `adherence_percentage`, `patterns` (list[str]), `recommendations` (list[str]), `suggested_edit_instruction` (optional str), `risk_level`

### 0.5: Edit prompt template
**File (new):** `app/prompts/coach_edit.txt`
- Instructs AI to receive existing plan + edit request, make targeted modifications
- Preserves exact formatting so `PlanParser` can still parse the output
- Outputs complete modified plan (not a diff)
- Starts with a coaching overview explaining what changed and why

---

## Phase 1 — Plan Editing Flow
**Depends on:** Phase 0

### 1.1: API — `/api/edit-plan` endpoint (SSE streaming)
**File:** `app/routes/plans.py`
- New `POST /api/edit-plan` accepting `PlanEditRequest`
- Validates dates, builds prompts, streams response via SSE (same pattern as `/api/generate-plan`)

**File:** `app/services/prompt_builder.py`
- Add `get_edit_system_prompt(race_type)` — combines the race-specific coach prompt with `coach_edit.txt`
- Add `build_edit_user_prompt(request: PlanEditRequest)` — formats current plan content + edit instructions into a structured prompt with race context

### 1.2: iOS — API models & service for edit
**File:** `StrideApp/Models/APIModels.swift`
- Add `PlanEditRequest` Codable struct with snake_case CodingKeys

**File:** `StrideApp/Services/APIService.swift`
- Add `editPlan(request:onChunk:onComplete:onError:)` — identical SSE streaming pattern as `generatePlan()` but hitting `/api/edit-plan`
- Add `static func buildEditRequest(from plan: TrainingPlan, editInstructions: String) -> PlanEditRequest`

### 1.3: iOS — PlanEditViewModel
**File (new):** `StrideApp/ViewModels/PlanEditViewModel.swift`
- `@Published` state: `editInstructions`, `isGenerating`, `streamingContent`, `isComplete`, `error`
- Holds reference to `currentPlan: TrainingPlan`
- `submitEdit()` — calls `apiService.editPlan()`, streams content
- `processEditedPlan(content:)` — uses `PlanParser.parse()` to build a new `TrainingPlan` **in memory** (not inserted into ModelContext yet). Copies over `raceType`, `raceDate`, `raceName`, `goalTime`, `startDate`, `fitnessLevel`, `currentWeeklyMileage`, `longestRecentRun` from current plan
- `approvePlan(context:)` — archives current plan (`.replaced`), inserts new plan into context
- `discardEdit()` — resets all state, discards in-memory plan

### 1.4: iOS — Edit flow UI

**File (new):** `StrideApp/Views/Plan/PlanEditInputView.swift`
- Sheet presented from PlanView
- Title: "Edit Your Plan"
- `TextEditor` for natural language edit instructions
- Example suggestion chips (tappable to pre-fill): "Remove Tuesday runs", "Cut volume in half", "Add one more run per week", "Increase intensity 20%"
- "Submit" button (disabled when instructions empty)

**File:** `StrideApp/Views/Onboarding/PlanGenerationView.swift`
- Add optional parameters: `secondaryButtonTitle: String?`, `onSecondaryAction: (() -> Void)?`, `title: String` (default: "PERSONALIZING YOUR TRAINING PLAN")
- When `secondaryButtonTitle` is provided, show two buttons at completion instead of one:
  - Primary: "Approve Plan" (green/primary)
  - Secondary: "Keep Current Plan" (outline style)
- This reuses the existing streaming display, progress bar, and timer logic

### 1.5: iOS — Wire up PlanView menu
**File:** `StrideApp/Views/Plan/PlanView.swift`
- Add `@State private var showEditInput = false` and `@State private var showEditGeneration = false`
- Add `@State private var editViewModel: PlanEditViewModel?`
- Change "Re-run Plan" button → "Edit Plan" with pencil icon, action sets `showEditInput = true`
- Add `.sheet(isPresented: $showEditInput)` → `PlanEditInputView`
- On submit: create `PlanEditViewModel`, set instructions, show `PlanEditGenerationView` as `.fullScreenCover`
- `PlanEditGenerationView` wraps `PlanGenerationView` with the two-button config, wired to `approvePlan()`/`discardEdit()`

---

## Phase 2 — AI Performance Analysis
**Depends on:** Phase 0 (API schemas) + Phase 1 (edit flow, since "Apply Recommendation" feeds into edit)

### 2.1: API — Analysis prompt & endpoint
**File (new):** `app/prompts/coach_analysis.txt`
- System prompt instructing AI to analyze workout data and return structured JSON
- Expects: race goal, timeline, completed workout metrics (planned vs actual, scores, ratings)
- Returns: overall assessment, adherence %, patterns, recommendations, optional suggested edit instruction

**File:** `app/routes/plans.py`
- New `POST /api/analyze-performance` accepting `PerformanceAnalysisRequest`, returning `PerformanceAnalysisResponse`
- Non-streaming (JSON response) — uses `OpenAIClient.generate_plan()` (non-streaming method)
- Parse AI's JSON response into `PerformanceAnalysisResponse`
- Use `response_format: {"type": "json_object"}` for reliable JSON output

**File:** `app/services/prompt_builder.py`
- Add `build_performance_analysis_prompt(request)` — formats completed workout data as a readable table

### 2.2: iOS — API models & service for analysis
**File:** `StrideApp/Models/APIModels.swift`
- Add `CompletedWorkoutData`, `PerformanceAnalysisRequest`, `PerformanceAnalysisResponse` Codable structs

**File:** `StrideApp/Services/APIService.swift`
- Add `analyzePerformance(request:) async throws -> PerformanceAnalysisResponse` — standard POST + JSON decode (same pattern as `analyzeConflicts()`)
- Add `static func buildPerformanceRequest(from plan: TrainingPlan) -> PerformanceAnalysisRequest` — extracts completed non-rest workouts with actual metrics, calculates `weeksIntoPlan`

### 2.3: iOS — PerformanceAnalysisViewModel
**File (new):** `StrideApp/ViewModels/PerformanceAnalysisViewModel.swift`
- `hasEnoughData: Bool` — requires >= 3 completed workouts
- `fetchAnalysis()` — calls API, sets `analysis: PerformanceAnalysisResponse?`
- `suggestedEditAvailable: Bool` — checks if `analysis?.suggestedEditInstruction != nil`

### 2.4: iOS — Performance analysis UI
**File (new):** `StrideApp/Views/Plan/PerformanceAnalysisView.swift`
- Sheet showing: overall assessment, adherence ring/bar, patterns as bullet list, recommendations as cards
- "Apply Recommendation" button (shown when `suggestedEditInstruction` exists) — pre-fills edit instructions and triggers the Phase 1 edit flow

### 2.5: iOS — PlanView integration
**File:** `StrideApp/Views/Plan/PlanView.swift`
- Add "Performance Analysis" to three-dot menu (disabled when < 3 completed workouts)
- Add `@State private var showPerformanceAnalysis = false`
- Wire `.sheet` to `PerformanceAnalysisView`
- When "Apply Recommendation" is tapped, dismiss analysis sheet → open edit flow with pre-filled instructions

---

## Phase 3 — Previous Plans Archive
**Depends on:** Phase 0 only (can run in parallel with Phases 1 & 2)

### 3.1: ArchivedPlansView
**File (new):** `StrideApp/Views/Settings/ArchivedPlansView.swift`
- `@Query` filtering `isArchived == true`, sorted by `archivedAt` descending
- List of `ArchivedPlanRow` items with NavigationLink to detail
- Empty state when no archived plans
- Swipe to permanently delete

### 3.2: ArchivedPlanRow
**File:** Same as 3.1
- Displays: race name (or race type), date range (startDate – raceDate), archive reason badge, completion progress at time of archival

### 3.3: ArchivedPlanDetailView
**File (new):** `StrideApp/Views/Settings/ArchivedPlanDetailView.swift`
- Read-only view of the archived plan
- Approach: Add `readOnly: Bool = false` parameter to existing `PlanView`
- When `readOnly == true`: hide three-dot menu, disable workout completion toggles, show "Archived Plan" banner

### 3.4: Settings integration
**File:** `StrideApp/Views/Settings/SettingsView.swift`
- Add "Training History" section with "Previous Plans" NavigationLink → `ArchivedPlansView`

### 3.5: Update delete confirmation to offer archive
**File:** `StrideApp/Views/Plan/PlanView.swift`
- Change delete alert to `confirmationDialog` with three options: "Archive Plan", "Delete Permanently", "Cancel"

---

## Dependency Graph

```
Phase 0 (Foundation) ─────────────────────────────────
  0.1  TrainingPlan model ──┐
  0.2  ArchiveReason enum ──┤
  0.3  PlanTabContainer ────┤ (needs 0.1)
  0.4  API schemas ─────────┤
  0.5  coach_edit.txt ──────┘
         │                   │                │
         ▼                   ▼                ▼
   Phase 1 (Edit)     Phase 3 (Archive)   Phase 2 API
   1.1 API endpoint   3.1 ArchivedPlans   2.1 API endpoint
        │              3.2 Row                  │
   1.2 iOS API/svc    3.3 Detail view     2.2 iOS API/svc
        │              3.4 Settings             │
   1.3 ViewModel       3.5 Delete→Archive  2.3 ViewModel
        │                                       │
   1.4 UI views                            2.4 Analysis UI
        │                                       │
   1.5 PlanView wiring ◄──────────────── 2.5 PlanView integration
                                          (needs edit flow from 1.5)
```

**Parallel lanes:**
- **Lane A (API):** 0.4 → 0.5 → 1.1 + 2.1 (in parallel)
- **Lane B (iOS models/archive):** 0.1 → 0.2 → 0.3 → Phase 3 (all)
- **Lane C (iOS edit flow):** After 0.1 + 1.1 done → 1.2 → 1.3 → 1.4 → 1.5
- **Lane D (iOS analysis):** After 2.1 + 1.5 done → 2.2 → 2.3 → 2.4 → 2.5

**Solo engineer order:** Phase 0 → Phase 3 → Phase 1 → Phase 2

---

## Verification

1. **Plan editing E2E:** Three-dot menu → "Edit Plan" → type "Remove Tuesday runs and reduce distances by 10%" → submit → see coaching overview streaming → "Approve Plan" → verify plan updated, old plan archived
2. **Keep current:** Same flow but tap "Keep Current Plan" → verify original plan unchanged, no archive created
3. **Performance analysis:** Complete 3+ workouts → three-dot menu → "Performance Analysis" → verify assessment, patterns, recommendations render → tap "Apply Recommendation" → verify edit flow opens with pre-filled instruction
4. **Archive:** Settings → Previous Plans → verify archived plans appear with correct reason badges → tap to view read-only plan → verify no edit/completion actions available
5. **Delete vs archive:** Three-dot menu → "Delete Plan" → verify dialog offers "Archive" and "Delete Permanently" options
6. **Migration:** Install update over existing app with a plan → verify existing plan gets `isArchived = false` default and continues working
