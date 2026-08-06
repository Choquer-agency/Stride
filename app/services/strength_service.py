"""
Strength service — log sessions (quick + detailed), seed exercise library on
startup, compute progression / total volume / skip count for the anomaly
engine and weekly review.
"""

import json
import logging
import statistics
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from pathlib import Path
from typing import Optional
from uuid import UUID

from sqlalchemy import desc, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.run import Run
from app.models.strength_exercise import StrengthExercise
from app.models.strength_session import StrengthSession
from app.models.strength_set import StrengthSet
from app.models.user import User

logger = logging.getLogger(__name__)


_LIBRARY_PATH = Path(__file__).resolve().parent.parent / "data" / "strength_exercises.json"


# ── Library seeding ────────────────────────────────────────────────────────

async def seed_library_if_empty(db: AsyncSession) -> int:
    """Idempotent seed — only inserts exercises not already in the table by name."""
    result = await db.execute(select(StrengthExercise.name))
    existing = {row[0] for row in result.all()}

    try:
        records = json.loads(_LIBRARY_PATH.read_text(encoding="utf-8"))
    except Exception:
        logger.exception("Couldn't read strength_exercises.json — library not seeded")
        return 0

    inserted = 0
    for rec in records:
        if rec["name"] in existing:
            continue
        db.add(StrengthExercise(
            name=rec["name"],
            category=rec["category"],
            equipment=rec["equipment"],
            youtube_demo_url=rec.get("youtube_demo_url"),
            default_set_count=rec.get("default_set_count", 3),
            default_rep_range=rec.get("default_rep_range", "8-12"),
        ))
        inserted += 1
    if inserted:
        await db.flush()
    logger.info("Strength library: %d new exercises seeded (%d total)", inserted, len(existing) + inserted)
    return inserted


async def list_library(db: AsyncSession, *, category: Optional[str] = None) -> list[StrengthExercise]:
    q = select(StrengthExercise).order_by(StrengthExercise.category, StrengthExercise.name)
    if category:
        q = q.where(StrengthExercise.category == category)
    result = await db.execute(q)
    return list(result.scalars().all())


# ── Logging ────────────────────────────────────────────────────────────────

async def log_quick_session(
    db: AsyncSession,
    user: User,
    *,
    date,
    planned_workout_id: Optional[UUID] = None,
    perceived_effort: Optional[int] = None,
) -> StrengthSession:
    row = StrengthSession(
        user_id=user.id,
        date=date,
        planned_workout_id=planned_workout_id,
        quick_logged=True,
        perceived_effort=perceived_effort,
    )
    db.add(row)
    await db.flush()
    logger.info("Strength quick-log: user=%s date=%s rpe=%s", user.id, date, perceived_effort)
    return row


async def log_detailed_session(
    db: AsyncSession,
    user: User,
    *,
    date,
    sets: list[dict],
    duration_minutes: Optional[int] = None,
    notes: Optional[str] = None,
    planned_workout_id: Optional[UUID] = None,
) -> StrengthSession:
    """
    `sets` is a list of {exercise_id (UUID), set_number, reps, weight_kg?, rpe?}.
    """
    session = StrengthSession(
        user_id=user.id,
        date=date,
        planned_workout_id=planned_workout_id,
        quick_logged=False,
        duration_minutes=duration_minutes,
        notes=notes,
    )
    db.add(session)
    await db.flush()

    for s in sets:
        weight = s.get("weight_kg")
        db.add(StrengthSet(
            session_id=session.id,
            exercise_id=s["exercise_id"],
            set_number=int(s["set_number"]),
            reps=int(s["reps"]),
            weight_kg=Decimal(str(weight)) if weight is not None else None,
            rpe=int(s["rpe"]) if s.get("rpe") is not None else None,
        ))
    await db.flush()
    logger.info("Strength detailed-log: user=%s date=%s sets=%d", user.id, date, len(sets))
    return session


async def get_last_set_for_exercise(
    db: AsyncSession,
    user_id: UUID,
    exercise_id: UUID,
) -> Optional[StrengthSet]:
    """Most recent set for this user + exercise — used for pre-fill."""
    result = await db.execute(
        select(StrengthSet)
        .join(StrengthSession, StrengthSession.id == StrengthSet.session_id)
        .where(
            StrengthSession.user_id == user_id,
            StrengthSet.exercise_id == exercise_id,
        )
        .order_by(desc(StrengthSession.date), desc(StrengthSet.set_number))
        .limit(1)
    )
    return result.scalar_one_or_none()


