"""
Deterministic anomaly engine — no LLM. Each detector takes data + recent context
and returns AnomalyFlag rows. Dedup: don't re-raise the same flag_type while an
active one (resolved_at IS NULL) already exists.

Public entry points:
- evaluate_workout(db, user, run, garmin_workout=None) — workout-level flags +
  pattern flags evaluated on every Garmin workout sync
- evaluate_recovery(db, user, daily_metric) — daily-recovery flags evaluated on
  every Garmin daily-metric sync (overnight push)

Severity vocabulary:
- info        = noted, no athlete action expected
- warning     = athlete should be aware, may surface in coach loop
- warning_plus = contributes to critical override (combined with another flag)
- critical    = always notifies regardless of pause/shadow

Critical override (computed by post_run_check, not here):
- LEA pattern at severity=critical, OR
- HRV drop at severity=warning_plus AND missed_workouts at severity≥warning
"""

import logging
import statistics
from datetime import date, datetime, timedelta, timezone
from typing import Optional
from uuid import UUID

from sqlalchemy import desc, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.anomaly_flag import AnomalyFlag, FlagSeverity, FlagType
from app.models.garmin_daily_metric import GarminDailyMetric
from app.models.garmin_workout import ACTIVITY_BUCKET_RUNNING, GarminWorkout
from app.models.run import Run
from app.models.user import User

logger = logging.getLogger(__name__)


# ── Tunable thresholds ──────────────────────────────────────────────────────

# Pace flags
_HILLY_THRESHOLD_M = 200          # >200m total elevation gain → skip pace flag
_EASY_PACE_OVERRUN_SEC = 30       # easy pace >30 sec/km faster than baseline → flag
_QUALITY_PACE_UNDERSHOOT_SEC = 30 # quality pace >30 sec/km slower than baseline → flag

# Workout completion
_INCOMPLETE_DISTANCE_PCT = 0.80   # actual < 80% of planned distance → flag

# HR zones
_ZONE_VIOLATION_PCT = 0.40        # >40% time in too-high zone for an easy run → flag

# Recovery
_HRV_WARNING_DROP = 0.10          # >10% drop vs baseline
_HRV_WARNING_PLUS_DROP = 0.15     # >15% drop → critical-component
_RHR_RISE_BPM = 5                 # +5 bpm vs 7-day median → flag
_SLEEP_MIN_HOURS = 6.0
_SLEEP_SCORE_FLOOR = 60

# Pattern
_MISSED_PROXY_FLOOR_PCT = 0.60    # actual runs < 60% of recent frequency → flag
_PATTERN_LOOKBACK_DAYS = 7
_FREQUENCY_BASELINE_DAYS = 28

# Dedup window — don't re-raise the same active flag if one was raised in the past N hours
_DEDUP_WINDOW_HOURS = 24


# ── Public entry points ─────────────────────────────────────────────────────

async def evaluate_workout(
    db: AsyncSession,
    user: User,
    run: Run,
    garmin_workout: Optional[GarminWorkout] = None,
) -> list[AnomalyFlag]:
    """
    Run every workout-level detector + pattern detector that fires on workout
    completion. Persists new flags + returns them.
    """
    raised: list[AnomalyFlag] = []

    pace = await _check_pace_off_target(db, user, run, garmin_workout)
    if pace:
        raised.append(pace)

    completion = _check_workout_completion(user, run)
    if completion:
        raised.append(completion)

    if garmin_workout is not None:
        zone = _check_hr_zone_violation(user, run, garmin_workout)
        if zone:
            raised.append(zone)

    missed = await _check_missed_workouts(db, user)
    if missed:
        raised.append(missed)

    # Wellness + LEA — no-op until Phase 4 / 6 ship
    pain = await _check_pain_logged(db, user)
    if pain:
        raised.append(pain)
    lea = await _check_lea_pattern(db, user)
    if lea:
        raised.append(lea)
    # Phase 9: skipped strength sessions
    skips = await _check_strength_skips(db, user)
    if skips:
        raised.append(skips)

    persisted: list[AnomalyFlag] = []
    for flag in raised:
        if await _persist_if_new(db, flag):
            persisted.append(flag)
    return persisted


