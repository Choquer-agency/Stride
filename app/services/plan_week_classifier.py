"""
Heuristic week-character classifier — labels the just-completed training week
as one of: first | build | peak | recovery | taper | race_week.

The plan itself lives in iOS SwiftData (TrainingPlan/Week/Workout) and isn't
mirrored to the backend, so this v1 classifier infers character from:
  - Run history on the backend (volume per week)
  - EventRegistration / Event for upcoming races (taper / race_week detection)
  - Recent activity (first-week detection)

Phase 7 will add explicit Week.is_recovery_week + plan-aware classification
once the plan structure is mirrored.
"""

from datetime import date, datetime, timedelta, timezone
from typing import Literal

from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.event import Event, EventRegistration
from app.models.run import Run

WeekCharacter = Literal["first", "build", "peak", "recovery", "taper", "race_week"]


# Tunable thresholds
_RECOVERY_VOLUME_DROP_PCT = 0.15   # ≥15% drop from prior 3-week avg → recovery
_FIRST_WEEK_INACTIVITY_DAYS = 14   # zero runs in past 14 days → "first" week
_PEAK_LOOKBACK_WEEKS = 6
_TAPER_DAYS = 28
_RACE_WEEK_DAYS = 7


async def classify_week(
    db: AsyncSession,
    user_id,
    today: date | None = None,
) -> WeekCharacter:
    """
    Decide the character of the week ENDING today (or the most recent Sunday).
    Order matters — race_week beats taper beats peak beats recovery beats build.
    """
    if today is None:
        today = datetime.now(timezone.utc).date()

    # 1) race_week — registered race within next 7 days
    race_distance_days = await _days_until_next_race(db, user_id, today)
    if race_distance_days is not None and race_distance_days <= _RACE_WEEK_DAYS:
        return "race_week"
    # 2) taper — within 28 days
    if race_distance_days is not None and race_distance_days <= _TAPER_DAYS:
        return "taper"

    # 3) first — no Run records in past 14 days
    recent_run_count = await _count_runs_in_window(db, user_id, today - timedelta(days=_FIRST_WEEK_INACTIVITY_DAYS), today)
    if recent_run_count == 0:
        return "first"

    # Compute weekly volumes for the last 6 weeks (week ending Sunday)
    weekly_volumes = await _weekly_volumes(db, user_id, today, weeks=_PEAK_LOOKBACK_WEEKS)
    this_week_volume = weekly_volumes[0] if weekly_volumes else 0.0
    prior_three = weekly_volumes[1:4]
    prior_three_avg = sum(prior_three) / len(prior_three) if prior_three else 0.0

    # 4) recovery — this week ≥15% lower than prior 3-week avg (and prior weeks weren't 0)
    if prior_three_avg > 0 and this_week_volume <= prior_three_avg * (1 - _RECOVERY_VOLUME_DROP_PCT):
        return "recovery"

    # 5) peak — this week is the highest of the last 6 weeks (with at least 4 weeks of history)
    if len(weekly_volumes) >= 4 and this_week_volume == max(weekly_volumes) and this_week_volume > 0:
        return "peak"

    # 6) default
    return "build"


# ── helpers ────────────────────────────────────────────────────────────────

async def _days_until_next_race(db: AsyncSession, user_id, today: date) -> int | None:
    """Days until the athlete's next registered race (any future Event). None if none."""
    now = datetime.combine(today, datetime.min.time(), tzinfo=timezone.utc)
    result = await db.execute(
        select(Event.starts_at)
        .join(EventRegistration, EventRegistration.event_id == Event.id)
        .where(
            EventRegistration.user_id == user_id,
            Event.starts_at >= now,
            Event.is_active.is_(True),
        )
        .order_by(Event.starts_at)
        .limit(1)
    )
    next_start = result.scalar_one_or_none()
    if next_start is None:
        return None
    delta_days = (next_start.date() - today).days
    return max(0, delta_days)


async def _count_runs_in_window(db: AsyncSession, user_id, since: date, until: date) -> int:
    since_dt = datetime.combine(since, datetime.min.time(), tzinfo=timezone.utc)
    until_dt = datetime.combine(until, datetime.max.time(), tzinfo=timezone.utc)
    result = await db.execute(
        select(func.count(Run.id)).where(
            Run.user_id == user_id,
            Run.completed_at >= since_dt,
            Run.completed_at <= until_dt,
        )
    )
    return result.scalar_one() or 0


async def _weekly_volumes(db: AsyncSession, user_id, today: date, weeks: int) -> list[float]:
    """
    Return total km per week for the most recent `weeks` weeks (this week first).
    Each "week" runs Monday → Sunday, ending on the Sunday at or before `today`.
    """
    # Find the most recent Sunday <= today
    days_since_sunday = (today.weekday() + 1) % 7  # Mon=0..Sun=6 → days back to last Sunday
    most_recent_sunday = today - timedelta(days=days_since_sunday)

    volumes: list[float] = []
    for i in range(weeks):
        end = most_recent_sunday - timedelta(days=7 * i)
        start = end - timedelta(days=6)
        start_dt = datetime.combine(start, datetime.min.time(), tzinfo=timezone.utc)
        end_dt = datetime.combine(end, datetime.max.time(), tzinfo=timezone.utc)
        result = await db.execute(
            select(func.coalesce(func.sum(Run.distance_km), 0.0)).where(
                Run.user_id == user_id,
                Run.completed_at >= start_dt,
                Run.completed_at <= end_dt,
            )
        )
        volumes.append(float(result.scalar_one() or 0.0))
    return volumes
