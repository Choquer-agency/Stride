"""
Focus tracking — parses <focuses>, <focus_outcomes>, <adjustment> JSON tags
from coaching LLM output, persists focuses to weekly_focuses, applies outcomes
to prior focuses, and exposes active focuses for the next prompt's input.
"""

import json
import logging
import re
from datetime import datetime, timedelta, timezone
from typing import Optional
from uuid import UUID

from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.weekly_focus import FocusOutcome, WeeklyFocus

logger = logging.getLogger(__name__)


# ── Tag parsing ────────────────────────────────────────────────────────────

# Each tag opens with `<name>` and closes with `</name>`. JSON inside.
_FOCUSES_RE = re.compile(r"<focuses>\s*(.*?)\s*</focuses>", re.DOTALL)
_OUTCOMES_RE = re.compile(r"<focus_outcomes>\s*(.*?)\s*</focus_outcomes>", re.DOTALL)
_ADJUSTMENT_RE = re.compile(r"<adjustment>\s*(.*?)\s*</adjustment>", re.DOTALL)


def parse_focuses(llm_output: str) -> list[str]:
    """Extract the next-week focuses from `<focuses>[...]</focuses>`. Empty if missing."""
    match = _FOCUSES_RE.search(llm_output or "")
    if not match:
        return []
    try:
        parsed = json.loads(match.group(1))
        if isinstance(parsed, list):
            return [str(item).strip() for item in parsed if str(item).strip()]
    except (json.JSONDecodeError, ValueError):
        logger.warning("Failed to parse focuses JSON: %s", match.group(1)[:120])
    return []


def parse_focus_outcomes(llm_output: str) -> dict[str, str]:
    """
    Extract outcomes for prior focuses from `<focus_outcomes>{...}</focus_outcomes>`.
    Keys are focus IDs (UUID strings). Values are FocusOutcome literal strings.
    """
    match = _OUTCOMES_RE.search(llm_output or "")
    if not match:
        return {}
    try:
        parsed = json.loads(match.group(1))
        if not isinstance(parsed, dict):
            return {}
        valid = {o.value for o in FocusOutcome}
        return {str(k): str(v) for k, v in parsed.items() if str(v) in valid}
    except (json.JSONDecodeError, ValueError):
        logger.warning("Failed to parse focus_outcomes JSON: %s", match.group(1)[:120])
    return {}


def parse_adjustment(llm_output: str) -> Optional[dict]:
    """Extract the optional `<adjustment>{...}</adjustment>` proposal. None if missing."""
    match = _ADJUSTMENT_RE.search(llm_output or "")
    if not match:
        return None
    try:
        parsed = json.loads(match.group(1))
        return parsed if isinstance(parsed, dict) else None
    except (json.JSONDecodeError, ValueError):
        logger.warning("Failed to parse adjustment JSON: %s", match.group(1)[:200])
    return None


def strip_tags(llm_output: str) -> str:
    """Remove all coaching JSON tags from the output for athlete-facing display."""
    out = _FOCUSES_RE.sub("", llm_output or "")
    out = _OUTCOMES_RE.sub("", out)
    out = _ADJUSTMENT_RE.sub("", out)
    return out.strip()


# ── Persistence ────────────────────────────────────────────────────────────

async def persist_focuses(
    db: AsyncSession,
    user_id: UUID,
    raised_in_event_id: UUID,
    focuses: list[str],
) -> list[WeeklyFocus]:
    """Insert one WeeklyFocus row per focus from the just-completed review."""
    rows = [
        WeeklyFocus(
            user_id=user_id,
            raised_in_event_id=raised_in_event_id,
            text=text,
        )
        for text in focuses
        if text.strip()
    ]
    for row in rows:
        db.add(row)
    await db.flush()
    return rows


async def apply_outcomes(
    db: AsyncSession,
    user_id: UUID,
    outcomes: dict[str, str],
    set_by_event_id: UUID,
) -> int:
    """
    Update outcome on prior WeeklyFocus rows. Keys are focus UUID strings.
    Skips outcomes where the focus doesn't belong to this user (defensive).
    Returns the count of rows updated.
    """
    if not outcomes:
        return 0
    updated = 0
    now = datetime.now(timezone.utc)
    for focus_id_str, outcome_value in outcomes.items():
        try:
            focus_id = UUID(focus_id_str)
        except ValueError:
            logger.warning("Invalid focus_id in outcomes: %s", focus_id_str)
            continue
        focus = await db.get(WeeklyFocus, focus_id)
        if focus is None or focus.user_id != user_id:
            continue
        focus.outcome = outcome_value
        focus.outcome_set_at = now
        focus.outcome_event_id = set_by_event_id
        db.add(focus)
        updated += 1
    await db.flush()
    return updated


# ── Active focuses for prompt input ────────────────────────────────────────

async def get_active_focuses(
    db: AsyncSession,
    user_id: UUID,
    weeks_back: int = 4,
) -> list[WeeklyFocus]:
    """
    Return all unresolved focuses raised in the last `weeks_back` weeks, plus the
    most recent batch even if they were resolved (so the next review can confirm
    outcomes one more time when relevant).
    Sorted oldest first so the prompt addresses them in order.
    """
    cutoff = datetime.now(timezone.utc) - timedelta(weeks=weeks_back)
    result = await db.execute(
        select(WeeklyFocus)
        .where(
            WeeklyFocus.user_id == user_id,
            WeeklyFocus.raised_at >= cutoff,
        )
        .order_by(WeeklyFocus.raised_at)
    )
    return list(result.scalars().all())


def format_focuses_for_prompt(focuses: list[WeeklyFocus]) -> str:
    """
    Render active focuses as a markdown block for the prompt input.
    Each line has the focus_id (so the LLM can emit outcomes back), the raised date,
    and the focus text.
    """
    if not focuses:
        return "(no active focuses)"
    lines = []
    for f in focuses:
        date_str = f.raised_at.strftime("%Y-%m-%d") if f.raised_at else "?"
        outcome_marker = ""
        if f.outcome:
            outcome_marker = f" [previously marked {f.outcome}]"
        lines.append(f"- id={f.id}  raised={date_str}  text={f.text!r}{outcome_marker}")
    return "\n".join(lines)