async def evaluate_recovery(
    db: AsyncSession,
    user: User,
    daily_metric: GarminDailyMetric,
) -> list[AnomalyFlag]:
    """
    Run daily-recovery detectors on a freshly-pushed metric.
    Persists new flags + returns them.
    """
    raised: list[AnomalyFlag] = []

    hrv = _check_hrv_drop(user, daily_metric)
    if hrv:
        raised.append(hrv)

    rhr = await _check_rhr_rise(db, user, daily_metric)
    if rhr:
        raised.append(rhr)

    sleep = _check_sleep_deficit(user, daily_metric)
    if sleep:
        raised.append(sleep)

    persisted: list[AnomalyFlag] = []
    for flag in raised:
        if await _persist_if_new(db, flag):
            persisted.append(flag)
    return persisted


# ── Workout-level detectors ────────────────────────────────────────────────

async def _check_pace_off_target(
    db: AsyncSession,
    user: User,
    run: Run,
    garmin_workout: Optional[GarminWorkout],
) -> Optional[AnomalyFlag]:
    """
    Easy/recovery runs: actual pace > threshold faster than baseline → "ran too hot."
    Quality runs (tempo/threshold/intervals): actual pace > threshold slower than baseline.

    Skipped on hilly runs (>200m elevation) and interval workouts (target pace
    varies per rep — overall avg isn't meaningful).
    """
    planned_type = (run.planned_workout_type or "").lower()
    if not planned_type or not run.avg_pace_sec_per_km:
        return None
    if "interval" in planned_type or "fartlek" in planned_type:
        return None

    # Skip if hilly — best signal is Garmin elevation gain summed from splits
    if garmin_workout and garmin_workout.splits:
        elev_gain = _sum_elevation_gain(garmin_workout.splits)
        if elev_gain > _HILLY_THRESHOLD_M:
            return None

    is_easy = any(k in planned_type for k in ("easy", "recovery", "long"))
    is_quality = any(k in planned_type for k in ("tempo", "threshold", "vo2", "speed"))

    if not (is_easy or is_quality):
        return None

    baseline = await _median_pace_for_type(db, user.id, is_easy=is_easy, days=28)
    if baseline is None:
        return None

    actual = run.avg_pace_sec_per_km
    delta_sec = actual - baseline  # positive = slower than baseline

    if is_easy and delta_sec < -_EASY_PACE_OVERRUN_SEC:
        # Faster than baseline = ran too hot on an easy day
        return _build_flag(
            user_id=user.id,
            flag_type=FlagType.PACE_OFF_TARGET.value,
            severity=FlagSeverity.WARNING.value,
            workout_id=run.id,
            context={
                "run_kind": "easy",
                "actual_sec_per_km": actual,
                "baseline_sec_per_km": baseline,
                "delta_sec": round(delta_sec, 1),
                "direction": "too_fast",
                "planned_workout_type": run.planned_workout_type,
            },
        )

    if is_quality and delta_sec > _QUALITY_PACE_UNDERSHOOT_SEC:
        return _build_flag(
            user_id=user.id,
            flag_type=FlagType.PACE_OFF_TARGET.value,
            severity=FlagSeverity.WARNING.value,
            workout_id=run.id,
            context={
                "run_kind": "quality",
                "actual_sec_per_km": actual,
                "baseline_sec_per_km": baseline,
                "delta_sec": round(delta_sec, 1),
                "direction": "too_slow",
                "planned_workout_type": run.planned_workout_type,
            },
        )

    return None


def _check_workout_completion(user: User, run: Run) -> Optional[AnomalyFlag]:
    """Actual distance < 80% of planned → flag. Depends on iOS having stamped planned_distance_km."""
    if not run.planned_distance_km or not run.distance_km:
        return None
    if run.planned_distance_km <= 0:
        return None
    completion = run.distance_km / run.planned_distance_km
    if completion >= _INCOMPLETE_DISTANCE_PCT:
        return None
    return _build_flag(
        user_id=user.id,
        flag_type=FlagType.WORKOUT_INCOMPLETE.value,
        severity=FlagSeverity.WARNING.value,
        workout_id=run.id,
        context={
            "actual_km": run.distance_km,
            "planned_km": run.planned_distance_km,
            "completion_pct": round(completion * 100, 1),
        },
    )