# ── Progression + volume ───────────────────────────────────────────────────

async def compute_progression(
    db: AsyncSession,
    user_id: UUID,
    exercise_id: UUID,
    *,
    limit: int = 10,
) -> list[dict]:
    """
    Return the last N sessions' best set for this exercise, oldest first,
    suitable for charting weight × reps over time.
    """
    result = await db.execute(
        select(StrengthSession.id, StrengthSession.date, StrengthSet.reps, StrengthSet.weight_kg, StrengthSet.rpe)
        .join(StrengthSet, StrengthSet.session_id == StrengthSession.id)
        .where(
            StrengthSession.user_id == user_id,
            StrengthSet.exercise_id == exercise_id,
        )
        .order_by(desc(StrengthSession.date))
        .limit(limit * 5)  # over-fetch since multiple sets per session
    )
    rows = list(result.all())

    # Group by session and pick the best set (highest weight × reps)
    by_session: dict = {}
    for sid, sdate, reps, weight, rpe in rows:
        score = float(reps) * float(weight or 0)
        if sid not in by_session or score > by_session[sid]["score"]:
            by_session[sid] = {
                "session_id": sid,
                "date": sdate.isoformat() if sdate else None,
                "reps": int(reps),
                "weight_kg": float(weight) if weight is not None else None,
                "rpe": int(rpe) if rpe is not None else None,
                "score": score,
            }
    sorted_sessions = sorted(by_session.values(), key=lambda r: r["date"] or "")
    return sorted_sessions[-limit:]


async def compute_total_volume_kg(
    db: AsyncSession,
    user_id: UUID,
    *,
    days: int = 7,
) -> float:
    """Total (sets × reps × weight_kg) over the past `days`."""
    cutoff = datetime.now(timezone.utc).date() - timedelta(days=days)
    result = await db.execute(
        select(StrengthSet.reps, StrengthSet.weight_kg)
        .join(StrengthSession, StrengthSession.id == StrengthSet.session_id)
        .where(
            StrengthSession.user_id == user_id,
            StrengthSession.date >= cutoff,
            StrengthSet.weight_kg.is_not(None),
        )
    )
    total = 0.0
    for reps, weight in result.all():
        total += float(reps) * float(weight or 0)
    return total


# ── Skip detection ─────────────────────────────────────────────────────────

async def compute_skip_count(
    db: AsyncSession,
    user_id: UUID,
    *,
    days: int = 7,
) -> dict:
    """
    Estimate skipped gym sessions in the past `days`.
    Proxy: count Run rows in the window flagged with `planned_workout_type` containing
    'gym' or 'strength' that have no matching strength_session on the same date.

    Phase 9 v1 keeps this lightweight — Phase 9.1 follow-up will mirror planned
    Workouts to the backend so we have proper "expected gym session" detection.
    """
    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    cutoff_date = cutoff.date()

    # Pull planned-gym dates (proxy: Runs where planned_workout_type contains gym/strength)
    runs_q = await db.execute(
        select(Run.completed_at, Run.planned_workout_type).where(
            Run.user_id == user_id,
            Run.completed_at >= cutoff,
            Run.planned_workout_type.is_not(None),
        )
    )
    planned_gym_dates: set = set()
    for completed_at, ptype in runs_q.all():
        if not ptype:
            continue
        ptype_lower = ptype.lower()
        if "gym" in ptype_lower or "strength" in ptype_lower:
            planned_gym_dates.add(completed_at.date())

    # Pull logged strength sessions in the same window
    sessions_q = await db.execute(
        select(StrengthSession.date).where(
            StrengthSession.user_id == user_id,
            StrengthSession.date >= cutoff_date,
        )
    )
    logged_dates = {row[0] for row in sessions_q.all()}

    skipped = planned_gym_dates - logged_dates
    return {
        "days": days,
        "planned_gym_dates": sorted(d.isoformat() for d in planned_gym_dates),
        "logged_dates": sorted(d.isoformat() for d in logged_dates),
        "skip_count": len(skipped),
        "skipped_dates": sorted(d.isoformat() for d in skipped),
    }


async def compute_session_count(
    db: AsyncSession,
    user_id: UUID,
    *,
    days: int = 7,
) -> int:
    """Total logged strength sessions in the past `days`."""
    cutoff = datetime.now(timezone.utc).date() - timedelta(days=days)
    result = await db.execute(
        select(StrengthSession.id).where(
            StrengthSession.user_id == user_id,
            StrengthSession.date >= cutoff,
        )
    )
    return len(list(result.all()))
