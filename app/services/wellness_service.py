"""
Wellness service — submit, today, trends, and concern-keyword detection.
"""

import logging
import re
import statistics
from collections import Counter
from datetime import date, datetime, timedelta, timezone
from typing import Optional
from uuid import UUID

from sqlalchemy import desc, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User
from app.models.wellness_checkin import (
    ENTRY_MORNING, ENTRY_POST_RUN, ENTRY_PRE_RUN, WellnessCheckin,
)

logger = logging.getLogger(__name__)


# ── Concern keyword detection ──────────────────────────────────────────────

# Body parts the heuristic recognizes (mirrors iOS chip set)
_BODY_PARTS = {
    "calf", "calves", "knee", "knees", "achilles", "it band", "itb",
    "hip", "hips", "hip flexor", "hamstring", "hamstrings",
    "back", "lower back", "foot", "feet", "glute", "glutes",
    "quad", "quads", "shin", "shins", "ankle", "ankles",
    "hip flexors", "groin", "calf muscle",
}

# Pain words that bump severity even at moderate slider scores
_PAIN_WORDS = {"hurt", "hurts", "hurting", "sharp", "twinge", "twinges",
               "tight", "pulled", "strain", "strained", "tweak", "tweaked",
               "ache", "aches", "aching", "sore", "soreness"}

_PAIN_RE = re.compile(r"\b(" + "|".join(re.escape(w) for w in _PAIN_WORDS) + r")\b", re.IGNORECASE)
_BODY_RE = re.compile(r"\b(" + "|".join(re.escape(w) for w in _BODY_PARTS) + r")\b", re.IGNORECASE)


def concern_keywords_match(notes: Optional[str]) -> dict:
    """
    Returns:
      {
        "has_pain_word": bool,
        "has_body_part": bool,
        "matched_pain": list[str],
        "matched_body": list[str],
      }
    """
    if not notes:
        return {"has_pain_word": False, "has_body_part": False, "matched_pain": [], "matched_body": []}
    pain = list({m.group(0).lower() for m in _PAIN_RE.finditer(notes)})
    body = list({m.group(0).lower() for m in _BODY_RE.finditer(notes)})
    return {
        "has_pain_word": bool(pain),
        "has_body_part": bool(body),
        "matched_pain": pain,
        "matched_body": body,
    }


def is_concerning(checkin: WellnessCheckin) -> bool:
    """Triggers the wellness_concern_check pipeline (Sonnet call + maybe push)."""
    if (checkin.soreness or 0) >= 4:
        return True
    if (checkin.motivation or 99) <= 1:
        return True
    if (checkin.sleep_quality or 99) <= 1:
        return True
    keywords = concern_keywords_match(checkin.notes)
    if keywords["has_pain_word"] and keywords["has_body_part"]:
        return True
    return False


def is_serious_concern(checkin: WellnessCheckin) -> bool:
    """The subset that warrants a push (vs. a quiet card on Run tab). soreness ≥4."""
    return (checkin.soreness or 0) >= 4


# ── Submit ────────────────────────────────────────────────────────────────

async def submit_checkin(
    db: AsyncSession,
    user: User,
    *,
    entry_method: str,
    sleep_quality: Optional[int] = None,
    soreness: Optional[int] = None,
    motivation: Optional[int] = None,
    stress: Optional[int] = None,
    energy: Optional[int] = None,
    soreness_areas: Optional[list[str]] = None,
    notes: Optional[str] = None,
    submission_date: Optional[date] = None,
) -> WellnessCheckin:
    """
    Insert (pre_run/post_run/manual) or upsert (morning) a check-in.
    Morning entries enforce one-per-day via the partial unique index in main.py.
    """
    today = submission_date or datetime.now(timezone.utc).date()

    if entry_method == ENTRY_MORNING:
        # Upsert on the partial unique index. Use ON CONFLICT (user_id, date) DO UPDATE
        # but only when entry_method='morning' — Postgres needs an index match.
        stmt = pg_insert(WellnessCheckin).values(
            user_id=user.id,
            date=today,
            entry_method=ENTRY_MORNING,
            sleep_quality=sleep_quality,
            soreness=soreness,
            motivation=motivation,
            stress=stress,
            energy=energy,
            soreness_areas=soreness_areas or [],
            notes=notes,
        ).on_conflict_do_update(
            index_elements=["user_id", "date"],
            index_where=(WellnessCheckin.entry_method == ENTRY_MORNING),
            set_={
                "sleep_quality": sleep_quality,
                "soreness": soreness,
                "motivation": motivation,
                "stress": stress,
                "energy": energy,
                "soreness_areas": soreness_areas or [],
                "notes": notes,
                "submitted_at": datetime.now(timezone.utc),
            },
        ).returning(WellnessCheckin)
        result = await db.execute(stmt)
        row = result.scalar_one()
    else:
        # Insert (pre_run/post_run/manual allow multiple per day)
        row = WellnessCheckin(
            user_id=user.id,
            date=today,
            entry_method=entry_method,
            sleep_quality=sleep_quality,
            soreness=soreness,
            motivation=motivation,
            stress=stress,
            energy=energy,
            soreness_areas=soreness_areas or [],
            notes=notes,
        )
        db.add(row)
        await db.flush()

    logger.info(
        "Wellness check-in submitted: user=%s method=%s soreness=%s motivation=%s",
        user.id, entry_method, soreness, motivation,
    )
    return row