def _check_hr_zone_violation(
    user: User,
    run: Run,
    garmin_workout: GarminWorkout,
) -> Optional[AnomalyFlag]:
    """
    For runs the plan called 'easy', flag if >40% of total time was spent in Z3+.
    Indicates the athlete couldn't (or didn't) keep it aerobic.
    """
    planned_type = (run.planned_workout_type or "").lower()
    if not planned_type:
        return None
    is_easy = any(k in planned_type for k in ("easy", "recovery", "long"))
    if not is_easy:
        return None
    zones = garmin_workout.hr_zones or {}
    z3_plus = (zones.get("z3", 0) + zones.get("z4", 0) + zones.get("z5", 0))
    total = sum(int(zones.get(k, 0)) for k in ("z1", "z2", "z3", "z4", "z5"))
    if total == 0:
        return None
    pct = z3_plus / total
    if pct < _ZONE_VIOLATION_PCT:
        return None
    return _build_flag(
        user_id=user.id,
        flag_type=FlagType.HR_ZONE_VIOLATION.value,
        severity=FlagSeverity.WARNING.value,
        workout_id=run.id,
        context={
            "z3_plus_pct": round(pct * 100, 1),
            "z3_plus_seconds": int(z3_plus),
            "total_seconds": int(total),
            "expected_zones": "Z1-Z2 for easy/recovery/long",
        },
    )


# ── Daily-recovery detectors ───────────────────────────────────────────────

def _check_hrv_drop(user: User, metric: GarminDailyMetric) -> Optional[AnomalyFlag]:
    """today's hrv vs the rolling 7-day baseline stamped on the same row."""
    if not metric.hrv_overnight or not metric.hrv_baseline_7day:
        return None
    if metric.hrv_baseline_7day <= 0:
        return None
    drop_pct = (metric.hrv_baseline_7day - metric.hrv_overnight) / metric.hrv_baseline_7day
    if drop_pct < _HRV_WARNING_DROP:
        return None
    severity = (
        FlagSeverity.WARNING_PLUS.value if drop_pct >= _HRV_WARNING_PLUS_DROP
        else FlagSeverity.WARNING.value
    )
    return _build_flag(
        user_id=user.id,
        flag_type=FlagType.HRV_DROP.value,
        severity=severity,
        context={
            "today_hrv": metric.hrv_overnight,
            "baseline_7day": metric.hrv_baseline_7day,
            "drop_pct": round(drop_pct * 100, 1),
            "metric_date": metric.date.isoformat() if metric.date else None,
        },
    )


async def _check_rhr_rise(
    db: AsyncSession,
    user: User,
    metric: GarminDailyMetric,
) -> Optional[AnomalyFlag]:
    """today's RHR vs median of past 7 days. +5 bpm → flag."""
    if not metric.resting_heart_rate:
        return None
    cutoff = (metric.date or datetime.now(timezone.utc).date()) - timedelta(days=7)
    result = await db.execute(
        select(GarminDailyMetric.resting_heart_rate)
        .where(
            GarminDailyMetric.user_id == user.id,
            GarminDailyMetric.date >= cutoff,
            GarminDailyMetric.date < metric.date,
            GarminDailyMetric.resting_heart_rate.is_not(None),
        )
    )
    samples = [int(r[0]) for r in result.all() if r[0]]
    if len(samples) < 3:
        return None
    median = statistics.median(samples)
    delta = metric.resting_heart_rate - median
    if delta < _RHR_RISE_BPM:
        return None
    return _build_flag(
        user_id=user.id,
        flag_type=FlagType.RHR_RISE.value,
        severity=FlagSeverity.WARNING.value,
        context={
            "today_rhr": metric.resting_heart_rate,
            "median_7day": median,
            "delta_bpm": int(delta),
        },
    )


def _check_sleep_deficit(user: User, metric: GarminDailyMetric) -> Optional[AnomalyFlag]:
    """<6h actual sleep OR sleep_score < 60 → flag."""
    short_sleep = (
        metric.sleep_duration_minutes is not None
        and metric.sleep_duration_minutes < _SLEEP_MIN_HOURS * 60
    )
    poor_score = metric.sleep_score is not None and metric.sleep_score < _SLEEP_SCORE_FLOOR
    if not (short_sleep or poor_score):
        return None
    return _build_flag(
        user_id=user.id,
        flag_type=FlagType.SLEEP_DEFICIT.value,
        severity=FlagSeverity.INFO.value,  # informational unless multiple consecutive days
        context={
            "sleep_hours": round((metric.sleep_duration_minutes or 0) / 60, 1),
            "sleep_score": metric.sleep_score,
            "short_sleep": short_sleep,
            "poor_score": poor_score,
        },
    )


# ── Pattern detectors ──────────────────────────────────────────────────────

