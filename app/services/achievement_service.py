"""Achievement & streak engine: checks for new unlocks after each run sync."""

import uuid
from datetime import datetime, date, timedelta, timezone
from typing import Optional

from sqlalchemy import select, func, text
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.run import Run
from app.models.achievement import AchievementDefinition, UserAchievement
from app.models.streak import UserStreak
from app.models.personal_best import PersonalBest
from app.services.social_service import log_activity


# ── Achievement Seed Data ────────────────────────────────────────────────────

ACHIEVEMENT_DEFINITIONS = [
    # Distance milestones (threshold in km)
    {"id": "distance_100km", "category": "distance", "title": "Century Runner", "description": "Run 100 km total", "icon": "figure.run", "threshold": 100, "tier": "bronze", "sort_order": 1},
    {"id": "distance_500km", "category": "distance", "title": "Road Warrior", "description": "Run 500 km total", "icon": "figure.run", "threshold": 500, "tier": "silver", "sort_order": 2},
    {"id": "distance_1000km", "category": "distance", "title": "1K Club", "description": "Run 1,000 km total", "icon": "figure.run", "threshold": 1000, "tier": "gold", "sort_order": 3},
    {"id": "distance_100mi", "category": "distance", "title": "100 Mile Club", "description": "Run 100 miles total", "icon": "figure.run.circle", "threshold": 161, "tier": "silver", "sort_order": 4},
    {"id": "distance_500mi", "category": "distance", "title": "500 Mile Club", "description": "Run 500 miles total", "icon": "figure.run.circle", "threshold": 805, "tier": "gold", "sort_order": 5},
    {"id": "distance_1000mi", "category": "distance", "title": "1000 Mile Club", "description": "Run 1,000 miles total", "icon": "figure.run.circle.fill", "threshold": 1609, "tier": "platinum", "sort_order": 6},

    # Streak milestones (threshold in days)
    {"id": "streak_7", "category": "streak", "title": "Week Warrior", "description": "7-day running streak", "icon": "flame", "threshold": 7, "tier": "bronze", "sort_order": 10},
    {"id": "streak_30", "category": "streak", "title": "Monthly Machine", "description": "30-day running streak", "icon": "flame.fill", "threshold": 30, "tier": "silver", "sort_order": 11},
    {"id": "streak_100", "category": "streak", "title": "Centurion", "description": "100-day running streak", "icon": "flame.fill", "threshold": 100, "tier": "gold", "sort_order": 12},
    {"id": "streak_365", "category": "streak", "title": "Year of Fire", "description": "365-day running streak", "icon": "flame.fill", "threshold": 365, "tier": "platinum", "sort_order": 13},

    # Performance (threshold in seconds — lower is better)
    {"id": "perf_5k_sub25", "category": "performance", "title": "Sub-25 5K", "description": "Run 5K in under 25 minutes", "icon": "bolt.fill", "threshold": 1500, "tier": "bronze", "sort_order": 20},
    {"id": "perf_5k_sub20", "category": "performance", "title": "Sub-20 5K", "description": "Run 5K in under 20 minutes", "icon": "bolt.fill", "threshold": 1200, "tier": "gold", "sort_order": 21},
    {"id": "perf_10k_sub50", "category": "performance", "title": "Sub-50 10K", "description": "Run 10K in under 50 minutes", "icon": "bolt.fill", "threshold": 3000, "tier": "bronze", "sort_order": 22},
    {"id": "perf_10k_sub40", "category": "performance", "title": "Sub-40 10K", "description": "Run 10K in under 40 minutes", "icon": "bolt.fill", "threshold": 2400, "tier": "gold", "sort_order": 23},
    {"id": "perf_hm_sub2h", "category": "performance", "title": "Sub-2:00 Half", "description": "Run a half marathon in under 2 hours", "icon": "bolt.fill", "threshold": 7200, "tier": "silver", "sort_order": 24},
    {"id": "perf_hm_sub130", "category": "performance", "title": "Sub-1:30 Half", "description": "Run a half marathon in under 1:30", "icon": "bolt.fill", "threshold": 5400, "tier": "platinum", "sort_order": 25},
    {"id": "perf_fm_sub4h", "category": "performance", "title": "Sub-4:00 Marathon", "description": "Run a marathon in under 4 hours", "icon": "bolt.fill", "threshold": 14400, "tier": "silver", "sort_order": 26},
    {"id": "perf_fm_sub3h", "category": "performance", "title": "Sub-3:00 Marathon", "description": "Run a marathon in under 3 hours", "icon": "bolt.fill", "threshold": 10800, "tier": "platinum", "sort_order": 27},

    # Milestones (threshold = distance in km, 0 = first run)
    {"id": "milestone_first_run", "category": "milestone", "title": "First Steps", "description": "Complete your first run", "icon": "star", "threshold": 0, "tier": "bronze", "sort_order": 30},
    {"id": "milestone_first_5k", "category": "milestone", "title": "5K Finisher", "description": "Complete a 5K distance", "icon": "star.fill", "threshold": 5, "tier": "bronze", "sort_order": 31},
    {"id": "milestone_first_10k", "category": "milestone", "title": "10K Finisher", "description": "Complete a 10K distance", "icon": "star.fill", "threshold": 10, "tier": "silver", "sort_order": 32},
    {"id": "milestone_first_hm", "category": "milestone", "title": "Half Marathon Finisher", "description": "Complete a half marathon distance", "icon": "star.fill", "threshold": 21, "tier": "gold", "sort_order": 33},
    {"id": "milestone_first_fm", "category": "milestone", "title": "Marathon Finisher", "description": "Complete a marathon distance", "icon": "star.fill", "threshold": 42, "tier": "gold", "sort_order": 34},
    {"id": "milestone_first_ultra", "category": "milestone", "title": "Ultra Finisher", "description": "Complete an ultra distance (50K+)", "icon": "star.circle.fill", "threshold": 50, "tier": "platinum", "sort_order": 35},
]

