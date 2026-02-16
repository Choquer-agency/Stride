# Stride Community — Full Implementation Plan

## Context

Stride is a treadmill running coach app (Assault Runner focused) with AI-generated training plans, live run tracking via Bluetooth FTMS, and personal stats. Users currently train in isolation — all run data lives locally on-device (SwiftData), and the backend only stores user accounts.

The running community trend is massive, and there's a clear opportunity to build retention, virality, and brand loyalty through community features: leaderboards, achievements, weekly races, events, and physical rewards. This plan lays out the full vision in 6 phases, each independently deployable.

**Critical architecture gap:** Runs are 100% local on iOS. The backend has zero run data. Phase 1 must solve this before anything else is possible.

### Key Decisions
- **Tab order**: Run, Plan, Stats, **Community**, Profile (5 tabs, community in 4th position)
- **Run verification**: **Bluetooth-connected runs only** count for leaderboards — no manual entries, prevents cheating entirely
- **Weekly races**: **Explicit join + run** model — users opt into a race first, then qualifying runs during the window count
- **Physical rewards**: **Deferred** — build the full badge/achievement system now, physical reward fulfillment comes in a later phase once user volume justifies it

---

## Phase 1: Run Sync Foundation

> **Goal:** Get run data onto the server. This is the prerequisite for every community feature.

### Backend

**New files:**
- `app/models/run.py` — `runs` table mirroring iOS RunLog fields
  - `id` (UUID, uses iOS-generated ID for deduplication)
  - `user_id` (FK → users), `completed_at`, `distance_km`, `duration_seconds`, `avg_pace_sec_per_km`, `km_splits_json`
  - `feedback_rating`, `notes`
  - Denormalized plan context: `planned_workout_title`, `planned_workout_type`, `planned_distance_km`, `completion_score`, `plan_name`, `week_number`
  - Run verification: `data_source` ("bluetooth_ftms" | "manual"), `treadmill_brand` — **only bluetooth_ftms runs are eligible for leaderboards**
  - `is_leaderboard_eligible: Bool` — server-side flag set based on `data_source == "bluetooth_ftms"`
  - `synced_at` timestamp

- `app/models/community_schemas.py` — Pydantic schemas: `RunSyncPayload`, `RunBatchSyncRequest`, `RunBatchSyncResponse`

- `app/routes/runs.py` — Endpoints:
  - `POST /api/runs/sync` — Batch upload runs, `ON CONFLICT (id) DO NOTHING` for dedup, returns `synced_count`
  - `GET /api/runs` — User's synced runs (paginated, with `since` filter)

**Modify:**
- `app/models/user.py` — Add `leaderboard_opt_in` (bool, default false), `display_name` (str, nullable)
- `app/models/auth_schemas.py` — Add new fields to `ProfileUpdateRequest` and `UserResponse`
- `app/routes/auth.py` — Handle new profile fields in `update_profile`
- `app/main.py` — Register `runs_router`

### iOS

**New files:**
- `StrideApp/Services/RunSyncService.swift` — Singleton that:
  - Fetches un-synced RunLogs (where `syncedToServer == false`)
  - Batches into `RunBatchSyncRequest` and POSTs to `/api/runs/sync`
  - Marks synced on success, queues retry on failure
  - Triggered after each run save + on app launch

- `StrideApp/Models/SyncModels.swift` — Codable request/response models for sync endpoint

**Modify:**
- `StrideApp/Models/RunLog.swift` — Add `syncedToServer: Bool = false` property
- `StrideApp/Views/MainTabView.swift` — Trigger `RunSyncService.shared.syncPendingRuns()` after `saveRun()`
- `StrideApp/App/StrideApp.swift` — Trigger full sync on app launch after auth
- `StrideApp/Views/Profile/ProfileView.swift` or `SettingsView.swift` — Add "Community" settings section: leaderboard opt-in toggle, display name field
- `StrideApp/Models/AuthModels.swift` — Add `leaderboardOptIn`, `displayName` to user models

### Privacy & Consent
- Leaderboard participation is **opt-in** (default off)
- `display_name` is separate from real name for privacy
- Profile photo on leaderboards uses existing server-stored photo
- Users can always see their own rank, but are invisible to others unless opted in

---

## Phase 2: Community Tab & Leaderboards

> **Goal:** A new Community tab with yearly distance and best-time leaderboards.