async def _check_missed_workouts(db: AsyncSession, user: User) -> Optional[AnomalyFlag]:
    """
    Proxy heuristic since we don't have plan structure on the backend:
    expected runs/week = (runs in past 28 days) / 4
    actual runs in past 7 days < 60% of expected → flag.
    Skipped if expected baseline < 3 runs/week (athlete just getting started).
    """
    today = datetime.now(timezone.utc)
    baseline_start = today - timedelta(days=_FREQUENCY_BASELINE_DAYS)
    recent_start = today - timedelta(days=_PATTERN_LOOKBACK_DAYS)

    baseline_count_q = select(func.count(Run.id)).where(
        Run.user_id == user.id,
        Run.completed_at >= baseline_start,
        Run.completed_at < recent_start,
    )
    recent_count_q = select(func.count(Run.id)).where(
        Run.user_id == user.id,
        Run.completed_at >= recent_start,
    )
    baseline_count = (await db.execute(baseline_count_q)).scalar_one() or 0
    recent_count = (await db.execute(recent_count_q)).scalar_one() or 0

    expected_per_week = baseline_count / 3.0  # 21 days of baseline → /3 for weekly rate
    if expected_per_week < 3:
        return None
    if recent_count >= expected_per_week * _MISSED_PROXY_FLOOR_PCT:
        return None
    missed_estimate = max(1, int(round(expected_per_week - recent_count)))
    severity = FlagSeverity.WARNING.value if missed_estimate >= 2 else FlagSeverity.INFO.value
    return _build_flag(
        user_id=user.id,
        flag_type=FlagType.MISSED_WORKOUTS.value,
        severity=severity,
        context={
            "recent_count": int(recent_count),
            "expected_per_week": round(expected_per_week, 1),
            "missed_estimate": missed_estimate,
            "lookback_days": _PATTERN_LOOKBACK_DAYS,
            "baseline_window_days": _FREQUENCY_BASELINE_DAYS,
        },
    )


async def _check_pain_logged(db: AsyncSession, user: User) -> Optional[AnomalyFlag]:
    """
    Phase 4: examine recent wellness check-ins. Returns:
      - warning if any wellness entry in past 48h has soreness ≥ 4 OR has both
        a pain keyword AND a body-part token in notes.
      - warning_plus if the SAME body part has been flagged on 3+ different
        days in the past 14 days (indicates a chronic, escalating signal).
    """
    from collections import Counter

    from app.models.wellness_checkin import WellnessCheckin

    now = datetime.now(timezone.utc)
    cutoff_48h = now - timedelta(hours=48)
    cutoff_14d = now - timedelta(days=14)

    # Recent (48h) check-ins → warning trigger
    result_48 = await db.execute(
        select(WellnessCheckin).where(
            WellnessCheckin.user_id == user.id,
            WellnessCheckin.submitted_at >= cutoff_48h,
        )
    )
    recent = list(result_48.scalars().all())

    triggered_recent = False
    matched_areas_recent: list[str] = []
    matched_pain_recent: list[str] = []
    notes_with_pain_count = 0
    for r in recent:
        if (r.soreness or 0) >= 4:
            triggered_recent = True
            matched_areas_recent.extend(r.soreness_areas or [])
        # Defer the keyword check so we don't import wellness_service at module load
        from app.services.wellness_service import concern_keywords_match
        kw = concern_keywords_match(r.notes)
        if kw["has_pain_word"] and kw["has_body_part"]:
            triggered_recent = True
            matched_pain_recent.extend(kw["matched_pain"])
            matched_areas_recent.extend(kw["matched_body"])
            notes_with_pain_count += 1

    if not triggered_recent:
        return None

    # Past 14d for body-part frequency
    result_14d = await db.execute(
        select(WellnessCheckin).where(
            WellnessCheckin.user_id == user.id,
            WellnessCheckin.submitted_at >= cutoff_14d,
        )
    )
    rows_14d = list(result_14d.scalars().all())

    body_day_counter: Counter = Counter()
    for r in rows_14d:
        day = r.date.isoformat() if r.date else None
        for a in (r.soreness_areas or []):
            body_day_counter[(a, day)] += 1
    # Distinct days per area
    area_distinct_days: Counter = Counter()
    for (area, day), _ in body_day_counter.items():
        if day is not None:
            area_distinct_days[area] += 1

    chronic_areas = [a for a, count in area_distinct_days.items() if count >= 3]

    severity = (
        FlagSeverity.WARNING_PLUS.value
        if chronic_areas
        else FlagSeverity.WARNING.value
    )
    return _build_flag(
        user_id=user.id,
        flag_type=FlagType.PAIN_LOGGED.value,
        severity=severity,
        context={
            "matched_areas_recent": list({a for a in matched_areas_recent if a}),
            "matched_pain_keywords_recent": list({p for p in matched_pain_recent if p}),
            "chronic_areas_14d": chronic_areas,
            "notes_with_pain_recent": notes_with_pain_count,
        },
    )