# Performance achievement → PB category mapping
PERF_CATEGORY_MAP = {
    "perf_5k_sub25": "5K",
    "perf_5k_sub20": "5K",
    "perf_10k_sub50": "10K",
    "perf_10k_sub40": "10K",
    "perf_hm_sub2h": "HM",
    "perf_hm_sub130": "HM",
    "perf_fm_sub4h": "FM",
    "perf_fm_sub3h": "FM",
}


async def seed_achievement_definitions(db: AsyncSession) -> None:
    """Insert or update all achievement definitions (idempotent)."""
    for defn in ACHIEVEMENT_DEFINITIONS:
        stmt = pg_insert(AchievementDefinition).values(**defn).on_conflict_do_update(
            index_elements=["id"],
            set_={k: v for k, v in defn.items() if k != "id"},
        )
        await db.execute(stmt)
    await db.commit()


# ── Streak Computation ────────────────────────────────────────────────────────

async def update_streak(
    db: AsyncSession,
    user_id: uuid.UUID,
    run_date: date,
) -> int:
    """
    Update the user's streak after a run. Returns current streak length.
    A streak counts consecutive calendar days with at least one run.
    """
    result = await db.execute(
        select(UserStreak).where(UserStreak.user_id == user_id)
    )
    streak = result.scalar_one_or_none()

    run_date_str = run_date.isoformat()

    if streak is None:
        streak = UserStreak(
            user_id=user_id,
            current_streak_days=1,
            longest_streak_days=1,
            last_run_date=run_date_str,
            streak_start_date=run_date_str,
        )
        db.add(streak)
        return 1

    if streak.last_run_date == run_date_str:
        # Already ran today — no change
        return streak.current_streak_days

    last_run = date.fromisoformat(streak.last_run_date) if streak.last_run_date else None

    if last_run and (run_date - last_run).days == 1:
        # Consecutive day
        streak.current_streak_days += 1
    elif last_run and (run_date - last_run).days == 0:
        pass  # Same day, already handled above
    else:
        # Streak broken — reset
        streak.current_streak_days = 1
        streak.streak_start_date = run_date_str

    streak.last_run_date = run_date_str
    if streak.current_streak_days > streak.longest_streak_days:
        streak.longest_streak_days = streak.current_streak_days

    return streak.current_streak_days


# ── Achievement Checking ──────────────────────────────────────────────────────

