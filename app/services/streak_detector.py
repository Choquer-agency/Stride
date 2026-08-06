"""
Positive-loop streak detection — fires consolidation events when the athlete
strings together meaningful patterns. Balances Phase 3's anomaly engine so
the coach has a positive register, not just worry signals.

All checks are deterministic, no LLM. Each returns a single AnomalyFlag with
severity=info and a `consolidation_*` flag_type. The post_run_check orchestrator
then triggers a Haiku call against `coach_consolidation.txt` to render the message.

Dedup: a streak doesn't fire again until 7 days have passed since the last
consolidation flag of the same type for that user.
"""

import logging
import statistics
from datetime import datetime, timedelta, timezone
from typing import Optional
from uuid import UUID

from sqlalchemy import desc, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.anomaly_flag import AnomalyFlag, FlagSeverity, FlagType
from app.models.garmin_daily_metric import GarminDailyMetric
from app.models.run import Run
from app.models.user import User

logger = logging.getLogger(__name__)


# ── Tunable thresholds ──────────────────────────────────────────────────────

_QUALITY_STREAK_MIN = 5           # 5+ consecutive quality sessions hit
_RUN_STREAK_MIN_DAYS = 14         # 14+ consecutive days with at least one run
_HRV_BUILD_WEEKS = 4              # 4 weeks of trending-up baseline
_DISTRIBUTION_LOCK_WEEKS = 4      # 80/15/5 maintained 4 weeks
_DISTRIBUTION_TARGET_EASY_PCT = 0.80
_DISTRIBUTION_TOLERANCE = 0.05    # ±5pp on the easy share

_CONSOLIDATION_DEDUP_DAYS = 7     # don't fire same streak twice within 7 days


# ── Public entry point ─────────────────────────────────────────────────────

async def detect_all(db: AsyncSession, user: User) -> list[AnomalyFlag]:
    """
    Run all streak detectors. Returns the list of flags raised + persisted.
    Called by post_run_check.run_post_run_check (workout-triggered) AND can
    be invoked from a daily cron later.
    """
    raised: list[AnomalyFlag] = []
    for detector in (
        _detect_quality_streak,
        _detect_run_streak,
        _detect_hrv_build,
        _detect_distribution_lock,
    ):
        flag = await detector(db, user)
        if flag:
            raised.append(flag)

    persisted: list[AnomalyFlag] = []
    for flag in raised:
        if await _persist_if_no_recent_dup(db, flag):
            persisted.append(flag)
    return persisted


# ── Detectors ──────────────────────────────────────────────────────────────

async def _detect_quality_streak(db: AsyncSession, user: User) -> Optional[AnomalyFlag]:
    """
    5+ consecutive quality sessions hit. "Hit" = completion_score is null OR ≥ 70.
    Iterates back through the user's quality runs in chronological order until a
    miss breaks the streak.
    """
    quality_keywords = ("tempo", "threshold", "vo2", "speed", "interval")
    cutoff = datetime.now(timezone.utc) - timedelta(days=60)
    result = await db.execute(
        select(Run)
        .where(
            Run.user_id == user.id,
            Run.completed_at >= cutoff,
            Run.planned_workout_type.is_not(None),
        )
        .order_by(desc(Run.completed_at))
        .limit(20)
    )
    runs = list(result.scalars().all())
    quality = [r for r in runs if r.planned_workout_type and any(k in r.planned_workout_type.lower() for k in quality_keywords)]
    if len(quality) < _QUALITY_STREAK_MIN:
        return None

    streak = 0
    streak_runs: list[Run] = []
    for r in quality:
        score = r.completion_score
        if score is None or score >= 70:
            streak += 1
            streak_runs.append(r)
        else:
            break

    if streak < _QUALITY_STREAK_MIN:
        return None

    return _build_flag(
        user_id=user.id,
        flag_type=FlagType.CONSOLIDATION_QUALITY_STREAK.value,
        context={
            "streak_length": streak,
            "session_dates": [
                r.completed_at.strftime("%Y-%m-%d") for r in streak_runs[:_QUALITY_STREAK_MIN]
            ],
            "session_types": [r.planned_workout_type for r in streak_runs[:_QUALITY_STREAK_MIN]],
        },
    )


async def _detect_run_streak(db: AsyncSession, user: User) -> Optional[AnomalyFlag]:
    """14+ consecutive calendar days with at least one Run."""
    today = datetime.now(timezone.utc).date()
    lookback_days = max(_RUN_STREAK_MIN_DAYS + 7, 30)
    cutoff = today - timedelta(days=lookback_days)
    result = await db.execute(
        select(Run.completed_at)
        .where(
            Run.user_id == user.id,
            Run.completed_at >= datetime.combine(cutoff, datetime.min.time(), tzinfo=timezone.utc),
        )
        .order_by(desc(Run.completed_at))
    )
    run_dates = sorted({row[0].date() for row in result.all() if row[0]}, reverse=True)
    if not run_dates:
        return None

    # Streak must include today or yesterday to count as "active"
    if (today - run_dates[0]).days > 1:
        return None

    streak = 1
    expected = run_dates[0] - timedelta(days=1)
    for d in run_dates[1:]:
        if d == expected:
            streak += 1
            expected -= timedelta(days=1)
        elif d == expected + timedelta(days=1):
            # multiple runs same day — already counted, skip
            continue
        else:
            break

    if streak < _RUN_STREAK_MIN_DAYS:
        return None

    return _build_flag(
        user_id=user.id,
        flag_type=FlagType.CONSOLIDATION_RUN_STREAK.value,
        context={
            "streak_days": streak,
            "started_on": (run_dates[0] - timedelta(days=streak - 1)).isoformat(),
            "latest_run": run_dates[0].isoformat(),
        },
    )


