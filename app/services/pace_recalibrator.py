"""
Deterministic pace-drift math used by Phase 7 block reviews. The arithmetic
runs in code, not in prompts — the LLM reasons about whether to recommend
a recalibration based on the magnitudes we hand it.

Three windows are exposed:
  - compute_easy_pace_drift   — actual easy-run pace vs plan-stated zone
  - compute_threshold_drift   — actual quality-run pace vs plan-stated zone
  - compute_race_predictor_delta — Garmin race predictor vs athlete's goal time

All return None gracefully when there isn't enough data to compute.
"""

import logging
import statistics
from datetime import datetime, timedelta, timezone
from typing import Optional
from uuid import UUID

from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.garmin_periodic_metric import GarminPeriodicMetric
from app.models.run import Run

logger = logging.getLogger(__name__)


_EASY_KEYWORDS = ("easy", "recovery", "long")
_QUALITY_KEYWORDS = ("tempo", "threshold", "vo2", "speed", "interval")

# Below this many same-type runs in the window, return None
_MIN_SAMPLES = 4


async def compute_easy_pace_drift(
    db: AsyncSession,
    user_id: UUID,
    *,
    weeks_back: int = 4,
) -> Optional[dict]:
    """
    Median actual pace from easy/recovery/long runs in the last `weeks_back`
    weeks vs the median of the FIRST 2 weeks of the prior window — gives us
    a rough "are easy paces shifting" signal.

    Returns:
      {
        "current_median_sec_per_km": 308,
        "baseline_median_sec_per_km": 320,
        "delta_sec_per_km": -12,        # negative = paces dropped (got faster)
        "sample_count_current": 9,
        "sample_count_baseline": 7,
      }
      or None if insufficient data.
    """
    return await _compute_drift(db, user_id, weeks_back=weeks_back, keywords=_EASY_KEYWORDS)


async def compute_threshold_drift(
    db: AsyncSession,
    user_id: UUID,
    *,
    weeks_back: int = 4,
) -> Optional[dict]:
    return await _compute_drift(db, user_id, weeks_back=weeks_back, keywords=_QUALITY_KEYWORDS)


async def _compute_drift(
    db: AsyncSession,
    user_id: UUID,
    *,
    weeks_back: int,
    keywords: tuple,
) -> Optional[dict]:
    now = datetime.now(timezone.utc)
    window_end = now
    window_start = now - timedelta(weeks=weeks_back)
    baseline_start = window_start - timedelta(weeks=weeks_back)

    runs_q = select(Run.completed_at, Run.avg_pace_sec_per_km, Run.planned_workout_type).where(
        Run.user_id == user_id,
        Run.completed_at >= baseline_start,
        Run.avg_pace_sec_per_km.is_not(None),
        Run.planned_workout_type.is_not(None),
    )
    rows = list((await db.execute(runs_q)).all())

    current = []
    baseline = []
    for completed_at, pace, ptype in rows:
        ptype_lower = ptype.lower() if ptype else ""
        if not any(k in ptype_lower for k in keywords):
            continue
        if completed_at >= window_start:
            current.append(float(pace))
        else:
            baseline.append(float(pace))

    if len(current) < _MIN_SAMPLES or len(baseline) < _MIN_SAMPLES:
        return None

    current_median = float(statistics.median(current))
    baseline_median = float(statistics.median(baseline))

    return {
        "current_median_sec_per_km": round(current_median, 1),
        "baseline_median_sec_per_km": round(baseline_median, 1),
        "delta_sec_per_km": round(current_median - baseline_median, 1),
        "sample_count_current": len(current),
        "sample_count_baseline": len(baseline),
        "weeks_back": weeks_back,
    }


async def compute_race_predictor_delta(
    db: AsyncSession,
    user_id: UUID,
    *,
    race_type: str,
    goal_time_seconds: Optional[int],
) -> Optional[dict]:
    """
    Compares Garmin's most recent race predictor (from garmin_periodic_metrics)
    for the athlete's current race type against their stated goal time.

    Returns:
      {
        "race_type": "marathon",
        "predictor_seconds": 10440,
        "goal_seconds": 10800,
        "delta_seconds": -360,             # negative = faster than goal
        "delta_pct": -3.3,                 # negative = faster than goal
        "on_track": True,                  # within ±5%
      }
      or None if no predictor available.
    """
    if not goal_time_seconds:
        return None

    result = await db.execute(
        select(GarminPeriodicMetric.race_predictors)
        .where(GarminPeriodicMetric.user_id == user_id)
        .order_by(desc(GarminPeriodicMetric.fetched_at))
        .limit(1)
    )
    predictors = result.scalar_one_or_none()
    if not predictors:
        return None

    # Map race_type to the predictor key
    race_lookup = {
        "5K": "five_k",
        "10K": "ten_k",
        "Half Marathon": "half_marathon",
        "Marathon": "marathon",
        "five_k": "five_k",
        "ten_k": "ten_k",
        "half_marathon": "half_marathon",
        "marathon": "marathon",
    }
    key = race_lookup.get(race_type)
    if key is None or key not in predictors:
        return None
    predictor_seconds = int(predictors[key])

    delta = predictor_seconds - goal_time_seconds
    delta_pct = (delta / goal_time_seconds) * 100
    on_track = abs(delta_pct) <= 5.0

    return {
        "race_type": race_type,
        "predictor_seconds": predictor_seconds,
        "goal_seconds": goal_time_seconds,
        "delta_seconds": int(delta),
        "delta_pct": round(delta_pct, 2),
        "on_track": on_track,
    }
