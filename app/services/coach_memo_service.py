"""
Coach Memo — persistent ~500-word working knowledge the LLM maintains about each athlete.

Loaded into every coaching prompt as `## What you know about this athlete`.
Auto-updated after every weekly review via Haiku.
First memo seeded from athlete profile + recent runs at user creation or first connect.
"""

import logging
from datetime import datetime, timezone
from typing import Optional
from uuid import UUID

from sqlalchemy import select, desc
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.coach_memo import CoachMemo
from app.models.user import User
from app.models.run import Run
from app.services import coaching_models
from app.services.anthropic_client import AnthropicClient
from app.services.prompt_builder import prompt_builder

logger = logging.getLogger(__name__)


async def get_active_memo(db: AsyncSession, user_id: UUID) -> Optional[CoachMemo]:
    """Return the most recently updated memo for a user, or None if none exists."""
    result = await db.execute(
        select(CoachMemo)
        .where(CoachMemo.user_id == user_id)
        .order_by(desc(CoachMemo.updated_at))
        .limit(1)
    )
    return result.scalar_one_or_none()


async def get_memo_text(db: AsyncSession, user_id: UUID) -> str:
    """Convenience: return memo content or empty string. Used by prompt_builder callers."""
    memo = await get_active_memo(db, user_id)
    return memo.content if memo else ""


async def seed_memo_from_profile(db: AsyncSession, user: User) -> CoachMemo:
    """
    Create the first memo for a user from their profile + any logged runs.
    Called on first Garmin connect (Phase 1) or manually for users created
    before v2 ships.
    """
    existing = await get_active_memo(db, user.id)
    if existing:
        return existing

    # Pull last 30 days of runs as initial context
    recent_runs = await _fetch_recent_run_summaries(db, user.id, days=30)

    profile_block = _build_profile_block(user)
    runs_block = _build_runs_block(recent_runs) if recent_runs else "(no runs logged yet)"

    user_prompt = (
        "ATHLETE PROFILE\n"
        f"{profile_block}\n\n"
        "RECENT RUNS (last 30 days)\n"
        f"{runs_block}\n\n"
        "Write the initial coaching memo for this athlete."
    )

    client = AnthropicClient()
    system_prompt = prompt_builder._load_prompt("coach_memo_seed.txt")

    content = await client.generate_plan(
        system_prompt,
        user_prompt,
        name="memo-seed",
        user_id=str(user.id),
        model=coaching_models.MEMO_UPDATE_MODEL,
        metadata={"loop": "memo_seed"},
    )

    memo = CoachMemo(
        user_id=user.id,
        content=content.strip(),
        version=1,
        updated_at=datetime.now(timezone.utc),
        last_event_id=None,
        summary_of={"start": None, "end": None, "kind": "seed"},
    )
    db.add(memo)
    await db.flush()
    logger.info("Seeded memo for user %s (v1, %d chars)", user.id, len(content))
    return memo


async def update_memo(
    db: AsyncSession,
    user_id: UUID,
    triggering_event_id: Optional[UUID],
    triggering_event_output: str,
    summary_range: Optional[dict] = None,
) -> CoachMemo:
    """
    Roll the memo forward given the most recent weekly review (or other triggering event).
    Persists a new memo row (history retained).
    """
    previous = await get_active_memo(db, user_id)
    previous_text = previous.content if previous else "(no prior memo — this is the first update)"

    user_prompt = (
        "PREVIOUS MEMO\n"
        f"{previous_text}\n\n"
        "MOST RECENT WEEKLY REVIEW\n"
        f"{triggering_event_output}\n\n"
        "Write the updated memo."
    )

    client = AnthropicClient()
    system_prompt = prompt_builder.get_memo_update_prompt()

    new_content = await client.generate_plan(
        system_prompt,
        user_prompt,
        name="memo-update",
        user_id=str(user_id),
        model=coaching_models.MEMO_UPDATE_MODEL,
        metadata={"loop": "memo_update", "triggering_event_id": str(triggering_event_id) if triggering_event_id else None},
    )

    next_version = (previous.version + 1) if previous else 1
    memo = CoachMemo(
        user_id=user_id,
        content=new_content.strip(),
        version=next_version,
        updated_at=datetime.now(timezone.utc),
        last_event_id=triggering_event_id,
        summary_of=summary_range or {},
    )
    db.add(memo)
    await db.flush()
    logger.info("Updated memo for user %s (v%d, %d chars)", user_id, next_version, len(new_content))
    return memo


# ── Helpers ──────────────────────────────────────────────────────────────────

async def _fetch_recent_run_summaries(db: AsyncSession, user_id: UUID, days: int) -> list[Run]:
    from datetime import timedelta
    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    result = await db.execute(
        select(Run)
        .where(Run.user_id == user_id, Run.completed_at >= cutoff)
        .order_by(desc(Run.completed_at))
        .limit(40)
    )
    return list(result.scalars().all())


def _build_profile_block(user: User) -> str:
    """Compact one-line-per-field profile summary for the seed prompt."""
    lines = []
    if user.name:
        lines.append(f"Name: {user.name}")
    if user.gender:
        lines.append(f"Gender: {user.gender}")
    if user.date_of_birth:
        lines.append(f"DOB: {user.date_of_birth}")
    if user.height_cm:
        lines.append(f"Height: {user.height_cm}cm")
    if user.bio:
        lines.append(f"Bio: {user.bio}")
    return "\n".join(lines) if lines else "(profile incomplete)"


def _build_runs_block(runs: list[Run]) -> str:
    """One run per line: date, distance, pace, type if known."""
    parts = []
    for r in runs:
        bits = [r.completed_at.strftime("%Y-%m-%d") if r.completed_at else "?"]
        bits.append(f"{r.distance_km:.1f}km")
        if r.avg_pace_sec_per_km:
            mins, secs = divmod(int(r.avg_pace_sec_per_km), 60)
            bits.append(f"{mins}:{secs:02d}/km")
        if r.planned_workout_type:
            bits.append(r.planned_workout_type)
        parts.append(" | ".join(bits))
    return "\n".join(parts)