### Backend

**New files:**
- `app/models/personal_best.py` — `personal_bests` table: pre-computed fastest times per distance category per user (avoids expensive JSON parsing on every query)
  - `user_id`, `distance_category` ("5K", "10K", "HM", "FM", "50K"), `time_seconds`, `achieved_at`, `run_id`
  - Unique constraint on `(user_id, distance_category)`, index on `(distance_category, time_seconds)`

- `app/services/leaderboard_service.py` — Service class:
  - `compute_personal_bests(user_id, run)` — Called after each sync, updates PB if faster
  - `get_yearly_distance_leaderboard(year, limit, offset, gender?, age_group?)` — `SUM(distance_km)` grouped by user
  - `get_best_time_leaderboard(category, limit, offset, gender?, age_group?)` — Query from PBs table
  - `get_user_rank(user_id, leaderboard_type)` — Find user's position

- `app/routes/community.py` — Endpoints:
  - `GET /api/community/leaderboards/yearly-distance?year=&limit=&offset=&gender=&age_group=`
  - `GET /api/community/leaderboards/best-time?category=&limit=&offset=&gender=&age_group=`
  - Returns: entries list + `your_rank` + `your_value` + `total_participants`

**Modify:**
- `app/routes/runs.py` — Trigger `compute_personal_bests()` after run sync
- `app/main.py` — Register `community_router`

### iOS

**New files:**
- `StrideApp/Views/Community/CommunityView.swift` — Top-level community tab:
  - Segment picker: "Distance" | "5K" | "10K" | "HM" | "Marathon" | "Ultra"
  - Filter pills: "All" | "Men" | "Women" | "My Age Group"
  - Leaderboard list with sticky "Your Position" card at bottom

- `StrideApp/Views/Community/LeaderboardCardView.swift` — Individual row:
  - Rank (BarlowCondensed), profile photo (circle), display name (Inter), value
  - Top 3: gold/silver/bronze accent
  - Current user row highlighted with light stridePrimary background

- `StrideApp/ViewModels/CommunityViewModel.swift` — Manages leaderboard type, filters, pagination, loading state

- `StrideApp/Models/CommunityModels.swift` — Codable models for leaderboard API

**Modify:**
- `StrideApp/Views/MainTabView.swift` — Add 5th `.community` tab (order: run=0, plan=1, stats=2, community=3, profile=4), adjust pill width
- `StrideApp/Views/Components/StrideIcons.swift` — Add community icon
- `StrideApp/Services/APIService.swift` — Add `fetchLeaderboard()` method

### Leaderboard Details
- **Yearly Distance**: Total km run in current year, resets Jan 1. Shows km value. Only Bluetooth-verified runs counted.
- **Best Time**: Fastest consecutive splits for each distance. Computed from `km_splits_json` server-side (same algorithm as existing `StatsViewModel.fastestConsecutiveTime`). Only Bluetooth-verified runs eligible.
- **Filters**: Gender (from user profile), age group (computed from DOB: 18-29, 30-39, 40-49, 50-59, 60+)
- **Eligibility**: Only runs with `data_source == "bluetooth_ftms"` qualify for any leaderboard — this is enforced server-side via the `is_leaderboard_eligible` flag

---

## Phase 3: Achievements & Badges

> **Goal:** Unlock-based achievement system with badges on profiles.

### Backend

**New files:**
- `app/models/achievement.py` — Two tables:
  - `achievement_definitions` — Seed data for all achievements (id, category, title, description, icon, threshold, tier)
  - `user_achievements` — Join table: user_id, achievement_id, unlocked_at, run_id

- `app/models/streak.py` — `user_streaks` table: `current_streak_days`, `longest_streak_days`, `last_run_date`, `streak_start_date`. Updated after each sync.

- `app/services/achievement_service.py` — Engine that checks achievements after each run sync:
  - Computes lifetime distance, current streak, personal bests
  - Compares against definitions, inserts new unlocks
  - Returns newly unlocked achievements in sync response

**Achievement categories (seed data):**

| Category | Examples |
|----------|---------|
| Distance | 100km, 500km, 1000km, 100mi, 500mi, 1000mi clubs |
| Streaks | 7-day, 30-day, 100-day, 365-day consecutive running |
| Performance | Sub-25 5K, Sub-50 10K, Sub-2:00 HM, Sub-4:00 FM, Sub-3:00 FM |
| Milestones | First run, First 5K, First 10K, First HM, First FM, First Ultra |