async def _check_strength_skips(db: AsyncSession, user: User) -> Optional[AnomalyFlag]:
    """
    Phase 9: skipped strength sessions. 2+ skipped gym sessions in past 7d → warning.
    Lazy import to avoid circular imports at module load.
    """
    from app.services.strength_service import compute_skip_count
    result = await compute_skip_count(db, user.id, days=7)
    skip_count = result.get("skip_count", 0)
    if skip_count < 2:
        return None
    return _build_flag(
        user_id=user.id,
        flag_type=FlagType.STRENGTH_SKIPS.value,
        severity=FlagSeverity.WARNING.value,
        context=result,
    )


async def _check_lea_pattern(db: AsyncSession, user: User) -> Optional[AnomalyFlag]:
    """
    Phase 6: detect Low Energy Availability via the multi-signal heuristic in
    nutrition_service.check_lea_signals. ≥3 signals over 14 days → critical
    flag (which combined with the foundation safety prompts triggers Phase 3's
    red_flag override regardless of pause / shadow mode).
    """
    from app.services.nutrition_service import check_lea_signals

    result = await check_lea_signals(db, user, window_days=14)
    if not result.get("is_critical"):
        # 1-2 signals: noted in audit at warning level but doesn't escalate
        if result.get("signal_count", 0) >= 1:
            return _build_flag(
                user_id=user.id,
                flag_type=FlagType.LEA_PATTERN.value,
                severity=FlagSeverity.WARNING.value,
                context=result,
            )
        return None

    return _build_flag(
        user_id=user.id,
        flag_type=FlagType.LEA_PATTERN.value,
        severity=FlagSeverity.CRITICAL.value,
        context=result,
    )


# ── Helpers ────────────────────────────────────────────────────────────────

def _build_flag(
    *,
    user_id: UUID,
    flag_type: str,
    severity: str,
    context: dict,
    workout_id: Optional[UUID] = None,
) -> AnomalyFlag:
    return AnomalyFlag(
        user_id=user_id,
        flag_type=flag_type,
        severity=severity,
        workout_id=workout_id,
        context=context,
    )


async def _persist_if_new(db: AsyncSession, flag: AnomalyFlag) -> bool:
    """
    Insert the flag unless an unresolved active flag of the same type exists
    within the dedup window. Returns True if persisted.
    """
    cutoff = datetime.now(timezone.utc) - timedelta(hours=_DEDUP_WINDOW_HOURS)
    result = await db.execute(
        select(AnomalyFlag.id).where(
            AnomalyFlag.user_id == flag.user_id,
            AnomalyFlag.flag_type == flag.flag_type,
            AnomalyFlag.resolved_at.is_(None),
            AnomalyFlag.raised_at >= cutoff,
        ).limit(1)
    )
    if result.scalar_one_or_none() is not None:
        return False
    db.add(flag)
    await db.flush()
    logger.info("Anomaly flag raised: type=%s sev=%s user=%s context=%s", flag.flag_type, flag.severity, flag.user_id, flag.context)
    return True


async def _median_pace_for_type(
    db: AsyncSession,
    user_id: UUID,
    *,
    is_easy: bool,
    days: int,
) -> Optional[float]:
    """Median avg_pace_sec_per_km for runs of similar type in the past `days`."""
    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    if is_easy:
        wanted = ("easy", "recovery", "long")
    else:
        wanted = ("tempo", "threshold", "vo2", "speed")
    result = await db.execute(
        select(Run.avg_pace_sec_per_km, Run.planned_workout_type)
        .where(
            Run.user_id == user_id,
            Run.completed_at >= cutoff,
            Run.avg_pace_sec_per_km.is_not(None),
            Run.planned_workout_type.is_not(None),
        )
    )
    samples = [
        float(row[0]) for row in result.all()
        if row[0] and row[1] and any(k in row[1].lower() for k in wanted)
    ]
    if len(samples) < 3:
        return None
    return float(statistics.median(samples))


def _sum_elevation_gain(splits: list) -> float:
    """Sum positive elevation deltas between consecutive splits."""
    if not splits:
        return 0.0
    total = 0.0
    last = None
    for s in splits:
        elev = s.get("elevation") if isinstance(s, dict) else None
        if elev is None:
            continue
        if last is not None and elev > last:
            total += elev - last
        last = elev
    return total