async def _detect_hrv_build(db: AsyncSession, user: User) -> Optional[AnomalyFlag]:
    """
    HRV baseline trending up for 4 weeks running.
    Uses the hrv_baseline_7day stamped on each daily metric — sample one per
    week (the most recent in each week) and require a monotonic non-decreasing
    sequence (allowing a week of plateau, but no drop).
    """
    today = datetime.now(timezone.utc).date()
    weeks = _HRV_BUILD_WEEKS
    samples: list[float] = []
    for w in range(weeks):
        end = today - timedelta(days=7 * w)
        start = end - timedelta(days=6)
        result = await db.execute(
            select(GarminDailyMetric.hrv_baseline_7day)
            .where(
                GarminDailyMetric.user_id == user.id,
                GarminDailyMetric.date >= start,
                GarminDailyMetric.date <= end,
                GarminDailyMetric.hrv_baseline_7day.is_not(None),
            )
            .order_by(desc(GarminDailyMetric.date))
            .limit(1)
        )
        baseline = result.scalar_one_or_none()
        if baseline is None:
            return None
        samples.append(float(baseline))

    # `samples` is most-recent-first → reverse to chronological for trend check
    chrono = list(reversed(samples))
    # Monotonic non-decreasing with at least 1 ms between earliest and latest
    if any(later < earlier for earlier, later in zip(chrono, chrono[1:])):
        return None
    if (chrono[-1] - chrono[0]) < 1.0:
        return None

    return _build_flag(
        user_id=user.id,
        flag_type=FlagType.CONSOLIDATION_HRV_BUILD.value,
        context={
            "weeks": weeks,
            "weekly_baselines_chrono": [round(v, 1) for v in chrono],
            "delta_ms": round(chrono[-1] - chrono[0], 1),
        },
    )


async def _detect_distribution_lock(db: AsyncSession, user: User) -> Optional[AnomalyFlag]:
    """
    80/15/5 distribution maintained for 4 consecutive weeks.
    "Easy" = planned_workout_type containing easy/recovery/long. We check the
    easy share is in [75%, 85%] every week (5 percentage point tolerance).
    """
    today = datetime.now(timezone.utc).date()
    weeks_ok = 0
    for w in range(_DISTRIBUTION_LOCK_WEEKS):
        end = today - timedelta(days=7 * w)
        start = end - timedelta(days=6)
        easy_km, total_km = await _easy_vs_total_km(db, user.id, start, end)
        if total_km < 10:
            return None  # not enough volume to call distribution
        easy_share = easy_km / total_km
        if abs(easy_share - _DISTRIBUTION_TARGET_EASY_PCT) > _DISTRIBUTION_TOLERANCE:
            return None
        weeks_ok += 1

    if weeks_ok < _DISTRIBUTION_LOCK_WEEKS:
        return None

    return _build_flag(
        user_id=user.id,
        flag_type=FlagType.CONSOLIDATION_DISTRIBUTION_LOCK.value,
        context={
            "weeks": _DISTRIBUTION_LOCK_WEEKS,
            "target_easy_pct": int(_DISTRIBUTION_TARGET_EASY_PCT * 100),
            "tolerance_pp": int(_DISTRIBUTION_TOLERANCE * 100),
        },
    )


# ── Helpers ────────────────────────────────────────────────────────────────

async def _easy_vs_total_km(db: AsyncSession, user_id: UUID, start, end) -> tuple[float, float]:
    start_dt = datetime.combine(start, datetime.min.time(), tzinfo=timezone.utc)
    end_dt = datetime.combine(end, datetime.max.time(), tzinfo=timezone.utc)
    result = await db.execute(
        select(Run.distance_km, Run.planned_workout_type)
        .where(
            Run.user_id == user_id,
            Run.completed_at >= start_dt,
            Run.completed_at <= end_dt,
            Run.distance_km.is_not(None),
        )
    )
    rows = list(result.all())
    total = sum(float(r[0] or 0) for r in rows)
    easy = sum(
        float(r[0] or 0)
        for r in rows
        if r[1] and any(k in r[1].lower() for k in ("easy", "recovery", "long"))
    )
    return easy, total


def _build_flag(*, user_id: UUID, flag_type: str, context: dict) -> AnomalyFlag:
    return AnomalyFlag(
        user_id=user_id,
        flag_type=flag_type,
        severity=FlagSeverity.INFO.value,
        context=context,
    )


async def _persist_if_no_recent_dup(db: AsyncSession, flag: AnomalyFlag) -> bool:
    """Don't fire the same consolidation type twice within 7 days for one user."""
    cutoff = datetime.now(timezone.utc) - timedelta(days=_CONSOLIDATION_DEDUP_DAYS)
    result = await db.execute(
        select(AnomalyFlag.id).where(
            AnomalyFlag.user_id == flag.user_id,
            AnomalyFlag.flag_type == flag.flag_type,
            AnomalyFlag.raised_at >= cutoff,
        ).limit(1)
    )
    if result.scalar_one_or_none() is not None:
        return False
    db.add(flag)
    await db.flush()
    logger.info("Streak fired: type=%s user=%s context=%s", flag.flag_type, flag.user_id, flag.context)
    return True