**Tiers:** Bronze → Silver → Gold → Platinum (visual distinction)

**Modify:**
- `app/routes/community.py` — Add achievement endpoints:
  - `GET /api/community/achievements` — All definitions
  - `GET /api/community/achievements/mine` — User's unlocked
  - `GET /api/community/achievements/unnotified` — Newly unlocked, unseen
  - `POST /api/community/achievements/mark-notified`
- `app/routes/runs.py` — Return newly unlocked achievements in sync response

### iOS

**New files:**
- `StrideApp/Views/Community/AchievementsView.swift` — Grid of all achievements: unlocked (full color + date) vs locked (greyed + progress bar)
- `StrideApp/Views/Community/AchievementBadgeView.swift` — Reusable circular badge with tier-colored border
- `StrideApp/Views/Community/AchievementUnlockedSheet.swift` — Celebration modal with confetti animation
- `StrideApp/ViewModels/AchievementsViewModel.swift` — Fetches achievements, checks for unnotified on app open
- `StrideApp/Models/AchievementModels.swift` — Codable models

**Modify:**
- `StrideApp/Views/Profile/ProfileView.swift` — Add "Badges" horizontal scroll below profile header showing top achievements
- `StrideApp/Views/Community/CommunityView.swift` — Add "Achievements" section/tab

---

## Phase 4: Weekly Challenges & Races

> **Goal:** Recurring virtual races with per-challenge leaderboards and gamification.

### Backend

**New files:**
- `app/models/challenge.py` — Two tables:
  - `challenges` — title, type (weekly_race, monthly), distance_category, starts_at, ends_at, auto_generated flag, series_id
  - `challenge_participations` — user_id, challenge_id, best qualifying run_id, best_time_seconds

- `app/services/challenge_service.py` — Service:
  - `auto_generate_weekly_challenges()` — Creates next week's 5K + 10K races (called on startup / cron)
  - `check_challenge_participation(user_id, run)` — After sync, auto-matches runs to active challenges user has joined
  - `get_challenge_leaderboard(challenge_id)` — Ranked results
  - Monthly challenges: same infra, just longer date ranges (e.g., "Run 100km in February")

**Modify:**
- `app/routes/community.py` — Challenge endpoints:
  - `GET /api/community/challenges` — Active + upcoming
  - `GET /api/community/challenges/{id}` — Detail + leaderboard
  - `POST /api/community/challenges/{id}/join`
  - `GET /api/community/challenges/history` — Past results
- `app/routes/runs.py` — Trigger challenge matching after sync

### iOS

**New files:**
- `StrideApp/Views/Community/ChallengesView.swift` — Active challenges list with join CTA
- `StrideApp/Views/Community/ChallengeDetailView.swift` — Detail view: countdown, leaderboard, personal result
- `StrideApp/Views/Community/ChallengeCardView.swift` — Compact card for list
- `StrideApp/ViewModels/ChallengesViewModel.swift`

**Modify:**
- `StrideApp/Views/Community/CommunityView.swift` — Add "Challenges" as prominent section

### Race Format
- **Explicit join model**: User taps "Join Race" → they're registered → any Bluetooth-verified run during the race window that meets the distance threshold automatically counts → fastest time wins
- **Weekly**: Auto-generated every Monday. "This Week's 5K", "This Week's 10K". Mon-Sun window.
- **Monthly**: "February Distance Challenge: Run 150km". Cumulative distance. Explicit join.
- **Special**: Manually created for holidays, milestones, etc.

---

## Phase 5: Events & Physical Rewards

> **Goal:** Scheduled one-off events with registration, sponsored events, and physical reward fulfillment.

### Backend

**New files:**
- `app/models/event.py` — Tables:
  - `events` — title, type, distance, event_date, registration window, max_participants, sponsor info, reward info
  - `event_registrations` — user_id, event_id, status, result run, finish time

- `app/models/reward.py` — Tables:
  - `reward_tiers` — Links achievements/events to physical rewards (type: patch, medal, shirt)
  - `reward_claims` — Tracks claim status (eligible → address_needed → processing → shipped → delivered)

- `app/services/event_service.py` — Registration, result processing, reward eligibility