async def check_achievements_after_sync(
    db: AsyncSession,
    user_id: uuid.UUID,
    run_id: uuid.UUID,
    distance_km: float,
    completed_at: datetime,
) -> list[dict]:
    """
    Check all achievement categories after a run sync.
    Returns list of newly unlocked achievement dicts.
    """
    newly_unlocked = []

    # Get user's already-unlocked achievement IDs
    result = await db.execute(
        select(UserAchievement.achievement_id).where(UserAchievement.user_id == user_id)
    )
    existing_ids = set(result.scalars().all())

    # Get all definitions
    result = await db.execute(select(AchievementDefinition).order_by(AchievementDefinition.sort_order))
    definitions = result.scalars().all()

    # ── 1. Distance achievements (lifetime total km) ──
    dist_result = await db.execute(
        select(func.sum(Run.distance_km)).where(Run.user_id == user_id)
    )
    lifetime_km = dist_result.scalar() or 0.0

    for defn in definitions:
        if defn.category != "distance" or defn.id in existing_ids:
            continue
        if lifetime_km >= defn.threshold:
            unlocked = await _unlock(db, user_id, defn.id, run_id, completed_at)
            if unlocked:
                newly_unlocked.append(_defn_to_dict(defn))

    # ── 2. Streak achievements ──
    run_date = completed_at.date() if isinstance(completed_at, datetime) else completed_at
    current_streak = await update_streak(db, user_id, run_date)

    # Also check longest streak
    streak_result = await db.execute(
        select(UserStreak).where(UserStreak.user_id == user_id)
    )
    streak_row = streak_result.scalar_one_or_none()
    longest_streak = streak_row.longest_streak_days if streak_row else current_streak

    for defn in definitions:
        if defn.category != "streak" or defn.id in existing_ids:
            continue
        if longest_streak >= defn.threshold:
            unlocked = await _unlock(db, user_id, defn.id, run_id, completed_at)
            if unlocked:
                newly_unlocked.append(_defn_to_dict(defn))

    # ── 3. Performance achievements (from personal bests) ──
    pb_result = await db.execute(
        select(PersonalBest).where(PersonalBest.user_id == user_id)
    )
    pbs = {pb.distance_category: pb.time_seconds for pb in pb_result.scalars().all()}

    for defn in definitions:
        if defn.category != "performance" or defn.id in existing_ids:
            continue
        pb_category = PERF_CATEGORY_MAP.get(defn.id)
        if pb_category and pb_category in pbs:
            if pbs[pb_category] <= defn.threshold:
                unlocked = await _unlock(db, user_id, defn.id, run_id, completed_at)
                if unlocked:
                    newly_unlocked.append(_defn_to_dict(defn))

    # ── 4. Milestone achievements (single-run distance) ──
    for defn in definitions:
        if defn.category != "milestone" or defn.id in existing_ids:
            continue
        if defn.threshold == 0:
            # "First run" — any run unlocks it
            unlocked = await _unlock(db, user_id, defn.id, run_id, completed_at)
            if unlocked:
                newly_unlocked.append(_defn_to_dict(defn))
        elif distance_km >= defn.threshold:
            unlocked = await _unlock(db, user_id, defn.id, run_id, completed_at)
            if unlocked:
                newly_unlocked.append(_defn_to_dict(defn))

    # Log activity for each newly unlocked achievement
    for ach in newly_unlocked:
        await log_activity(
            db, user_id, "achievement", None,
            {"title": ach["title"], "icon": ach["icon"], "tier": ach["tier"]},
        )

    return newly_unlocked


async def _unlock(
    db: AsyncSession,
    user_id: uuid.UUID,
    achievement_id: str,
    run_id: uuid.UUID,
    unlocked_at: datetime,
) -> bool:
    """Attempt to unlock an achievement. Returns True if newly inserted."""
    stmt = pg_insert(UserAchievement).values(
        user_id=user_id,
        achievement_id=achievement_id,
        run_id=run_id,
        unlocked_at=unlocked_at,
        notified="false",
    ).on_conflict_do_nothing(constraint="uq_user_achievement")

    result = await db.execute(stmt)
    return result.rowcount > 0


def _defn_to_dict(defn: AchievementDefinition) -> dict:
    """Convert definition to a serializable dict for the sync response."""
    return {
        "id": defn.id,
        "category": defn.category,
        "title": defn.title,
        "description": defn.description,
        "icon": defn.icon,
        "tier": defn.tier,
    }