# ── Today ─────────────────────────────────────────────────────────────────

async def get_today(db: AsyncSession, user_id: UUID, today: Optional[date] = None) -> dict:
    """
    Returns the morning entry for today (or None) plus the list of pre_run /
    post_run entries today. Used by iOS Run tab to decide whether to surface
    the morning card or trigger the pre-run check.
    """
    today = today or datetime.now(timezone.utc).date()
    result = await db.execute(
        select(WellnessCheckin)
        .where(
            WellnessCheckin.user_id == user_id,
            WellnessCheckin.date == today,
        )
    )
    rows = list(result.scalars().all())
    morning = next((r for r in rows if r.entry_method == ENTRY_MORNING), None)
    pre_run = [r for r in rows if r.entry_method == ENTRY_PRE_RUN]
    post_run = [r for r in rows if r.entry_method == ENTRY_POST_RUN]
    return {"morning": morning, "pre_run": pre_run, "post_run": post_run}


async def has_recent_pre_run_entry(db: AsyncSession, user_id: UUID, hours: int = 4) -> bool:
    """Used by iOS to decide whether to skip the pre-run check (already done recently)."""
    cutoff = datetime.now(timezone.utc) - timedelta(hours=hours)
    result = await db.execute(
        select(WellnessCheckin.id).where(
            WellnessCheckin.user_id == user_id,
            WellnessCheckin.entry_method == ENTRY_PRE_RUN,
            WellnessCheckin.submitted_at >= cutoff,
        ).limit(1)
    )
    return result.scalar_one_or_none() is not None


# ── Trends ────────────────────────────────────────────────────────────────

async def compute_trends(db: AsyncSession, user_id: UUID, *, window_days: int = 7) -> dict:
    """
    Rolling averages + most-frequent soreness areas + deltas vs prior window.
    Returns a structured dict ready for either iOS display or prompt input.
    """
    end = datetime.now(timezone.utc).date()
    start = end - timedelta(days=window_days)
    prior_start = start - timedelta(days=window_days)

    current = await _aggregate_window(db, user_id, start, end)
    prior = await _aggregate_window(db, user_id, prior_start, start)

    return {
        "window_days": window_days,
        "current": current,
        "prior": prior,
        "deltas": {
            k: round((current.get(k, 0) or 0) - (prior.get(k, 0) or 0), 2)
            for k in ("sleep_quality_avg", "soreness_avg", "motivation_avg", "stress_avg")
        },
        "frequent_soreness_areas": current.get("frequent_soreness_areas", []),
        "any_pain_keyword_days": current.get("any_pain_keyword_days", 0),
    }


async def _aggregate_window(db: AsyncSession, user_id: UUID, start: date, end: date) -> dict:
    result = await db.execute(
        select(WellnessCheckin).where(
            WellnessCheckin.user_id == user_id,
            WellnessCheckin.date >= start,
            WellnessCheckin.date < end,
        )
    )
    rows = list(result.scalars().all())
    if not rows:
        return {
            "n": 0, "sleep_quality_avg": None, "soreness_avg": None,
            "motivation_avg": None, "stress_avg": None,
            "frequent_soreness_areas": [], "any_pain_keyword_days": 0,
            "notes_concatenated": "",
        }

    def _mean(vals):
        clean = [v for v in vals if v is not None]
        return round(statistics.mean(clean), 2) if clean else None

    sleep = _mean([r.sleep_quality for r in rows])
    soreness = _mean([r.soreness for r in rows])
    motivation = _mean([r.motivation for r in rows])
    stress = _mean([r.stress for r in rows])

    area_counter: Counter = Counter()
    for r in rows:
        for a in (r.soreness_areas or []):
            area_counter[a] += 1
    frequent = [{"area": a, "count": c} for a, c in area_counter.most_common(5)]

    pain_days = sum(1 for r in rows if concern_keywords_match(r.notes)["has_pain_word"])

    notes_blob = "\n".join(r.notes for r in rows if r.notes)

    return {
        "n": len(rows),
        "sleep_quality_avg": sleep,
        "soreness_avg": soreness,
        "motivation_avg": motivation,
        "stress_avg": stress,
        "frequent_soreness_areas": frequent,
        "any_pain_keyword_days": pain_days,
        "notes_concatenated": notes_blob[:2000],  # cap for prompt budget
    }


# ── History list (for Stats tab) ───────────────────────────────────────────

async def get_history(db: AsyncSession, user_id: UUID, limit: int = 30) -> list[WellnessCheckin]:
    result = await db.execute(
        select(WellnessCheckin)
        .where(WellnessCheckin.user_id == user_id)
        .order_by(desc(WellnessCheckin.submitted_at))
        .limit(limit)
    )
    return list(result.scalars().all())