**Modify:**
- `app/routes/community.py` — Event endpoints:
  - `GET /api/community/events` — Upcoming
  - `POST /api/community/events/{id}/register`
  - `GET /api/community/events/{id}/leaderboard`
  - `POST /api/community/rewards/claim` — Collect shipping address
  - `GET /api/community/rewards/mine` — Claim status tracking

### iOS

**New files:**
- `StrideApp/Views/Community/EventsView.swift` — Event listing with registration
- `StrideApp/Views/Community/EventDetailView.swift` — Event detail with sponsor branding
- `StrideApp/Views/Community/RewardsView.swift` — Reward tracking and claim flow
- `StrideApp/Views/Community/AddressInputView.swift` — Shipping address form

### Event Types
- **Day-of Marathons**: Specific date, everyone runs simultaneously (or within a window)
- **Sponsored Events**: Brand logo, custom rewards, special branding
- **Seasonal**: New Year's Day Marathon, Summer Solstice Ultra, Halloween 31K

### Physical Rewards (Deferred until this phase)
- Achievement milestones: patches, stickers for distance clubs
- Event medals: mailed to finishers/winners
- Fulfillment approach TBD (manual vs third-party like Printful)

---

## Phase 6: Social Layer

> **Goal:** Follow system, activity feed, teams, and sharing.

### Backend

**New files:**
- `app/models/social.py` — Tables:
  - `follows` — follower_id, following_id
  - `teams` — name, description, photo, invite_code, created_by
  - `team_members` — team_id, user_id, role
  - `activity_feed` — user_id, activity_type (run, achievement, pb, challenge), created_at

- `app/services/social_service.py` — Follow/unfollow, feed generation, team CRUD
- `app/routes/social.py` — Social endpoints: follow, feed, teams, user search

### iOS

**New files:**
- `StrideApp/Views/Community/ActivityFeedView.swift` — Feed from followed users
- `StrideApp/Views/Community/UserProfileView.swift` — Public profile: badges, stats, follow button
- `StrideApp/Views/Community/TeamsView.swift` — Team management, team leaderboards
- `StrideApp/Views/Community/UserSearchView.swift` — Find and follow users

### Features
- **Activity Feed**: See when followed users complete runs, unlock achievements, set PBs
- **Teams/Crews**: Create team, share invite code, team cumulative distance leaderboard
- **User Profiles**: Public view of badges, stats, recent activity
- **Sharing**: Share runs, achievements, challenge results (generates shareable image/link)

---

## Bonus Ideas (to weave in across phases)

| Idea | Phase | Description |
|------|-------|-------------|
| "Running Now" counter | 2 | Heartbeat endpoint during active runs → "7 runners on Stride right now" |
| Streak display | 3 | Prominent streak counter on profile + "Longest Streaks" mini-leaderboard |
| Age-group leaderboards | 2 | Filter by age bracket (computed from DOB) |
| Gender leaderboards | 2 | Filter by gender |
| Team challenges | 4+6 | Teams compete in weekly challenges (combined distance/time) |
| Streak freeze | 3+ | Allow 1 rest day without breaking streak (future consideration) |

---

## Phase Dependency Chain

```
Phase 1 (Run Sync) ─┬─> Phase 2 (Leaderboards)
                     ├─> Phase 3 (Achievements)
                     └─> Phase 4 (Challenges) ──> Phase 5 (Events & Rewards)
                                                   Phase 6 (Social) — independent but benefits from all
```

Phases 2, 3, and 4 can be developed in parallel after Phase 1.

---

## Verification Strategy

**Phase 1:** Complete a run on iOS → verify RunLog syncs to server → check `runs` table in Neon → verify dedup on re-sync → test leaderboard opt-in toggle updates profile

**Phase 2:** Sync multiple runs → hit leaderboard endpoints → verify correct ranking + personal rank → test gender/age filters → verify PB computation

**Phase 3:** Sync runs that cross achievement thresholds → verify `user_achievements` populated → verify unnotified endpoint returns them → test badge display on profile

**Phase 4:** Verify weekly challenges auto-generate → join challenge → sync qualifying run → verify participation recorded and ranked → test challenge history

**Phase 5:** Create event → register → sync run during event window → verify result → test reward claim flow

**Phase 6:** Follow user → sync a run → verify it appears in follower's feed → create team → join via code → verify team leaderboard
